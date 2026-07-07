"""The VLA policy: one image + one language instruction + a window of past
action tokens -> the next action-chunk, decoded the same way Part 2's
`TransformerLM` decodes the next action token.

Three encoders feed one fusion decoder:

- `VisionEncoder` is Part 3's `TinyViT` patch-embedding trunk (patchify ->
  linear projection -> non-causal self-attention), minus the classifier
  head -- here it produces a sequence of patch tokens, not a single
  pooled vector, because the decoder needs something to cross-attend
  *into*, not a summary.
- `LanguageEncoder` is the same non-causal self-attention trunk applied to
  word tokens instead of image patches, with a padding mask so the
  (variable-length) instruction's pad tokens don't leak into attention.
- `ActionDecoder` (the bulk of `VLAPolicy`) is Part 2's causal
  self-attention block with one thing spliced in per layer: a
  cross-attention step where every action-token query reads from the
  concatenated [vision tokens; language tokens] context. This is the
  "VLM 式融合" the main design doc calls for -- causal self-attention
  keeps action history from peeking at its own future, cross-attention is
  how it perceives the (fixed, non-causal) image + instruction.

Each of the 7 action axes (x, y, z, roll, pitch, yaw, gripper) gets its own
embedding table on the way in and its own classification head on the way
out -- independent per-axis vocabularies instead of Part 2's single joint
vocabulary (`bins_per_dim ** 2`), because `bins_per_dim ** 7` isn't a vocab
you can put a softmax over. This is the same simplification RT-1/OpenVLA
make when they tokenize multi-dimensional actions.
"""

import math

import torch
from torch import nn

ACTION_DIM = 7


class SelfAttention(nn.Module):
    """Full (non-causal) self-attention with an optional key-padding mask,
    used inside both `VisionEncoder` (no padding -- every patch is real) and
    `LanguageEncoder` (padding masks out the instruction's pad tokens).
    """

    def __init__(self, n_embd: int, n_head: int, dropout: float) -> None:
        super().__init__()
        assert n_embd % n_head == 0
        self.n_head = n_head
        self.head_dim = n_embd // n_head
        self.qkv = nn.Linear(n_embd, 3 * n_embd)
        self.proj = nn.Linear(n_embd, n_embd)
        self.dropout = nn.Dropout(dropout)

    def forward(self, x: torch.Tensor, key_padding_mask: torch.Tensor | None = None):
        b, t, c = x.shape
        q, k, v = self.qkv(x).split(c, dim=2)
        q = q.view(b, t, self.n_head, self.head_dim).transpose(1, 2)
        k = k.view(b, t, self.n_head, self.head_dim).transpose(1, 2)
        v = v.view(b, t, self.n_head, self.head_dim).transpose(1, 2)

        att = (q @ k.transpose(-2, -1)) / math.sqrt(self.head_dim)
        if key_padding_mask is not None:
            att = att.masked_fill(~key_padding_mask[:, None, None, :], float("-inf"))
        att = torch.softmax(att, dim=-1)
        att = self.dropout(att)

        out = (att @ v).transpose(1, 2).contiguous().view(b, t, c)
        return self.proj(out)


class EncoderBlock(nn.Module):
    def __init__(self, n_embd: int, n_head: int, dropout: float) -> None:
        super().__init__()
        self.ln1 = nn.LayerNorm(n_embd)
        self.attn = SelfAttention(n_embd, n_head, dropout)
        self.ln2 = nn.LayerNorm(n_embd)
        self.mlp = nn.Sequential(
            nn.Linear(n_embd, 4 * n_embd),
            nn.GELU(),
            nn.Linear(4 * n_embd, n_embd),
            nn.Dropout(dropout),
        )

    def forward(self, x: torch.Tensor, key_padding_mask: torch.Tensor | None = None):
        x = x + self.attn(self.ln1(x), key_padding_mask=key_padding_mask)
        x = x + self.mlp(self.ln2(x))
        return x


