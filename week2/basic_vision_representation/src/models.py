"""Two image encoders, same interface, one axis of difference: how they
turn a 96x96 image into a vector for Part 1's regression head (a linear
layer predicting a 2-D action) to consume.

`SmallCNN` stacks strided convolutions -- each halves spatial resolution --
and finishes with a global average pool. Classic convnet perception: local
receptive fields, weights shared across every position, no notion of
"attend to some other part of the image". It has no attention weights to
print, so `explore.py` inspects it via input-gradient saliency instead
(which pixels the loss is most sensitive to).

`TinyViT` patchifies the image into a grid of non-overlapping patches,
linearly embeds each one, and runs them through the *exact*
`CausalSelfAttention` block from Part 2 -- minus the causal mask. A patch
grid has no time order to leak from: there is no "future patch" a raster
scan hasn't produced yet, so nothing needs hiding. Every patch attends to
every other patch, including ones after it in raster order. That contrast
(temporal attention must mask the future; spatial attention has no future
to mask) is the point of this lab, not an implementation detail.
"""

import math

import torch
from torch import nn


class SmallCNN(nn.Module):
    def __init__(self, channels: tuple[int, ...] = (16, 32, 64, 128), **_ignored) -> None:
        super().__init__()
        layers = []
        in_ch = 3
        for out_ch in channels:
            layers += [nn.Conv2d(in_ch, out_ch, kernel_size=3, stride=2, padding=1), nn.ReLU()]
            in_ch = out_ch
        self.conv = nn.Sequential(*layers)
        self.pool = nn.AdaptiveAvgPool2d(1)
        self.head = nn.Linear(channels[-1], 2)

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        pooled = self.pool(self.conv(x)).flatten(
            1
        )  # (B, C, H', W') -> (B, C), the "image as a vector"
        return self.head(pooled)

    def explain(self, x: torch.Tensor) -> torch.Tensor:
        """No attention weights exist for a CNN, so "where is it looking"
        is answered with input-gradient saliency instead: the gradient of
        the predicted action's magnitude with respect to each input pixel,
        i.e. "which pixels would change the prediction the most if
        nudged". Needs autograd even if the caller is inside
        `torch.no_grad()`, hence the explicit `enable_grad`.
        """
        x = x.clone().requires_grad_(True)
        with torch.enable_grad():
            self(x).abs().sum().backward()
        return x.grad.abs().mean(dim=1)  # (B, H, W), averaged over RGB channels


class SelfAttention(nn.Module):
    """Full (non-causal) self-attention -- identical to Part 2's
    `CausalSelfAttention` with the `causal_mask` deleted. Every token
    (patch) can look at every other token.
    """

    def __init__(self, n_embd: int, n_head: int, dropout: float) -> None:
        super().__init__()
        assert n_embd % n_head == 0
        self.n_head = n_head
        self.head_dim = n_embd // n_head
        self.qkv = nn.Linear(n_embd, 3 * n_embd)
        self.proj = nn.Linear(n_embd, n_embd)
        self.dropout = nn.Dropout(dropout)

    def forward(self, x: torch.Tensor, return_attn: bool = False):
        b, t, c = x.shape
        q, k, v = self.qkv(x).split(c, dim=2)
        q = q.view(b, t, self.n_head, self.head_dim).transpose(1, 2)
        k = k.view(b, t, self.n_head, self.head_dim).transpose(1, 2)
        v = v.view(b, t, self.n_head, self.head_dim).transpose(1, 2)

        att = (q @ k.transpose(-2, -1)) / math.sqrt(self.head_dim)
        att = torch.softmax(att, dim=-1)  # no mask: every patch attends to every patch
        att = self.dropout(att)

        out = (att @ v).transpose(1, 2).contiguous().view(b, t, c)
        out = self.proj(out)
        return (out, att) if return_attn else (out, None)


class Block(nn.Module):
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

    def forward(self, x: torch.Tensor, return_attn: bool = False):
        attn_out, attn = self.attn(self.ln1(x), return_attn=return_attn)
        x = x + attn_out
        x = x + self.mlp(self.ln2(x))
        return x, attn


class TinyViT(nn.Module):
    def __init__(
        self,
        img_size: int = 96,
        patch_size: int = 12,
        n_embd: int = 128,
        n_head: int = 4,
        n_layer: int = 4,
        dropout: float = 0.0,
        **_ignored,
    ) -> None:
        super().__init__()
        assert img_size % patch_size == 0
        self.patches_per_side = img_size // patch_size
        n_patches = self.patches_per_side**2
        # a strided conv with kernel == stride is a linear projection of
        # each non-overlapping patch -- the standard ViT "patch embedding"
        self.patch_embed = nn.Conv2d(3, n_embd, kernel_size=patch_size, stride=patch_size)
        self.cls_token = nn.Parameter(torch.zeros(1, 1, n_embd))
        self.pos_emb = nn.Parameter(torch.zeros(1, n_patches + 1, n_embd))
        self.drop = nn.Dropout(dropout)
        self.blocks = nn.ModuleList([Block(n_embd, n_head, dropout) for _ in range(n_layer)])
        self.ln_f = nn.LayerNorm(n_embd)
        self.head = nn.Linear(n_embd, 2)

    def forward(self, x: torch.Tensor, return_attn: bool = False):
        b = x.shape[0]
        patches = self.patch_embed(x).flatten(2).transpose(1, 2)  # (B, n_patches, n_embd)
        cls = self.cls_token.expand(b, -1, -1)
        tokens = torch.cat([cls, patches], dim=1)
        tokens = self.drop(tokens + self.pos_emb)

        last_attn = None
        for block in self.blocks:
            tokens, attn = block(tokens, return_attn=return_attn)
            if attn is not None:
                last_attn = attn
        tokens = self.ln_f(tokens)
        out = self.head(tokens[:, 0])  # CLS token summarizes the whole image
        return (out, last_attn) if return_attn else out

    def explain(self, x: torch.Tensor) -> torch.Tensor:
        """CLS-token attention to every patch, reshaped to the patch grid --
        the same mechanism `basic_sequence_bc` visualizes over time steps,
        here over spatial patches instead.
        """
        with torch.no_grad():
            _, attn = self(x, return_attn=True)
        cls_attn = attn[:, :, 0, 1:].mean(dim=1)  # (B, n_patches), averaged over heads
        return cls_attn.view(-1, self.patches_per_side, self.patches_per_side)


def build_model(model: str, **kwargs) -> nn.Module:
    if model == "cnn":
        return SmallCNN()
    if model == "vit":
        return TinyViT(**kwargs)
    raise ValueError(f"unknown model: {model!r}")
