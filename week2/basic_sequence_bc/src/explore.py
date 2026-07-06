"""Query CLI over a finished run's artifacts/.

Usage (from this directory):
    uv run --project .. python -m src.explore list
    uv run --project .. python -m src.explore metrics --run <run_id>
    uv run --project .. python -m src.explore generate --run <run_id> --episode 0 --prompt-len 8
    uv run --project .. python -m src.explore attention --run <run_id> --episode 0 --start 0
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
        config["vocab_size"],
        config["block_size"],
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


def _val_episode(config: dict, episode: int | None) -> torch.Tensor:
    split = data_mod.make_split(config["bins_per_dim"])
    ep_idx = episode if episode is not None else config["val_episode"]
    if not (0 <= ep_idx < len(split.val_episodes)):
        raise typer.BadParameter(
            f"episode must be in [0, {len(split.val_episodes)}) (held-out episodes only)"
        )
    return split, split.val_episodes[ep_idx]


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
            f"{run_dir.name:32s} model={config['model']:12s} "
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
        f"  perplexity  start={epoch_rows[0]['perplexity']:.2f}  end={last['perplexity']:.2f}"
    )
    typer.echo(
        f"  grad_norm   min={min(r['grad_norm'] for r in epoch_rows):.4f}  "
        f"max={max(r['grad_norm'] for r in epoch_rows):.4f}"
    )


@app.command()
def generate(
    run: str = typer.Option(...),
    episode: int = typer.Option(None, help="held-out episode index; defaults to config's val_episode"),
    prompt_len: int = typer.Option(8, help="real action steps fed as context before rolling out"),
    length: int = typer.Option(50, help="action steps to roll out"),
    temperature: float = typer.Option(0.8),
    epoch: int = typer.Option(None, help="defaults to latest"),
    seed: int = typer.Option(0),
) -> None:
    run_dir, config, target_epoch = _resolve_run(run, epoch)
    split, ep = _val_episode(config, episode)

    prompt_len = min(prompt_len, len(ep) - 1)
    length = min(length, len(ep) - prompt_len)

    torch.manual_seed(seed)
    net = _load_model(run_dir, config, target_epoch)
    idx = ep[:prompt_len].unsqueeze(0)
    rollout = net.generate(idx, length, temperature=temperature)
    predicted_xy = split.decode(rollout[0, prompt_len:])
    actual_xy = split.decode(ep[prompt_len : prompt_len + length])
    l2_error = (predicted_xy - actual_xy).norm(dim=-1).mean().item()

    typer.echo(f"run={run} epoch={target_epoch} temperature={temperature} l2_error={l2_error:.2f}px")
    typer.echo(f"{'step':>4}  {'predicted (x,y)':>18}  {'actual (x,y)':>18}")
    for i, (pred, actual) in enumerate(zip(predicted_xy.tolist(), actual_xy.tolist(), strict=True)):
        typer.echo(
            f"{i:>4}  ({pred[0]:6.1f}, {pred[1]:6.1f})    ({actual[0]:6.1f}, {actual[1]:6.1f})"
        )


@app.command()
def attention(
    run: str = typer.Option(...),
    episode: int = typer.Option(None, help="held-out episode index; defaults to config's val_episode"),
    start: int = typer.Option(0, help="starting frame within the episode"),
    epoch: int = typer.Option(None, help="defaults to latest"),
) -> None:
    run_dir, config, target_epoch = _resolve_run(run, epoch)
    _, ep = _val_episode(config, episode)
    block_size = config["block_size"]
    length = min(block_size, len(ep) - start)
    if length <= 0:
        raise typer.BadParameter(f"start={start} is past the end of episode (len={len(ep)})")

    net = _load_model(run_dir, config, target_epoch)
    idx = ep[start : start + length].unsqueeze(0)
    with torch.no_grad():
        _, attn = net(idx, return_attn=True)
    if attn is None:
        raise typer.BadParameter(f"model {config['model']!r} has no attention to show")
    avg_attn = attn[0].mean(dim=0)  # (t, t), averaged over heads

    typer.echo(
        f"run={run} epoch={target_epoch}: causal attention over action steps "
        f"{start}..{start + length - 1}, rows=query cols=key"
    )
    labels = [f"t{start + i}" for i in range(length)]
    header = "      " + " ".join(f"{lab:>5s}" for lab in labels)
    typer.echo(header)
    for i, row in enumerate(avg_attn.tolist()):
        cells = " ".join(f"{v:5.2f}" for v in row)
        typer.echo(f"{labels[i]:>5s}  {cells}")


if __name__ == "__main__":
    app()