class VisionEncoder(nn.Module):
    """Patchify -> linear projection -> a couple of non-causal self-attention
    blocks -- Part 3's `TinyViT` trunk, without the CLS token or the
    classifier head (the decoder cross-attends into the full patch sequence
    instead of reading a single pooled vector).
    """

    def __init__(
        self,
        image_size: int,
        patch_size: int,
        n_embd: int,
        n_head: int,
        n_layer: int,
        dropout: float,
    ) -> None:
        super().__init__()
        assert image_size % patch_size == 0
        n_patches = (image_size // patch_size) ** 2
        self.patch_embed = nn.Conv2d(3, n_embd, kernel_size=patch_size, stride=patch_size)
        self.pos_emb = nn.Parameter(torch.zeros(1, n_patches, n_embd))
        self.drop = nn.Dropout(dropout)
        self.blocks = nn.ModuleList([EncoderBlock(n_embd, n_head, dropout) for _ in range(n_layer)])
        self.ln_f = nn.LayerNorm(n_embd)

    def forward(self, images: torch.Tensor) -> torch.Tensor:
        x = self.patch_embed(images).flatten(2).transpose(1, 2)  # (B, n_patches, n_embd)
        x = self.drop(x + self.pos_emb)
        for block in self.blocks:
            x = block(x)
        return self.ln_f(x)


class LanguageEncoder(nn.Module):
    """Token + position embedding -> a couple of non-causal self-attention
    blocks -- the same trunk as `VisionEncoder`, just over word tokens
    instead of image patches, with a padding mask instead of none.
    """

    def __init__(
        self, vocab_size: int, max_len: int, n_embd: int, n_head: int, n_layer: int, dropout: float
    ) -> None:
        super().__init__()
        self.tok_emb = nn.Embedding(vocab_size, n_embd, padding_idx=0)
        self.pos_emb = nn.Embedding(max_len, n_embd)
        self.drop = nn.Dropout(dropout)
        self.blocks = nn.ModuleList([EncoderBlock(n_embd, n_head, dropout) for _ in range(n_layer)])
        self.ln_f = nn.LayerNorm(n_embd)

    def forward(self, token_ids: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
        _, t = token_ids.shape
        pos = torch.arange(t, device=token_ids.device)
        x = self.drop(self.tok_emb(token_ids) + self.pos_emb(pos))
        pad_mask = token_ids != 0  # (B, T), True = real token
        for block in self.blocks:
            x = block(x, key_padding_mask=pad_mask)
        return self.ln_f(x), pad_mask


class CausalSelfAttention(nn.Module):
    """Identical to `basic_sequence_bc`'s block: every action-token position
    attends only to itself and earlier positions in the chunk.
    """

    def __init__(self, n_embd: int, n_head: int, block_size: int, dropout: float) -> None:
        super().__init__()
        assert n_embd % n_head == 0
        self.n_head = n_head
        self.head_dim = n_embd // n_head
        self.qkv = nn.Linear(n_embd, 3 * n_embd)
        self.proj = nn.Linear(n_embd, n_embd)
        self.dropout = nn.Dropout(dropout)
        causal_mask = torch.tril(torch.ones(block_size, block_size)).view(
            1, 1, block_size, block_size
        )
        self.register_buffer("causal_mask", causal_mask)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        b, t, c = x.shape
        q, k, v = self.qkv(x).split(c, dim=2)
        q = q.view(b, t, self.n_head, self.head_dim).transpose(1, 2)
        k = k.view(b, t, self.n_head, self.head_dim).transpose(1, 2)
        v = v.view(b, t, self.n_head, self.head_dim).transpose(1, 2)

        att = (q @ k.transpose(-2, -1)) / math.sqrt(self.head_dim)
        att = att.masked_fill(self.causal_mask[:, :, :t, :t] == 0, float("-inf"))
        att = torch.softmax(att, dim=-1)
        att = self.dropout(att)

        out = (att @ v).transpose(1, 2).contiguous().view(b, t, c)
        return self.proj(out)


class CrossAttention(nn.Module):
    """Every action-token query reads from the (fixed, non-causal)
    [vision tokens; language tokens] context -- no causal mask here, since
    the whole context is available regardless of which action step is
    being decoded. `context_mask` blanks out the language side's padding.
    """

    def __init__(self, n_embd: int, n_head: int, dropout: float) -> None:
        super().__init__()
        assert n_embd % n_head == 0
        self.n_head = n_head
        self.head_dim = n_embd // n_head
        self.q_proj = nn.Linear(n_embd, n_embd)
        self.kv_proj = nn.Linear(n_embd, 2 * n_embd)
        self.proj = nn.Linear(n_embd, n_embd)
        self.dropout = nn.Dropout(dropout)

    def forward(
        self,
        x: torch.Tensor,
        context: torch.Tensor,
        context_mask: torch.Tensor | None = None,
        return_attn: bool = False,
    ):
        b, tq, c = x.shape
        tk = context.shape[1]
        q = self.q_proj(x).view(b, tq, self.n_head, self.head_dim).transpose(1, 2)
        k, v = self.kv_proj(context).split(c, dim=2)
        k = k.view(b, tk, self.n_head, self.head_dim).transpose(1, 2)
        v = v.view(b, tk, self.n_head, self.head_dim).transpose(1, 2)

        att = (q @ k.transpose(-2, -1)) / math.sqrt(self.head_dim)
        if context_mask is not None:
            att = att.masked_fill(~context_mask[:, None, None, :], float("-inf"))
        att = torch.softmax(att, dim=-1)
        att = self.dropout(att)

        out = (att @ v).transpose(1, 2).contiguous().view(b, tq, c)
        out = self.proj(out)
        return (out, att) if return_attn else (out, None)


class FusionBlock(nn.Module):
    """Causal self-attention over action history, then cross-attention into
    the multimodal context, then an MLP -- one decoder layer of the VLA.
    """

    def __init__(self, n_embd: int, n_head: int, block_size: int, dropout: float) -> None:
        super().__init__()
        self.ln1 = nn.LayerNorm(n_embd)
        self.self_attn = CausalSelfAttention(n_embd, n_head, block_size, dropout)
        self.ln2 = nn.LayerNorm(n_embd)
        self.cross_attn = CrossAttention(n_embd, n_head, dropout)
        self.ln3 = nn.LayerNorm(n_embd)
        self.mlp = nn.Sequential(
            nn.Linear(n_embd, 4 * n_embd),
            nn.GELU(),
            nn.Linear(4 * n_embd, n_embd),
            nn.Dropout(dropout),
        )

    def forward(
        self,
        x: torch.Tensor,
        context: torch.Tensor,
        context_mask: torch.Tensor | None,
        return_attn: bool = False,
    ):
        x = x + self.self_attn(self.ln1(x))
        cross_out, cross_attn = self.cross_attn(self.ln2(x), context, context_mask, return_attn)
        x = x + cross_out
        x = x + self.mlp(self.ln3(x))
        return x, cross_attn


class VLAPolicy(nn.Module):
    def __init__(
        self,
        vocab_size: int,
        bins_per_dim: int,
        block_size: int,
        image_size: int,
        patch_size: int,
        max_instruction_len: int,
        n_embd: int = 128,
        n_head: int = 4,
        n_vision_layer: int = 2,
        n_lang_layer: int = 2,
        n_action_layer: int = 4,
        dropout: float = 0.0,
        **_ignored,
    ) -> None:
        super().__init__()
        self.bins_per_dim = bins_per_dim
        self.block_size = block_size

        self.vision = VisionEncoder(image_size, patch_size, n_embd, n_head, n_vision_layer, dropout)
        self.language = LanguageEncoder(
            vocab_size, max_instruction_len, n_embd, n_head, n_lang_layer, dropout
        )

        self.action_embed = nn.ModuleList(
            [nn.Embedding(bins_per_dim, n_embd) for _ in range(ACTION_DIM)]
        )
        self.pos_emb = nn.Parameter(torch.zeros(1, block_size, n_embd))
        self.drop = nn.Dropout(dropout)
        self.blocks = nn.ModuleList(
            [FusionBlock(n_embd, n_head, block_size, dropout) for _ in range(n_action_layer)]
        )
        self.ln_f = nn.LayerNorm(n_embd)
        self.heads = nn.ModuleList([nn.Linear(n_embd, bins_per_dim) for _ in range(ACTION_DIM)])

    def encode_context(self, images: torch.Tensor, instruction_ids: torch.Tensor):
        vision_tokens = self.vision(images)  # (B, n_patches, C)
        lang_tokens, lang_mask = self.language(instruction_ids)  # (B, L, C), (B, L)
        context = torch.cat([vision_tokens, lang_tokens], dim=1)
        vision_mask = torch.ones(vision_tokens.shape[:2], dtype=torch.bool, device=images.device)
        context_mask = torch.cat([vision_mask, lang_mask], dim=1)
        return context, context_mask

    def forward(
        self,
        images: torch.Tensor,
        instruction_ids: torch.Tensor,
        action_hist_ids: torch.Tensor,
        return_attn: bool = False,
    ):
        _, t, _ = action_hist_ids.shape
        tok = sum(self.action_embed[d](action_hist_ids[..., d]) for d in range(ACTION_DIM))
        x = self.drop(tok + self.pos_emb[:, :t])

        context, context_mask = self.encode_context(images, instruction_ids)
        last_attn = None
        for block in self.blocks:
            x, attn = block(x, context, context_mask, return_attn=return_attn)
            if attn is not None:
                last_attn = attn
        x = self.ln_f(x)
        logits = torch.stack([head(x) for head in self.heads], dim=2)  # (B, T, ACTION_DIM, bins)
        return (logits, last_attn) if return_attn else logits

    @torch.no_grad()
    def generate(
        self,
        images: torch.Tensor,
        instruction_ids: torch.Tensor,
        prompt_ids: torch.Tensor,
        max_new_tokens: int,
        temperature: float = 1.0,
    ) -> torch.Tensor:
        """Autoregressively roll out `max_new_tokens` more action steps past
        `prompt_ids` (B, t0, ACTION_DIM), one image + instruction read once
        and reused for every step -- same "one glance, act blind for a
        while" assumption training uses, just applied at inference time.
        """
        idx = prompt_ids
        for _ in range(max_new_tokens):
            window = idx[:, -self.block_size :]
            logits = self(images, instruction_ids, window)  # (B, Tw, ACTION_DIM, bins)
            last_logits = logits[:, -1]  # (B, ACTION_DIM, bins)
            probs = torch.softmax(last_logits / temperature, dim=-1)
            next_ids = torch.stack(
                [
                    torch.multinomial(probs[:, d], num_samples=1).squeeze(1)
                    for d in range(ACTION_DIM)
                ],
                dim=-1,
            )  # (B, ACTION_DIM)
            idx = torch.cat([idx, next_ids.unsqueeze(1)], dim=1)
        return idx


def build_model(config: dict, vocab_size: int) -> VLAPolicy:
    return VLAPolicy(
        vocab_size=vocab_size,
        bins_per_dim=config["bins_per_dim"],
        block_size=config["block_size"],
        image_size=config["image_size"],
        patch_size=config["patch_size"],
        max_instruction_len=config["max_instruction_len"],
        n_embd=config["n_embd"],
        n_head=config["n_head"],
        n_vision_layer=config["n_vision_layer"],
        n_lang_layer=config["n_lang_layer"],
        n_action_layer=config["n_action_layer"],
        dropout=config["dropout"],
    )
