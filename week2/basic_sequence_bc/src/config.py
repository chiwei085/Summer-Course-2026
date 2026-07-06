"""YAML config resolution, modeled after Ultralytics YOLO's `cfg` module.

Precedence (highest wins):
    1. explicit CLI flags (anything the user actually typed)
    2. `--config <path>` (a user-supplied yaml, only needs to set what it
       overrides -- see configs/transformer.yaml for an example)
    3. configs/default.yaml (every key gets a value from here)

`train.py` exposes each hyperparameter as a Typer option defaulting to
`None`; `None` means "not explicitly passed" and falls through to the yaml
layers below it.
"""

from pathlib import Path
from typing import Any

import yaml

DEFAULT_CONFIG_PATH = Path(__file__).resolve().parent.parent / "configs" / "default.yaml"


def load_config(overrides: dict[str, Any], config_path: str | None = None) -> dict[str, Any]:
    """Merge `configs/default.yaml` <- `--config` file <- CLI overrides."""
    resolved = _read_yaml(DEFAULT_CONFIG_PATH)
    if config_path is not None:
        resolved.update(_read_yaml(Path(config_path)))
    for key, value in overrides.items():
        if value is not None:
            resolved[key] = value
    return resolved


def _read_yaml(path: Path) -> dict[str, Any]:
    if not path.exists():
        raise FileNotFoundError(f"config file not found: {path}")
    return yaml.safe_load(path.read_text(encoding="utf-8")) or {}
