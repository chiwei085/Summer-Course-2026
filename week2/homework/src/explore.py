"""Query CLI over a finished run's artifacts/.

Usage (from this directory):
    uv run --project .. python -m src.explore list
    uv run --project .. python -m src.explore metrics --run <run_id>
    uv run --project .. python -m src.explore predict --run <run_id> --episode 0 --offset 0
    uv run --project .. python -m src.explore attention --run <run_id> --episode 0 --offset 0
    uv run --project .. python -m src.explore corrupt --run <run_id> --episode 0 --offset 0
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
    net = build_model(config, config["vocab_size"])
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


def _window(config: dict, episode: int | None, offset: int) -> tuple:
    split = data_mod.make_split(
        config["bins_per_dim"], config["image_size"], camera=config["camera"]
    )
    ep = episode if episode is not None else config["val_episode"]
    if not (0 <= ep < len(split.val_episodes)):
        raise typer.BadParameter(
            f"episode must be in [0, {len(split.val_episodes)}) (held-out episodes only)"
        )
    ep_id = split.val_episodes[ep]
    start, end = split.episode_bounds[ep_id]
    block_size = config["block_size"]
    if start + offset + block_size + 1 > end:
        raise typer.BadParameter(f"offset={offset} runs past episode end (len={end - start})")
    t0 = start + offset
    return split, t0


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
        typer.echo(f"{run_dir.name:32s} epochs done={n_checkpoints}/{config['epochs']}")


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
    typer.echo(f"  loss             start={epoch_rows[0]['loss']:.4f}  end={last['loss']:.4f}")
    typer.echo(
        f"  action_l2_error  start={epoch_rows[0]['action_l2_error']:.4f}  end={last['action_l2_error']:.4f}"
    )
    typer.echo(
        f"  grad_norm        min={min(r['grad_norm'] for r in epoch_rows):.4f}  "
        f"max={max(r['grad_norm'] for r in epoch_rows):.4f}"
    )


@app.command()
def predict(
    run: str = typer.Option(...),
    episode: int = typer.Option(
        None, help="index into held-out episodes; defaults to config's val_episode"
    ),
    offset: int = typer.Option(0, help="starting frame offset within the episode"),
    epoch: int = typer.Option(None, help="defaults to latest"),
) -> None:
    run_dir, config, target_epoch = _resolve_run(run, epoch)
    split, t0 = _window(config, episode, offset)
    block_size = config["block_size"]

    net = _load_model(run_dir, config, target_epoch)
    window_ids = split.encode_actions(split.actions[t0 : t0 + block_size + 1])
    images = split.normalize_image(split.images[t0].unsqueeze(0))
    instr = split.encode_instruction(
        split.instructions[t0], config["max_instruction_len"]
    ).unsqueeze(0)
    hist = window_ids[:-1].unsqueeze(0)

    with torch.no_grad():
        logits = net(images, instr, hist)
    predicted = split.decode_actions(logits[0, -1].argmax(dim=-1))
    actual = split.decode_actions(window_ids[-1])
    l2_error = (predicted - actual).norm().item()

    typer.echo(f'run={run} epoch={target_epoch} instruction="{split.instructions[t0]}"')
    typer.echo(f"{'axis':>8}  {'predicted':>10}  {'actual':>10}")
    for label, p, a in zip(
        ["x", "y", "z", "roll", "pitch", "yaw", "gripper"],
        predicted.tolist(),
        actual.tolist(),
        strict=True,
    ):
        typer.echo(f"{label:>8}  {p:10.3f}  {a:10.3f}")
    typer.echo(f"combined L2 error (raw units) = {l2_error:.3f}")


@app.command()
def attention(
    run: str = typer.Option(...),
    episode: int = typer.Option(
        None, help="index into held-out episodes; defaults to config's val_episode"
    ),
    offset: int = typer.Option(0, help="starting frame offset within the episode"),
    epoch: int = typer.Option(None, help="defaults to latest"),
) -> None:
    run_dir, config, target_epoch = _resolve_run(run, epoch)
    split, t0 = _window(config, episode, offset)
    block_size = config["block_size"]

    net = _load_model(run_dir, config, target_epoch)
    window_ids = split.encode_actions(split.actions[t0 : t0 + block_size + 1])
    images = split.normalize_image(split.images[t0].unsqueeze(0))
    instr = split.encode_instruction(
        split.instructions[t0], config["max_instruction_len"]
    ).unsqueeze(0)
    hist = window_ids[:-1].unsqueeze(0)

    with torch.no_grad():
        _, attn = net(images, instr, hist, return_attn=True)
    step_avg = (
        attn[0].mean(dim=0).mean(dim=0)
    )  # (n_patches + L,), averaged over heads and decode steps

    n_patches = (config["image_size"] // config["patch_size"]) ** 2
    vision_share = step_avg[:n_patches].sum().item()
    lang_share = step_avg[n_patches:].sum().item()
    words = data_mod.tokenize(split.instructions[t0])[: config["max_instruction_len"]]
    word_attn = step_avg[n_patches : n_patches + len(words)]

    typer.echo(
        f"run={run} epoch={target_epoch}: cross-attention share -- vision={vision_share:.3f} language={lang_share:.3f}"
    )
    typer.echo("per-word attention:")
    for word, weight in zip(words, word_attn.tolist(), strict=True):
        typer.echo(f"  {word:>15s}  {weight:.4f}")


@app.command()
def corrupt(
    run: str = typer.Option(...),
    episode: int = typer.Option(
        None, help="index into held-out episodes; defaults to config's val_episode"
    ),
    offset: int = typer.Option(0, help="starting frame offset within the episode"),
    noise_std: float = typer.Option(
        0.3, help="std of Gaussian pixel noise added to the (normalized) image"
    ),
    epoch: int = typer.Option(None, help="defaults to latest"),
    seed: int = typer.Option(0),
) -> None:
    """Optional OOD read: corrupt the conditioning image with Gaussian noise
    and compare the predicted action against the clean-image prediction.
    A policy that's actually using the image (not just memorizing the
    constant instruction) should visibly degrade as noise_std grows.
    """
    run_dir, config, target_epoch = _resolve_run(run, epoch)
    split, t0 = _window(config, episode, offset)
    block_size = config["block_size"]

    net = _load_model(run_dir, config, target_epoch)
    window_ids = split.encode_actions(split.actions[t0 : t0 + block_size + 1])
    instr = split.encode_instruction(
        split.instructions[t0], config["max_instruction_len"]
    ).unsqueeze(0)
    hist = window_ids[:-1].unsqueeze(0)
    clean_image = split.normalize_image(split.images[t0].unsqueeze(0))

    torch.manual_seed(seed)
    noisy_image = (clean_image + torch.randn(clean_image.shape) * noise_std).clamp(0, 1)

    with torch.no_grad():
        clean_pred = split.decode_actions(net(clean_image, instr, hist)[0, -1].argmax(dim=-1))
        noisy_pred = split.decode_actions(net(noisy_image, instr, hist)[0, -1].argmax(dim=-1))
    actual = split.decode_actions(window_ids[-1])

    typer.echo(f"run={run} epoch={target_epoch} noise_std={noise_std}")
    typer.echo(f"{'axis':>8}  {'actual':>10}  {'clean pred':>10}  {'noisy pred':>10}")
    for label, a, c, n in zip(
        ["x", "y", "z", "roll", "pitch", "yaw", "gripper"],
        actual.tolist(),
        clean_pred.tolist(),
        noisy_pred.tolist(),
        strict=True,
    ):
        typer.echo(f"{label:>8}  {a:10.3f}  {c:10.3f}  {n:10.3f}")
    typer.echo(f"clean vs actual L2 = {(clean_pred - actual).norm().item():.3f}")
    typer.echo(f"noisy vs actual L2 = {(noisy_pred - actual).norm().item():.3f}")
    typer.echo(
        f"clean vs noisy pred L2 (how much the noise moved the prediction) = {(clean_pred - noisy_pred).norm().item():.3f}"
    )


if __name__ == "__main__":
    app()
