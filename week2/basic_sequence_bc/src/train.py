"""CLI entry point: hand-rolled training loop for next-action-token prediction.

The corpus is 206 independent trajectories, not a fixed set of i.i.d.
samples, so an "epoch" here means `steps_per_epoch` random-window gradient
steps (windows are drawn from randomly chosen episodes) rather than one pass
over a dataset -- same convention nanoGPT-style char-level tutorials use,
just applied to episodes instead of one long string. Hyperparameters follow
the same `--config` <- `configs/default.yaml` precedence as
`basic_regression_classification`.

Usage (from this directory):
    uv run --project .. python -m src.train --config configs/bigram.yaml
    uv run --project .. python -m src.train --config configs/transformer.yaml
    uv run --project .. python -m src.train --config configs/transformer.yaml --epochs 20
"""

import json
import math
from datetime import datetime
from pathlib import Path

import torch
import typer
import yaml

from src import config as config_mod
from src import data as data_mod
from src import report as report_mod
from src.models import build_model

app = typer.Typer(add_completion=False)

ARTIFACTS_ROOT = Path(__file__).resolve().parent.parent / "artifacts"

HPARAM_FIELDS = [
    "model", "bins_per_dim", "block_size", "n_embd", "n_head", "n_layer", "dropout",
    "epochs", "steps_per_epoch", "lr", "batch_size", "seed",
    "val_episode", "prompt_len", "gen_length", "temperature", "run_id", "device",
]


def _grad_norm(parameters) -> float:
    sq_sums = [p.grad.detach().pow(2).sum() for p in parameters if p.grad is not None]
    return torch.stack(sq_sums).sum().sqrt().item() if sq_sums else 0.0


@app.command()
def main(
    config_path: str = typer.Option(
        None, "--config", "-c", help="yaml file overriding configs/default.yaml"
    ),
    model: str = typer.Option(None, help="bigram | transformer"),
    bins_per_dim: int = typer.Option(None, help="action tokenizer bins per axis"),
    block_size: int = typer.Option(None, help="context window length in action steps"),
    n_embd: int = typer.Option(None, help="embedding dim (transformer only)"),
    n_head: int = typer.Option(None, help="attention heads (transformer only)"),
    n_layer: int = typer.Option(None, help="transformer blocks (transformer only)"),
    dropout: float = typer.Option(None, help="dropout probability (transformer only)"),
    epochs: int = typer.Option(None, help="number of epochs"),
    steps_per_epoch: int = typer.Option(None, help="gradient steps per epoch"),
    lr: float = typer.Option(None, help="Adam learning rate"),
    batch_size: int = typer.Option(None, help="windows per gradient step"),
    seed: int = typer.Option(None, help="random seed for split + init + sampling"),
    val_episode: int = typer.Option(None, help="index into the held-out episodes for the per-epoch rollout sample"),
    prompt_len: int = typer.Option(None, help="real action steps fed as context before rolling out"),
    gen_length: int = typer.Option(None, help="action steps to roll out for the sample"),
    temperature: float = typer.Option(None, help="sampling temperature for rollout"),
    run_id: str = typer.Option(None, help="artifact run id; auto-generated if omitted"),
    device: str = typer.Option(None, help="cuda | cpu; auto-detected if omitted"),
) -> None:
    cli_args = locals()
    cfg = config_mod.load_config(
        {field: cli_args[field] for field in HPARAM_FIELDS},
        config_path=config_path,
    )
    model_name = cfg["model"]
    if model_name not in {"bigram", "transformer"}:
        raise typer.BadParameter("model must be 'bigram' or 'transformer'")

    block_size = cfg["block_size"]
    epochs, steps_per_epoch = cfg["epochs"], cfg["steps_per_epoch"]
    lr, batch_size, seed = cfg["lr"], cfg["batch_size"], cfg["seed"]
    run_id, device = cfg["run_id"], cfg["device"]

    torch.manual_seed(seed)
    dev = torch.device(device or ("cuda" if torch.cuda.is_available() else "cpu"))
    gen = torch.Generator().manual_seed(seed)

    split = data_mod.make_split(cfg["bins_per_dim"])
    net = build_model(
        model_name,
        split.vocab_size,
        block_size,
        n_embd=cfg["n_embd"],
        n_head=cfg["n_head"],
        n_layer=cfg["n_layer"],
        dropout=cfg["dropout"],
    ).to(dev)

    loss_fn = torch.nn.CrossEntropyLoss()
    optimizer = torch.optim.AdamW(net.parameters(), lr=lr)

    resolved_run_id = run_id or f"{model_name}_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    run_dir = ARTIFACTS_ROOT / resolved_run_id
    for sub in ("checkpoints", "samples", "logs"):
        (run_dir / sub).mkdir(parents=True, exist_ok=True)

    config = {
        "run_id": resolved_run_id,
        "model": model_name,
        "vocab_size": split.vocab_size,
        "bins_per_dim": cfg["bins_per_dim"],
        "block_size": block_size,
        "n_embd": cfg["n_embd"],
        "n_head": cfg["n_head"],
        "n_layer": cfg["n_layer"],
        "dropout": cfg["dropout"],
        "epochs": epochs,
        "steps_per_epoch": steps_per_epoch,
        "lr": lr,
        "batch_size": batch_size,
        "seed": seed,
        "device": str(dev),
        "val_episode": cfg["val_episode"],
        "prompt_len": cfg["prompt_len"],
        "gen_length": cfg["gen_length"],
        "temperature": cfg["temperature"],
    }
    (run_dir / "config.yaml").write_text(yaml.safe_dump(config, sort_keys=False), encoding="utf-8")

    metrics_path = run_dir / "metrics.jsonl"
    log_path = run_dir / "logs" / "train.log"
    step = 0
    with (
        metrics_path.open("w", encoding="utf-8") as metrics_f,
        log_path.open("w", encoding="utf-8") as log_f,
    ):
        log_f.write(f"run {resolved_run_id} start model={model_name} device={dev}\n")
        for epoch in range(1, epochs + 1):
            net.train()
            for _ in range(steps_per_epoch):
                xb, yb = data_mod.get_batch(split.train_episodes, block_size, batch_size, gen)
                xb, yb = xb.to(dev), yb.to(dev)
                optimizer.zero_grad()
                logits = net(xb)
                loss = loss_fn(logits.reshape(-1, split.vocab_size), yb.reshape(-1))
                loss.backward()
                gnorm = _grad_norm(net.parameters())

                if not torch.isfinite(loss):
                    log_f.write(f"epoch {epoch} step {step}: non-finite loss, stopping\n")
                    raise RuntimeError("training diverged: non-finite loss")

                optimizer.step()
                step += 1

                metrics_f.write(
                    json.dumps(
                        {
                            "step": step,
                            "epoch": epoch,
                            "loss": loss.item(),
                            "perplexity": math.exp(min(loss.item(), 20.0)),
                            "lr": lr,
                            "grad_norm": gnorm,
                        }
                    )
                    + "\n"
                )
            metrics_f.flush()

            val_loss = _eval_val_loss(net, split, block_size, batch_size, dev, gen)
            torch.save(net.state_dict(), run_dir / "checkpoints" / f"epoch_{epoch}.pt")
            _write_epoch_sample(net, split, cfg, run_dir, epoch, dev, val_loss)
            log_f.write(f"epoch {epoch} done loss={loss.item():.4f} val_loss={val_loss:.4f}\n")
            log_f.flush()
            typer.echo(f"epoch {epoch}/{epochs} loss={loss.item():.4f} val_loss={val_loss:.4f}")

    _write_attention_snapshot(net, split, cfg, run_dir, dev)
    report_mod.write_report(run_dir, config)
    typer.echo(f"done: artifacts written to {run_dir}")


