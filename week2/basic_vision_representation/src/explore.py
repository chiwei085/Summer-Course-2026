"""Query CLI over a finished run's artifacts/.

Usage (from this directory):
    uv run --project .. python -m src.explore list
    uv run --project .. python -m src.explore metrics --run <run_id>
    uv run --project .. python -m src.explore predict --run <run_id> --index 0
    uv run --project .. python -m src.explore attention --run <run_id> --index 0
"""

import json
from pathlib import Path

import torch
import typer
import yaml

from src import data as data_mod
from src.models import build_model

app = typer.Typer(add_completion=False, no_args_is_help=True)

ARTIFACTS_ROOT = Path(__file__).resolve().parent.parent / "artifacts"


def _run_dir(run_id: str) -> Path:
    run_dir = ARTIFACTS_ROOT / run_id
    if not run_dir.exists():
        raise typer.BadParameter(f"no such run: {run_id} (see `explore.py list`)")
    return run_dir


def _load_config(run_dir: Path) -> dict:
    return yaml.safe_load((run_dir / "config.yaml").read_text(encoding="utf-8"))


def _load_metrics(run_dir: Path) -> list[dict]:
    with (run_dir / "metrics.jsonl").open(encoding="utf-8") as f:
        return [json.loads(line) for line in f]


def _latest_epoch(run_dir: Path) -> int:
    epochs = [int(p.stem.split("_")[1]) for p in (run_dir / "checkpoints").glob("epoch_*.pt")]
    if not epochs:
        raise typer.BadParameter(f"run {run_dir.name} has no checkpoints yet")
    return max(epochs)


def _load_model(run_dir: Path, config: dict, epoch: int, device: str = "cpu"):
    net = build_model(
        config["model"],
        patch_size=config["patch_size"],
        n_embd=config["n_embd"],
        n_head=config["n_head"],
        n_layer=config["n_layer"],
        dropout=0.0,
    )
    state = torch.load(
        run_dir / "checkpoints" / f"epoch_{epoch}.pt", map_location=device, weights_only=True
    )
    net.load_state_dict(state)
    net.eval()
    return net


def _resolve_run(run: str, epoch: int | None) -> tuple[Path, dict, int]:
    run_dir = _run_dir(run)
    config = _load_config(run_dir)
    target_epoch = epoch or _latest_epoch(run_dir)
    return run_dir, config, target_epoch


@app.command("list")
def list_runs() -> None:
    if not ARTIFACTS_ROOT.exists() or not any(ARTIFACTS_ROOT.iterdir()):
        typer.echo("no runs found under artifacts/")
        return
    for run_dir in sorted(ARTIFACTS_ROOT.iterdir()):
        if not run_dir.is_dir():
            continue
        config = _load_config(run_dir)
        n_checkpoints = len(list((run_dir / "checkpoints").glob("epoch_*.pt")))
        typer.echo(
            f"{run_dir.name:32s} model={config['model']:5s} "
            f"epochs done={n_checkpoints}/{config['epochs']}"
        )


@app.command()
def metrics(
    run: str = typer.Option(...), epoch: int = typer.Option(None, help="defaults to latest")
) -> None:
    run_dir, _, target_epoch = _resolve_run(run, epoch)
    rows = _load_metrics(run_dir)
    epoch_rows = [r for r in rows if r["epoch"] == target_epoch]
    if not epoch_rows:
        raise typer.BadParameter(f"no metrics for epoch {target_epoch}")
    last = epoch_rows[-1]
    typer.echo(f"run={run} epoch={target_epoch} ({len(epoch_rows)} steps)")
    typer.echo(f"  loss        start={epoch_rows[0]['loss']:.4f}  end={last['loss']:.4f}")
    typer.echo(
        f"  l2_error_px start={epoch_rows[0]['l2_error_px']:.2f}  end={last['l2_error_px']:.2f}"
    )
    typer.echo(
        f"  grad_norm   min={min(r['grad_norm'] for r in epoch_rows):.4f}  "
        f"max={max(r['grad_norm'] for r in epoch_rows):.4f}"
    )


@app.command()
def predict(
    run: str = typer.Option(...),
    index: int = typer.Option(0, help="index into the held-out (val) frames"),
    epoch: int = typer.Option(None, help="defaults to latest"),
) -> None:
    run_dir, config, target_epoch = _resolve_run(run, epoch)
    split = data_mod.make_split()
    if not (0 <= index < len(split.val_idx)):
        raise typer.BadParameter(f"index must be in [0, {len(split.val_idx)}) (held-out frames)")

    net = _load_model(run_dir, config, target_epoch)
    frame_idx = split.val_idx[index]
    image = split.images[frame_idx]
    actual = split.actions[frame_idx]

    with torch.no_grad():
        pred = net(split.normalize_image(image.unsqueeze(0)))
    predicted = split.denormalize_action(pred[0])
    l2_error = split.l2_error_px(pred[0], split.normalize_action(actual))

    typer.echo(f"run={run} epoch={target_epoch} val_index={index}")
    typer.echo(f"  actual    (x,y) = ({actual[0]:.1f}, {actual[1]:.1f})")
    typer.echo(f"  predicted (x,y) = ({predicted[0]:.1f}, {predicted[1]:.1f})")
    typer.echo(f"  l2 error        = {l2_error:.2f}px")


@app.command()
def attention(
    run: str = typer.Option(...),
    index: int = typer.Option(0, help="index into the held-out (val) frames"),
    epoch: int = typer.Option(None, help="defaults to latest"),
) -> None:
    run_dir, config, target_epoch = _resolve_run(run, epoch)
    if config["model"] != "vit":
        raise typer.BadParameter("attention is only defined for model='vit' runs (cnn has none)")

    split = data_mod.make_split()
    if not (0 <= index < len(split.val_idx)):
        raise typer.BadParameter(f"index must be in [0, {len(split.val_idx)}) (held-out frames)")

    net = _load_model(run_dir, config, target_epoch)
    frame_idx = split.val_idx[index]
    image = split.normalize_image(split.images[frame_idx].unsqueeze(0))
    grid = net.explain(image)[0]
    side = net.patches_per_side

    typer.echo(
        f"run={run} epoch={target_epoch}: CLS-token attention over the {side}x{side} patch grid"
    )
    for row in grid.tolist():
        typer.echo(" ".join(f"{v:5.2f}" for v in row))


if __name__ == "__main__":
    app()
