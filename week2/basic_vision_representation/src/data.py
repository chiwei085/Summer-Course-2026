"""Single-frame image -> action regression over the same push-T task as
`basic_sequence_bc`. `lerobot/pusht_image` (Hugging Face, LeRobot project)
is the same 206-episode teleoperated push-T demonstrations as
`lerobot/pusht_keypoints`, with a 96x96 RGB rendering of the scene added
per frame -- the image Part 2 explicitly dropped.

Part 3's job is turning that image into a vector a policy can use. The
"encode -> linear head -> action" shape is exactly Part 1's regression
task (a feature vector goes in, a 2-D action comes out); the only new
piece is the encoder that replaces "a feature vector someone already
computed for you" with "a raw image nobody has looked at yet".

No sequence here -- one frame in, one action out, same as Part 1. History
(Part 2) and language (Part 4) are both out of scope; only the input
modality changes.

Held out by *episode*, not by frame: frames from the same trajectory look
almost identical, so a frame-level split would leak validation frames that
are near-duplicates of a training frame one timestep away.
"""

from dataclasses import dataclass

import numpy as np
import torch
from datasets import load_dataset

HF_DATASET = "lerobot/pusht_image"
CANVAS_SIZE = 512.0  # action/state values are pixel coordinates on a 512x512 canvas
IMG_SIZE = 96  # native resolution of the rendered observation
VAL_FRACTION = 0.1


@dataclass
class TaskData:
    images: torch.Tensor  # (N, 3, 96, 96) uint8
    actions: torch.Tensor  # (N, 2) float32, raw pixel coords
    train_idx: torch.Tensor
    val_idx: torch.Tensor

    def normalize_image(self, images: torch.Tensor) -> torch.Tensor:
        return images.float() / 255.0

    def normalize_action(self, actions: torch.Tensor) -> torch.Tensor:
        return actions / CANVAS_SIZE

    def denormalize_action(self, actions: torch.Tensor) -> torch.Tensor:
        return actions * CANVAS_SIZE

    def l2_error_px(self, predicted: torch.Tensor, actual: torch.Tensor) -> float:
        """Mean pixel-space L2 error between normalized ([0, 1]) predicted
        and actual actions.
        """
        return (
            (self.denormalize_action(predicted) - self.denormalize_action(actual))
            .norm(dim=-1)
            .mean()
            .item()
        )


def make_split() -> TaskData:
    dataset = load_dataset(HF_DATASET, split="train")
    episode_index = torch.tensor(dataset["episode_index"])
    actions = torch.tensor(dataset["action"], dtype=torch.float32)
    images = (
        torch.from_numpy(np.stack([np.array(img) for img in dataset["observation.image"]]))
        .permute(0, 3, 1, 2)
        .contiguous()
    )  # (N, H, W, 3) uint8 -> (N, 3, H, W)

    n_episodes = int(episode_index.max().item()) + 1
    n_val = max(1, round(n_episodes * VAL_FRACTION))
    val_mask = (
        episode_index < n_val
    )  # episodes [0, n_val) held out, same convention as basic_sequence_bc
    train_idx = torch.nonzero(~val_mask).squeeze(1)
    val_idx = torch.nonzero(val_mask).squeeze(1)

    return TaskData(images=images, actions=actions, train_idx=train_idx, val_idx=val_idx)


def get_batch(
    data: TaskData,
    indices: torch.Tensor,
    batch_size: int,
    generator: torch.Generator,
) -> tuple[torch.Tensor, torch.Tensor]:
    """Sample `batch_size` random frames from `indices` (train_idx or
    val_idx). Returns raw uint8 images and raw pixel-coordinate actions --
    callers normalize after moving to the training device, so only 1 byte
    per pixel (not 4) crosses the CPU->GPU transfer.
    """
    sel = indices[torch.randint(len(indices), (batch_size,), generator=generator)]
    return data.images[sel], data.actions[sel]
