"""
`hidden_dims=[]` degenerates to a single `nn.Linear`, non-empty adds
activation layers in between.
"""

from torch import nn


class MLP(nn.Module):
    def __init__(
        self,
        in_dim: int,
        hidden_dims: list[int],
        out_dim: int,
        activation: type[nn.Module] = nn.ReLU,
    ) -> None:
        super().__init__()
        dims = [in_dim, *hidden_dims, out_dim]
        layers: list[nn.Module] = []
        for i, (a, b) in enumerate(zip(dims[:-1], dims[1:], strict=True)):
            layers.append(nn.Linear(a, b))
            if i < len(dims) - 2:
                layers.append(activation())
        self.net = nn.Sequential(*layers)
        self.hidden_dims = hidden_dims

    def forward(self, x):
        return self.net(x)

    @property
    def is_linear(self) -> bool:
        return len(self.hidden_dims) == 0
