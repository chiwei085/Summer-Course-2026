"""CLI entry point: hand-rolled training loop for image -> action regression.

Same `--config` <- `configs/default.yaml` precedence as
`basic_regression_classification` and `basic_sequence_bc`. An "epoch" here
means `steps_per_epoch` random-frame gradient steps (frames are drawn
uniformly from the held-in episodes), same convention `basic_sequence_bc`
uses for its episode corpus.

Usage (from this directory):
    uv run --project .. python -m src.train --config configs/cnn.yaml
    uv run --project .. python -m src.train --config configs/vit.yaml
    uv run --project .. python -m src.train --config configs/vit.yaml --epochs 20
"""

import base64
import io
import json
from datetime import datetime
from pathlib import Path

import torch
import typer
import yaml
from PIL import Image

from src import config as config_mod
from src import data as data_mod
from src import report as report_mod
from src.models import build_model

app = typer.Typer(add_completion=False)

ARTIFACTS_ROOT = Path(__file__).resolve().parent.parent / "artifacts"

HPARAM_FIELDS = [
    "model",
    "patch_size",
    "n_embd",
    "n_head",
    "n_layer",
    "dropout",
    "epochs",
    "steps_per_epoch",
    "lr",
    "batch_size",
    "seed",
    "n_samples",
    "run_id",
    "device",
]


def _grad_norm(parameters) -> float:
    sq_sums = [p.grad.detach().pow(2).sum() for p in parameters if p.grad is not None]
    return torch.stack(sq_sums).sum().sqrt().item() if sq_sums else 0.0


def _image_to_data_uri(image_uint8: torch.Tensor) -> str:
    """(3, H, W) uint8 tensor -> base64 PNG data URI, for embedding directly
    in the static HTML report (no separate image files to serve).
    """
    arr = image_uint8.permute(1, 2, 0).numpy()
    buf = io.BytesIO()
    Image.fromarray(arr).save(buf, format="PNG")
    return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode("ascii")


@app.command()
def main(
    config_path: str = typer.Option(
        None, "--config", "-c", help="yaml file overriding configs/default.yaml"
    ),
    model: str = typer.Option(None, help="cnn | vit"),
    patch_size: int = typer.Option(None, help="ViT patch size in pixels (vit only)"),
    n_embd: int = typer.Option(None, help="embedding dim (vit only)"),
    n_head: int = typer.Option(None, help="attention heads (vit only)"),
    n_layer: int = typer.Option(None, help="transformer blocks (vit only)"),
    dropout: float = typer.Option(None, help="dropout probability (vit only)"),
    epochs: int = typer.Option(None, help="number of epochs"),
    steps_per_epoch: int = typer.Option(None, help="gradient steps per epoch"),
    lr: float = typer.Option(None, help="Adam learning rate"),
    batch_size: int = typer.Option(None, help="frames per gradient step"),
    seed: int = typer.Option(None, help="random seed for split + init + sampling"),
    n_samples: int = typer.Option(
        None, help="held-out images shown in the per-epoch qualitative panel"
    ),
    run_id: str = typer.Option(None, help="artifact run id; auto-generated if omitted"),
    device: str = typer.Option(None, help="cuda | cpu; auto-detected if omitted"),
) -> None:
    cli_args = locals()
    cfg = config_mod.load_config(
        {field: cli_args[field] for field in HPARAM_FIELDS},
        config_path=config_path,
    )
    model_name = cfg["model"]
    if model_name not in {"cnn", "vit"}:
        raise typer.BadParameter("model must be 'cnn' or 'vit'")

    epochs, steps_per_epoch = cfg["epochs"], cfg["steps_per_epoch"]
    lr, batch_size, seed = cfg["lr"], cfg["batch_size"], cfg["seed"]
    run_id, device = cfg["run_id"], cfg["device"]

    torch.manual_seed(seed)
    dev = torch.device(device or ("cuda" if torch.cuda.is_available() else "cpu"))
    gen = torch.Generator().manual_seed(seed)

    typer.echo("loading lerobot/pusht_image ...")
    split = data_mod.make_split()
    net = build_model(
        model_name,
        patch_size=cfg["patch_size"],
        n_embd=cfg["n_embd"],
        n_head=cfg["n_head"],
        n_layer=cfg["n_layer"],
        dropout=cfg["dropout"],
    ).to(dev)

    loss_fn = torch.nn.MSELoss()
    optimizer = torch.optim.AdamW(net.parameters(), lr=lr)

    resolved_run_id = run_id or f"{model_name}_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    run_dir = ARTIFACTS_ROOT / resolved_run_id
    for sub in ("checkpoints", "samples", "logs"):
        (run_dir / sub).mkdir(parents=True, exist_ok=True)

    config = {**cfg, "run_id": resolved_run_id, "device": str(dev)}
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
                xb, yb = data_mod.get_batch(split, split.train_idx, batch_size, gen)
                xb, yb = split.normalize_image(xb.to(dev)), split.normalize_action(yb.to(dev))
                optimizer.zero_grad()
                pred = net(xb)
                loss = loss_fn(pred, yb)
                loss.backward()
                gnorm = _grad_norm(net.parameters())

                if not torch.isfinite(loss):
                    log_f.write(f"epoch {epoch} step {step}: non-finite loss, stopping\n")
                    raise RuntimeError("training diverged: non-finite loss")

                optimizer.step()
                step += 1

                l2_error_px = split.l2_error_px(pred.detach().cpu(), yb.cpu())
                metrics_f.write(
                    json.dumps(
                        {
                            "step": step,
                            "epoch": epoch,
                            "loss": loss.item(),
                            "l2_error_px": l2_error_px,
                            "lr": lr,
                            "grad_norm": gnorm,
                        }
                    )
                    + "\n"
                )
            metrics_f.flush()

            val_loss, val_l2 = _eval_val(net, split, batch_size, dev, gen, loss_fn)
            torch.save(net.state_dict(), run_dir / "checkpoints" / f"epoch_{epoch}.pt")
            _write_epoch_sample(net, split, cfg, run_dir, epoch, dev, gen, val_loss, val_l2)
            log_f.write(
                f"epoch {epoch} done loss={loss.item():.4f} val_loss={val_loss:.4f} val_l2={val_l2:.2f}px\n"
            )
            log_f.flush()
            typer.echo(
                f"epoch {epoch}/{epochs} loss={loss.item():.4f} val_loss={val_loss:.4f} val_l2={val_l2:.2f}px"
            )

    _write_encoder_snapshot(net, split, cfg, run_dir, dev, gen)
    report_mod.write_report(run_dir, config)
    typer.echo(f"done: artifacts written to {run_dir}")


