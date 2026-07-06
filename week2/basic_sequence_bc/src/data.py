"""Action tokenizer + episode-aware batching over a real robot demo dataset.

`lerobot/pusht_keypoints` (Hugging Face, part of the LeRobot project) is 206
teleoperated episodes of a 2D "push a T-shaped block to a fixed target"
task, recorded as (state, action) pairs at 10 fps. We only use `action`
here -- a 2-D pixel coordinate on a 512x512 canvas -- and ignore state,
image, and reward: Part 2's job is the sequence mechanism, not perception
(that's Part 3) or state conditioning (that's Part 4's full VLA).

Each action is a continuous 2-D vector. To reuse the exact next-token
prediction machinery a language model uses, we discretize it into a grid of
bins and assign each cell a single integer id -- this is "action
tokenization", the same technique RT-1/RT-2/OpenVLA use to turn continuous
robot actions into a vocabulary a transformer can predict over. Modeling
"next action" becomes modeling "next token": a fixed-length window of past
action tokens goes in, a probability distribution over the next one comes
out.

Episodes are independent trajectories (not one continuous stream like a
book), so batching samples an episode first, then a window inside it --
windows never cross an episode boundary.
"""

from dataclasses import dataclass

import torch
from datasets import load_dataset

HF_DATASET = "lerobot/pusht_keypoints"
CANVAS_SIZE = 512.0  # action values are pixel coordinates on a 512x512 canvas
VAL_FRACTION = 0.1


@dataclass
class TaskData:
    vocab_size: int
    bins_per_dim: int
    train_episodes: list[torch.Tensor]  # each: (len,) token ids
    val_episodes: list[torch.Tensor]

    def encode(self, actions: torch.Tensor) -> torch.Tensor:
        """actions: (n, 2) float32 pixel coords -> (n,) token ids."""
        bin_size = CANVAS_SIZE / self.bins_per_dim
        bins = (actions / bin_size).long().clamp(0, self.bins_per_dim - 1)
        return bins[:, 0] * self.bins_per_dim + bins[:, 1]

    def decode(self, ids: torch.Tensor) -> torch.Tensor:
        """(n,) token ids -> (n, 2) float32 pixel coords (bin centers)."""
        bin_size = CANVAS_SIZE / self.bins_per_dim
        bin_x = ids // self.bins_per_dim
        bin_y = ids % self.bins_per_dim
        return torch.stack([bin_x, bin_y], dim=-1).float() * bin_size + bin_size / 2


def _load_episodes(bins_per_dim: int) -> tuple[list[torch.Tensor], list[torch.Tensor]]:
    dataset = load_dataset(HF_DATASET, split="train")
    episode_index = torch.tensor(dataset["episode_index"])
    actions = torch.tensor(dataset["action"], dtype=torch.float32)

    n_episodes = int(episode_index.max().item()) + 1
    bin_size = CANVAS_SIZE / bins_per_dim
    bins = (actions / bin_size).long().clamp(0, bins_per_dim - 1)
    tokens = bins[:, 0] * bins_per_dim + bins[:, 1]

    episodes = []
    for ep in range(n_episodes):
        episodes.append(tokens[episode_index == ep])

    n_val = max(1, round(n_episodes * VAL_FRACTION))
    return episodes[n_val:], episodes[:n_val]


def make_split(bins_per_dim: int) -> TaskData:
    train_episodes, val_episodes = _load_episodes(bins_per_dim)
    return TaskData(
        vocab_size=bins_per_dim * bins_per_dim,
        bins_per_dim=bins_per_dim,
        train_episodes=train_episodes,
        val_episodes=val_episodes,
    )


def get_batch(
    episodes: list[torch.Tensor],
    block_size: int,
    batch_size: int,
    generator: torch.Generator,
) -> tuple[torch.Tensor, torch.Tensor]:
    """Sample `batch_size` random windows of length `block_size`, each from
    a randomly chosen episode. `y` is `x` shifted one action to the right:
    at every position `t`, `y[t]` is the "next action" target for the
    context `x[:t+1]`. Episodes shorter than `block_size + 1` are skipped.
    """
    usable = [ep for ep in episodes if len(ep) > block_size + 1]
    if not usable:
        raise ValueError(f"no episode has more than block_size={block_size} steps")

    xs, ys = [], []
    for _ in range(batch_size):
        ep_idx = torch.randint(len(usable), (1,), generator=generator).item()
        ep = usable[ep_idx]
        start = torch.randint(len(ep) - block_size - 1, (1,), generator=generator).item()
        xs.append(ep[start : start + block_size])
        ys.append(ep[start + 1 : start + block_size + 1])
    return torch.stack(xs), torch.stack(ys)
