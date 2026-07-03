"""CLI entry point: hand-rolled training loop over Palmer Penguins.

"Hand-rolled" means an explicit `optimizer.zero_grad()/backward()/step()`
loop instead of a Trainer/high-level abstraction -- autograd still does the
actual differentiation.

Hyperparameters: CLI flags override `--config <path>`, which
overrides `configs/default.yaml`. So all of these are equivalent ways to run
the same MLP classify job:
    uv run --project .. python -m src.train --task classify --model mlp --hidden-dims 32,16 --epochs 30
    uv run --project .. python -m src.train --config configs/mlp_classify.yaml
    uv run --project .. python -m src.train --config configs/mlp_classify.yaml --epochs 50

Usage (from this directory):
    uv run --project .. python -m src.train --task classify --model linear
    uv run --project .. python -m src.train --task classify --model mlp --hidden-dims 32,16
    uv run --project .. python -m src.train --task regress --model mlp --hidden-dims 32
    uv run --project .. python -m src.train --config configs/mlp_classify.yaml
"""

import json
from datetime import datetime
from pathlib import Path

import torch
import typer
import yaml
from torch.utils.data import DataLoader, TensorDataset

from src import config as config_mod
from src import data as data_mod
from src import report as report_mod
from src.models import MLP

app = typer.Typer(add_completion=False)

ARTIFACTS_ROOT = Path(__file__).resolve().parent.parent / "artifacts"


def _grad_norm(parameters) -> float:
    total = 0.0
    for p in parameters:
        if p.grad is not None:
            total += p.grad.detach().pow(2).sum().item()
    return total**0.5