@torch.no_grad()
def _eval_val(net, split, batch_size, dev, gen, loss_fn) -> tuple[float, float]:
    net.eval()
    xb, yb = data_mod.get_batch(split, split.val_idx, batch_size, gen)
    xb, yb = split.normalize_image(xb.to(dev)), split.normalize_action(yb.to(dev))
    pred = net(xb)
    val_loss = loss_fn(pred, yb).item()
    val_l2 = split.l2_error_px(pred.cpu(), yb.cpu())
    return val_loss, val_l2


@torch.no_grad()
def _write_epoch_sample(net, split, cfg, run_dir, epoch, dev, gen, val_loss, val_l2) -> None:
    """A fixed panel of held-out images with the model's predicted action
    point overlaid on the demonstrator's actual next action -- the visual
    equivalent of `basic_sequence_bc`'s per-epoch rollout trajectory plot,
    just a single point per image instead of a trajectory (no history
    here, one frame in, one action out).
    """
    net.eval()
    n = cfg["n_samples"]
    idx = split.val_idx[torch.arange(n) % len(split.val_idx)]
    images = split.images[idx]
    actions = split.actions[idx]

    xb = split.normalize_image(images).to(dev)
    pred = net(xb).cpu()
    predicted_xy = split.denormalize_action(pred)

    payload = {
        "epoch": epoch,
        "val_loss": val_loss,
        "val_l2_error": val_l2,
        "samples": [
            {
                "image": _image_to_data_uri(images[i]),
                "actual_xy": actions[i].tolist(),
                "predicted_xy": predicted_xy[i].tolist(),
            }
            for i in range(n)
        ],
    }
    (run_dir / "samples" / f"epoch_{epoch}.json").write_text(json.dumps(payload), encoding="utf-8")


def _write_encoder_snapshot(net, split, cfg, run_dir, dev, gen) -> None:
    """How the trained encoder looks at one fixed held-out image, via
    `net.explain()` -- ViT reports real CLS-token attention over patches,
    CNN reports input-gradient saliency (it has no attention weights to
    report). Same call site either way; the model decides how to explain
    itself.
    """
    net.eval()
    image = split.images[split.val_idx[0]]
    image_uri = _image_to_data_uri(image)
    xb = split.normalize_image(image.unsqueeze(0)).to(dev)

    grid = net.explain(xb)[0].detach().cpu()
    payload = {"image": image_uri, "kind": cfg["model"], "grid": grid.tolist()}
    (run_dir / "samples" / "encoder_snapshot.json").write_text(
        json.dumps(payload), encoding="utf-8"
    )


if __name__ == "__main__":
    app()