@torch.no_grad()
def _eval_val_loss(net, split, block_size, batch_size, dev, gen) -> float:
    net.eval()
    xb, yb = data_mod.get_batch(split.val_episodes, block_size, batch_size, gen)
    xb, yb = xb.to(dev), yb.to(dev)
    logits = net(xb)
    return torch.nn.functional.cross_entropy(
        logits.reshape(-1, split.vocab_size), yb.reshape(-1)
    ).item()


def _val_episode(split, cfg) -> torch.Tensor:
    return split.val_episodes[cfg["val_episode"] % len(split.val_episodes)]


@torch.no_grad()
def _write_epoch_sample(net, split, cfg, run_dir, epoch, dev, val_loss) -> None:
    """Roll out from a fixed held-out episode: feed the first `prompt_len`
    real action tokens as context, autoregressively predict the rest, and
    compare the predicted trajectory against what the demonstrator actually
    did next -- this is the same "generated sample" every epoch that a
    language-model tutorial would print as text, just decoded back into
    (x, y) pixel coordinates instead of characters.
    """
    net.eval()
    episode = _val_episode(split, cfg)
    prompt_len = min(cfg["prompt_len"], len(episode) - 1)
    gen_length = min(cfg["gen_length"], len(episode) - prompt_len)

    prompt_ids = episode[:prompt_len]
    idx = prompt_ids.unsqueeze(0).to(dev)
    rollout = net.generate(idx, gen_length, temperature=cfg["temperature"])
    predicted_ids = rollout[0, prompt_len:].cpu()
    actual_ids = episode[prompt_len : prompt_len + gen_length]

    predicted_xy = split.decode(predicted_ids)
    actual_xy = split.decode(actual_ids)
    l2_error = (predicted_xy - actual_xy).norm(dim=-1).mean().item()

    payload = {
        "epoch": epoch,
        "val_loss": val_loss,
        "prompt_len": prompt_len,
        "prompt_xy": split.decode(prompt_ids).tolist(),
        "predicted_xy": predicted_xy.tolist(),
        "actual_xy": actual_xy.tolist(),
        "l2_error": l2_error,
    }
    (run_dir / "samples" / f"epoch_{epoch}.json").write_text(json.dumps(payload), encoding="utf-8")


@torch.no_grad()
def _write_attention_snapshot(net, split, cfg, run_dir, dev) -> None:
    """Attention weights over a slice of a real held-out episode, for the
    report's heatmap. Skipped for models with no attention to show (e.g.
    the bigram model), which report `attn=None` from
    `forward(..., return_attn=True)`.
    """
    net.eval()
    episode = _val_episode(split, cfg)
    length = min(cfg["block_size"], len(episode))
    action_ids = episode[:length]
    idx = action_ids.unsqueeze(0).to(dev)
    _, attn = net(idx, return_attn=True)
    if attn is None:
        return
    # attn: (1, n_head, t, t) -> average over heads for a single readable map
    avg_attn = attn[0].mean(dim=0).cpu()
    labels = [f"t{i}" for i in range(length)]
    payload = {"labels": labels, "attn": avg_attn.tolist()}
    (run_dir / "samples" / "attention.json").write_text(json.dumps(payload), encoding="utf-8")


if __name__ == "__main__":
    app()
