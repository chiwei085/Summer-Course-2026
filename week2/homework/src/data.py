"""Image + language instruction + action-history -> next action-chunk: the
full VLA fusion. Part 4 collapses Part 2's action-token sequence and Part
3's image encoder into one model's input, plus a language instruction
neither earlier lab used.

`HuggingFaceVLA/smol-libero` (Hugging Face, LeRobot format) is a compact
LIBERO subset: 50 teleoperated Franka-arm episodes, 7-DoF joint-command
actions, two fixed camera views, and one natural-language task instruction
(`meta/tasks.jsonl` -- a side file, not a parquet column, so it's fetched
separately and joined onto every frame by `task_index`).

Unlike push-T's fixed 512x512 pixel canvas, robot joint commands have no
natural bounded range, so action bins are quantile edges fit on the
training split (per axis) rather than a fixed bin size -- the same
"action tokenization" idea as Part 2, just with a bin boundary that has to
be learned from data instead of assumed from the task geometry.

Every window mirrors an action-chunking policy (ACT/RT-2 style): one
image + one instruction, read once, condition a `block_size`-step action
chunk decoded with the same shifted-by-one teacher forcing Part 2 uses for
its token sequence. The image is the observation at the chunk's first
step, not re-encoded every step -- both the standard action-chunking
assumption (one glance, then act blind for a few steps) and the cheap
thing to compute (one vision-encoder pass per window, not one per step).
"""

import json
import re
from dataclasses import dataclass
from pathlib import Path

import torch
from datasets import load_dataset
from huggingface_hub import hf_hub_download
from torchvision.transforms.v2 import functional as TF

HF_DATASET = "HuggingFaceVLA/smol-libero"
ACTION_DIM = 7  # x, y, z, roll, pitch, yaw, gripper
VAL_FRACTION = 0.1
PAD_ID = 0  # instruction padding token id (0 is never assigned to a real word)


@dataclass
class TaskData:
    vocab_size: int
    bins_per_dim: int
    bin_centers: torch.Tensor  # (ACTION_DIM, bins_per_dim), bin index -> raw action value
    bin_boundaries: torch.Tensor  # (ACTION_DIM, bins_per_dim - 1), for encode()
    word_to_id: dict[str, int]
    images: torch.Tensor  # (N, 3, image_size, image_size) uint8
    actions: torch.Tensor  # (N, ACTION_DIM) float32, raw robot units
    instructions: list[str]  # per-frame task text (same length as images/actions)
    episode_bounds: dict[int, tuple[int, int]]  # episode id -> [start, end) frame index
    train_episodes: list[int]
    val_episodes: list[int]

    def encode_actions(self, actions: torch.Tensor) -> torch.Tensor:
        """(n, ACTION_DIM) float32 -> (n, ACTION_DIM) long token ids."""
        return torch.stack(
            [
                torch.bucketize(actions[:, d].contiguous(), self.bin_boundaries[d])
                for d in range(ACTION_DIM)
            ],
            dim=-1,
        )

    def decode_actions(self, ids: torch.Tensor) -> torch.Tensor:
        """(..., ACTION_DIM) long token ids -> (..., ACTION_DIM) float32 (bin centers)."""
        return torch.stack([self.bin_centers[d][ids[..., d]] for d in range(ACTION_DIM)], dim=-1)

    def encode_instruction(self, text: str, max_len: int) -> torch.Tensor:
        ids = [self.word_to_id.get(w, PAD_ID) for w in tokenize(text)][:max_len]
        ids += [PAD_ID] * (max_len - len(ids))
        return torch.tensor(ids, dtype=torch.long)

    def normalize_image(self, images: torch.Tensor) -> torch.Tensor:
        return images.float() / 255.0

    def action_l2_error(self, predicted_ids: torch.Tensor, actual_ids: torch.Tensor) -> float:
        """Mean L2 distance in raw action units, averaged over the 7 (mixed-unit)
        axes -- a rough combined signal only, since position (meters), orientation
        (radians), and gripper command aren't on the same scale. Good enough for
        "is the policy converging at all", which is all this homework asks of it.
        """
        return (
            (self.decode_actions(predicted_ids) - self.decode_actions(actual_ids))
            .norm(dim=-1)
            .mean()
            .item()
        )


def tokenize(text: str) -> list[str]:
    return re.findall(r"[a-z0-9]+", text.lower())