@app.command()
def main(
    config_path: str = typer.Option(
        None, "--config", "-c", help="yaml file overriding configs/default.yaml"
    ),
    task: str = typer.Option(None, help="classify | regress"),
    model: str = typer.Option(None, help="linear | mlp"),
    hidden_dims: str = typer.Option(
        None, help="comma-separated hidden sizes; ignored for --model linear"
    ),
    epochs: int = typer.Option(None, help="number of epochs"),
    lr: float = typer.Option(None, help="SGD learning rate"),
    batch_size: int = typer.Option(
        None, help="mini-batch size; 0 means full-batch gradient descent"
    ),
    seed: int = typer.Option(None, help="random seed for split + init + shuffling"),
    run_id: str = typer.Option(None, help="artifact run id; auto-generated if omitted"),
    device: str = typer.Option(None, help="cuda | cpu; auto-detected if omitted"),
) -> None:
    cfg = config_mod.load_config(
        {
            "task": task,
            "model": model,
            "hidden_dims": [int(x) for x in hidden_dims.split(",") if x] if hidden_dims else None,
            "epochs": epochs,
            "lr": lr,
            "batch_size": batch_size,
            "seed": seed,
            "run_id": run_id,
            "device": device,
        },
        config_path=config_path,
    )
    task, model = cfg["task"], cfg["model"]
    epochs, lr, batch_size, seed = cfg["epochs"], cfg["lr"], cfg["batch_size"], cfg["seed"]
    run_id, device = cfg["run_id"], cfg["device"]

    if task not in {"classify", "regress"}:
        raise typer.BadParameter("task must be 'classify' or 'regress'")
    if model not in {"linear", "mlp"}:
        raise typer.BadParameter("model must be 'linear' or 'mlp'")

    torch.manual_seed(seed)
    dev = torch.device(device or ("cuda" if torch.cuda.is_available() else "cpu"))

    split = data_mod.make_split(task, seed=seed)
    hdims = [int(x) for x in cfg["hidden_dims"]] if model == "mlp" else []
    out_dim = len(split.class_names) if task == "classify" else 1
    net = MLP(len(split.feature_names), hdims, out_dim).to(dev)

    loss_fn = torch.nn.CrossEntropyLoss() if task == "classify" else torch.nn.MSELoss()
    optimizer = torch.optim.SGD(net.parameters(), lr=lr)

    bs = batch_size if batch_size > 0 else len(split.train_x)
    loader = DataLoader(
        TensorDataset(split.train_x, split.train_y),
        batch_size=bs,
        shuffle=True,
        generator=torch.Generator().manual_seed(seed),
    )

    resolved_run_id = run_id or f"{task}_{model}_{datetime.now().strftime('%Y%m%d_%H%M%S')}"
    run_dir = ARTIFACTS_ROOT / resolved_run_id
    for sub in ("checkpoints", "samples", "logs"):
        (run_dir / sub).mkdir(parents=True, exist_ok=True)
    if task == "classify":
        (run_dir / "boundary").mkdir(parents=True, exist_ok=True)

    config = {
        "run_id": resolved_run_id,
        "task": task,
        "model": model,
        "hidden_dims": hdims,
        "epochs": epochs,
        "lr": lr,
        "batch_size": bs,
        "seed": seed,
        "device": str(dev),
        "feature_names": split.feature_names,
        "class_names": split.class_names,
        "feature_mean": split.feature_mean.tolist(),
        "feature_std": split.feature_std.tolist(),
        "target_mean": split.target_mean,
        "target_std": split.target_std,
    }
    (run_dir / "config.yaml").write_text(yaml.safe_dump(config, sort_keys=False), encoding="utf-8")
    report_mod.init_report(run_dir, config)

    metrics_path = run_dir / "metrics.jsonl"
    log_path = run_dir / "logs" / "train.log"
    step = 0
    try:
        with (
            metrics_path.open("w", encoding="utf-8") as metrics_f,
            log_path.open("w", encoding="utf-8") as log_f,
        ):
            log_f.write(f"run {resolved_run_id} start task={task} model={model} device={dev}\n")
            for epoch in range(1, epochs + 1):
                net.train()
                for xb, yb in loader:
                    xb, yb = xb.to(dev), yb.to(dev)
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

                    row = {
                        "step": step,
                        "epoch": epoch,
                        "loss": loss.item(),
                        "lr": lr,
                        "grad_norm": gnorm,
                    }
                    if task == "classify":
                        row["acc"] = (pred.argmax(-1) == yb).float().mean().item()
                    else:
                        row["mae"] = (pred - yb).abs().mean().item()
                    metrics_f.write(json.dumps(row) + "\n")
                metrics_f.flush()

                torch.save(net.state_dict(), run_dir / "checkpoints" / f"epoch_{epoch}.pt")
                _write_epoch_samples(net, split, task, run_dir, epoch, dev)
                report_mod.write_epoch_report(
                    run_dir,
                    epoch,
                    task,
                    split.class_names,
                    split.feature_names,
                    split.feature_mean,
                    split.feature_std,
                )
                log_f.write(f"epoch {epoch} done loss={row['loss']:.4f}\n")
                log_f.flush()
                typer.echo(f"epoch {epoch}/{epochs} loss={row['loss']:.4f}")
    finally:
        report_mod.finalize_report(run_dir)

    typer.echo(f"done: artifacts written to {run_dir}")


def _write_epoch_samples(net, split, task, run_dir, epoch, dev) -> None:
    net.eval()
    with torch.no_grad():
        val_x = split.val_x.to(dev)
        pred = net(val_x).cpu()
        features_raw = torch.from_numpy(
            split.val_x.numpy() * split.feature_std + split.feature_mean
        )

        if task == "classify":
            probs = torch.softmax(pred, dim=-1)
            payload = {
                "true": split.val_y,
                "pred": probs.argmax(-1),
                "probs": probs,
                "features_raw": features_raw,
            }
        else:
            payload = {
                "true": split.denormalize_target(split.val_y),
                "pred": split.denormalize_target(pred),
                "features_raw": features_raw,
            }
        torch.save(payload, run_dir / "samples" / f"epoch_{epoch}_predictions.pt")

        if task == "classify":
            xs, ys, grid = data_mod.boundary_grid(split.train_x)
            grid_logits = net(grid.to(dev)).cpu()
            grid_probs = torch.softmax(grid_logits, dim=-1)
            class_grid = grid_probs.argmax(-1).reshape(len(ys), len(xs))
            confidence_grid = grid_probs.max(-1).values.reshape(len(ys), len(xs))
            torch.save(
                {
                    "xs": torch.from_numpy(xs),
                    "ys": torch.from_numpy(ys),
                    "class_grid": class_grid,
                    "confidence_grid": confidence_grid,
                },
                run_dir / "boundary" / f"epoch_{epoch}.pt",
            )


if __name__ == "__main__":
    app()
