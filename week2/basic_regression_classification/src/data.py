"""Palmer Penguins loading, cleaning, standardization, and fixed splits.

Two tasks share the same underlying table:
  - "classify": species (3-class) from bill_length_mm + flipper_length_mm.
    Deliberately kept to 2 raw features so the decision-boundary snapshot is
    the model's *actual* boundary, not a PCA/embedding projection.
  - "regress": body_mass_g from bill_length_mm + bill_depth_mm + flipper_length_mm.
"""

from dataclasses import dataclass

import numpy as np
import torch
from datasets import load_dataset

HF_DATASET = "SIH/palmer-penguins"

CLASSIFY_FEATURES = ["bill_length_mm", "flipper_length_mm"]
REGRESS_FEATURES = ["bill_length_mm", "bill_depth_mm", "flipper_length_mm"]
REGRESS_TARGET = "body_mass_g"

VAL_FRACTION = 0.2
GRID_RESOLUTION = 120
GRID_PADDING = 0.5  # standardized units


@dataclass
class TaskData:
    task: str
    feature_names: list[str]
    train_x: torch.Tensor
    train_y: torch.Tensor
    val_x: torch.Tensor
    val_y: torch.Tensor
    feature_mean: np.ndarray
    feature_std: np.ndarray
    class_names: list[str] | None = None  # classify only
    target_mean: float | None = None  # regress only
    target_std: float | None = None  # regress only

    def denormalize_target(self, y: torch.Tensor) -> torch.Tensor:
        return y * self.target_std + self.target_mean


def load_penguins():
    df = load_dataset(HF_DATASET)["train"].to_pandas()
    needed = [*CLASSIFY_FEATURES, *REGRESS_FEATURES, REGRESS_TARGET, "species"]
    return df.dropna(subset=list(dict.fromkeys(needed))).reset_index(drop=True)


def _split_indices(
    n: int, seed: int, val_fraction: float = VAL_FRACTION
) -> tuple[np.ndarray, np.ndarray]:
    rng = np.random.default_rng(seed)
    idx = rng.permutation(n)
    n_val = int(round(n * val_fraction))
    return idx[n_val:], idx[:n_val]


def make_classification_split(seed: int = 0) -> TaskData:
    df = load_penguins()
    class_names = sorted(df["species"].unique().tolist())
    class_to_idx = {name: i for i, name in enumerate(class_names)}

    x = df[CLASSIFY_FEATURES].to_numpy(dtype=np.float32)
    y = df["species"].map(class_to_idx).to_numpy(dtype=np.int64)

    train_idx, val_idx = _split_indices(len(df), seed)
    feature_mean = x[train_idx].mean(axis=0)
    feature_std = x[train_idx].std(axis=0)
    x_norm = (x - feature_mean) / feature_std

    return TaskData(
        task="classify",
        feature_names=CLASSIFY_FEATURES,
        train_x=torch.from_numpy(x_norm[train_idx]),
        train_y=torch.from_numpy(y[train_idx]),
        val_x=torch.from_numpy(x_norm[val_idx]),
        val_y=torch.from_numpy(y[val_idx]),
        feature_mean=feature_mean,
        feature_std=feature_std,
        class_names=class_names,
    )


def make_regression_split(seed: int = 0) -> TaskData:
    df = load_penguins()

    x = df[REGRESS_FEATURES].to_numpy(dtype=np.float32)
    y = df[REGRESS_TARGET].to_numpy(dtype=np.float32)

    train_idx, val_idx = _split_indices(len(df), seed)
    feature_mean = x[train_idx].mean(axis=0)
    feature_std = x[train_idx].std(axis=0)
    x_norm = (x - feature_mean) / feature_std

    target_mean = float(y[train_idx].mean())
    target_std = float(y[train_idx].std())
    y_norm = (y - target_mean) / target_std

    return TaskData(
        task="regress",
        feature_names=REGRESS_FEATURES,
        train_x=torch.from_numpy(x_norm[train_idx]),
        train_y=torch.from_numpy(y_norm[train_idx]).unsqueeze(1),
        val_x=torch.from_numpy(x_norm[val_idx]),
        val_y=torch.from_numpy(y_norm[val_idx]).unsqueeze(1),
        feature_mean=feature_mean,
        feature_std=feature_std,
        target_mean=target_mean,
        target_std=target_std,
    )


def make_split(task: str, seed: int = 0) -> TaskData:
    if task == "classify":
        return make_classification_split(seed)
    if task == "regress":
        return make_regression_split(seed)
    raise ValueError(f"unknown task: {task!r}")


def boundary_grid(train_x: torch.Tensor, resolution: int = GRID_RESOLUTION):
    """A fixed 2D grid in standardized feature space, for decision-boundary snapshots.

    Only meaningful for the 2-feature classify task.
    """
    x_np = train_x.numpy()
    x0_min, x0_max = x_np[:, 0].min() - GRID_PADDING, x_np[:, 0].max() + GRID_PADDING
    x1_min, x1_max = x_np[:, 1].min() - GRID_PADDING, x_np[:, 1].max() + GRID_PADDING
    xs = np.linspace(x0_min, x0_max, resolution, dtype=np.float32)
    ys = np.linspace(x1_min, x1_max, resolution, dtype=np.float32)
    xx, yy = np.meshgrid(xs, ys)
    grid = torch.from_numpy(np.stack([xx.ravel(), yy.ravel()], axis=1))
    return xs, ys, grid