def _load_task_texts() -> dict[int, str]:
    path = hf_hub_download(HF_DATASET, "meta/tasks.jsonl", repo_type="dataset")
    tasks = {}
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        row = json.loads(line)
        tasks[row["task_index"]] = row["task"]
    return tasks


def _episode_bounds(episode_index: torch.Tensor) -> dict[int, tuple[int, int]]:
    n_episodes = int(episode_index.max().item()) + 1
    bounds = {}
    for ep in range(n_episodes):
        (idx,) = torch.nonzero(episode_index == ep, as_tuple=True)
        bounds[ep] = (idx[0].item(), idx[-1].item() + 1)
    return bounds


def make_split(bins_per_dim: int, image_size: int, camera: str = "image") -> TaskData:
    dataset = load_dataset(HF_DATASET, split="train")
    task_texts = _load_task_texts()

    episode_index = torch.tensor(dataset["episode_index"])
    actions = torch.tensor(dataset["action"], dtype=torch.float32)
    instructions = [task_texts[t] for t in dataset["task_index"]]
    images = torch.stack(
        [
            TF.resize(TF.pil_to_tensor(img), [image_size, image_size], antialias=True)
            for img in dataset[f"observation.images.{camera}"]
        ]
    )  # (N, 3, image_size, image_size) uint8

    bounds = _episode_bounds(episode_index)
    n_episodes = len(bounds)
    n_val = max(1, round(n_episodes * VAL_FRACTION))
    train_episodes = list(range(n_val, n_episodes))
    val_episodes = list(range(n_val))

    train_mask = episode_index >= n_val
    quantiles = torch.linspace(0, 1, bins_per_dim + 1)
    edges = torch.quantile(actions[train_mask], quantiles, dim=0).T  # (ACTION_DIM, bins+1)
    bin_centers = (edges[:, :-1] + edges[:, 1:]) / 2
    bin_boundaries = edges[:, 1:-1]  # interior thresholds only, for torch.bucketize

    vocab = sorted({w for text in task_texts.values() for w in tokenize(text)})
    word_to_id = {w: i + 1 for i, w in enumerate(vocab)}  # id 0 reserved for padding

    return TaskData(
        vocab_size=len(word_to_id) + 1,
        bins_per_dim=bins_per_dim,
        bin_centers=bin_centers,
        bin_boundaries=bin_boundaries,
        word_to_id=word_to_id,
        images=images,
        actions=actions,
        instructions=instructions,
        episode_bounds=bounds,
        train_episodes=train_episodes,
        val_episodes=val_episodes,
    )


def get_batch(
    data: TaskData,
    episode_ids: list[int],
    block_size: int,
    batch_size: int,
    max_instruction_len: int,
    generator: torch.Generator,
) -> tuple[torch.Tensor, torch.Tensor, torch.Tensor, torch.Tensor]:
    """Sample `batch_size` windows, each `block_size + 1` actions long, from a
    randomly chosen episode in `episode_ids`. Returns:
        images:        (B, 3, image_size, image_size) uint8, the frame at each window's start
        instructions:  (B, max_instruction_len) long token ids
        action_hist:   (B, block_size, ACTION_DIM) long token ids -- the history fed in
        targets:       (B, block_size, ACTION_DIM) long token ids -- action_hist shifted by 1
    """
    usable = [
        ep
        for ep in episode_ids
        if data.episode_bounds[ep][1] - data.episode_bounds[ep][0] > block_size + 1
    ]
    if not usable:
        raise ValueError(f"no episode has more than block_size={block_size} steps")

    images, instructions, action_hist, targets = [], [], [], []
    for _ in range(batch_size):
        ep = usable[torch.randint(len(usable), (1,), generator=generator).item()]
        start, end = data.episode_bounds[ep]
        offset = torch.randint(end - start - block_size - 1, (1,), generator=generator).item()
        t0 = start + offset
        window_ids = data.encode_actions(data.actions[t0 : t0 + block_size + 1])

        images.append(data.images[t0])
        instructions.append(data.encode_instruction(data.instructions[t0], max_instruction_len))
        action_hist.append(window_ids[:-1])
        targets.append(window_ids[1:])

    return (
        torch.stack(images),
        torch.stack(instructions),
        torch.stack(action_hist),
        torch.stack(targets),
    )
