"""Two next-action-token models, same interface, one axis of difference: context.

Both operate on the discretized action tokens produced by `data.py` -- the
model itself has no idea whether a vocab entry is "bin (3, 7) of a robot's
2-D action space" or "the letter e"; only the tokenizer knows.

`BigramLM` predicts the next action token from *only* the current one -- an
`nn.Embedding` lookup table, no attention, no position information. It's
what part 1's "linear model" degenerates to once the input is a token
instead of a feature vector: a policy with zero action history.

`TransformerLM` predicts the next action token from the *whole* preceding
window via causal self-attention: every position can look at itself and
everything before it, never after (that's the "causal" mask -- without it
the model could just read the answer off position t+1, i.e. peek at an
action it hasn't taken yet).
"""

import math

import torch
from torch import nn


@torch.no_grad()
def _sample(model: nn.Module, idx: torch.Tensor, max_new_tokens: int, temperature: float, context_size: int):
    for _ in range(max_new_tokens):
        logits = model(idx[:, -context_size:])
        probs = torch.softmax(logits[:, -1] / temperature, dim=-1)
        next_id = torch.multinomial(probs, num_samples=1)
        idx = torch.cat([idx, next_id], dim=1)
    return idx


class BigramLM(nn.Module):
    def __init__(self, vocab_size: int, **_ignored) -> None:
        super().__init__()
        self.vocab_size = vocab_size
        self.table = nn.Embedding(vocab_size, vocab_size)

    def forward(self, idx: torch.Tensor, return_attn: bool = False):
        logits = self.table(idx)
        return (logits, None) if return_attn else logits

    def generate(self, idx: torch.Tensor, max_new_tokens: int, temperature: float = 1.0):
        return _sample(self, idx, max_new_tokens, temperature, context_size=1)


class CausalSelfAttention(nn.Module):
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

    def forward(self, x: torch.Tensor, return_attn: bool = False):
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
        out = self.proj(out)
        return (out, att) if return_attn else (out, None)


class Block(nn.Module):
    def __init__(self, n_embd: int, n_head: int, block_size: int, dropout: float) -> None:
        super().__init__()
        self.ln1 = nn.LayerNorm(n_embd)
        self.attn = CausalSelfAttention(n_embd, n_head, block_size, dropout)
        self.ln2 = nn.LayerNorm(n_embd)
        self.mlp = nn.Sequential(
            nn.Linear(n_embd, 4 * n_embd),
            nn.GELU(),
            nn.Linear(4 * n_embd, n_embd),
            nn.Dropout(dropout),
        )

    def forward(self, x: torch.Tensor, return_attn: bool = False):
        attn_out, attn = self.attn(self.ln1(x), return_attn=return_attn)
        x = x + attn_out
        x = x + self.mlp(self.ln2(x))
        return x, attn


class TransformerLM(nn.Module):
    def __init__(
        self,
        vocab_size: int,
        block_size: int,
        n_embd: int = 128,
        n_head: int = 4,
        n_layer: int = 4,
        dropout: float = 0.0,
        **_ignored,
    ) -> None:
        super().__init__()
        self.block_size = block_size
        self.tok_emb = nn.Embedding(vocab_size, n_embd)
        self.pos_emb = nn.Embedding(block_size, n_embd)
        self.drop = nn.Dropout(dropout)
        self.blocks = nn.ModuleList(
            [Block(n_embd, n_head, block_size, dropout) for _ in range(n_layer)]
        )
        self.ln_f = nn.LayerNorm(n_embd)
        self.head = nn.Linear(n_embd, vocab_size)

    def forward(self, idx: torch.Tensor, return_attn: bool = False):
        _, t = idx.shape
        pos = torch.arange(t, device=idx.device)
        x = self.drop(self.tok_emb(idx) + self.pos_emb(pos))
        last_attn = None
        for block in self.blocks:
            x, attn = block(x, return_attn=return_attn)
            if attn is not None:
                last_attn = attn
        logits = self.head(self.ln_f(x))
        return (logits, last_attn) if return_attn else logits

    def generate(self, idx: torch.Tensor, max_new_tokens: int, temperature: float = 1.0):
        return _sample(self, idx, max_new_tokens, temperature, context_size=self.block_size)


def build_model(model: str, vocab_size: int, block_size: int, **kwargs) -> nn.Module:
    if model == "bigram":
        return BigramLM(vocab_size)
    if model == "transformer":
        return TransformerLM(vocab_size, block_size, **kwargs)
    raise ValueError(f"unknown model: {model!r}")
