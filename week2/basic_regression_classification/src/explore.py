"""Non-linear query CLI over a finished (or in-progress) run's artifacts/.

Usage (from this directory):
    uv run --project .. python -m src.explore list
    uv run --project .. python -m src.explore metrics --run <run_id>
    uv run --project .. python -m src.explore predict --run <run_id> --index 3
    uv run --project .. python -m src.explore misclassified --run <run_id>
    uv run --project .. python -m src.explore boundary --run <run_id>
    uv run --project .. python -m src.explore compare --run <run_id> --epochs 1,10
    uv run --project .. python -m src.explore serve --run <run_id>
"""

import http.server
import json
import socketserver
from pathlib import Path

import torch
import typer
import yaml

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


@app.command("list")
def list_runs() -> None:
    if not ARTIFACTS_ROOT.exists() or not any(ARTIFACTS_ROOT.iterdir()):
        typer.echo("no runs found under artifacts/")
        return
    for run_dir in sorted(ARTIFACTS_ROOT.iterdir()):
        if not run_dir.is_dir():
            continue
        config = _load_config(run_dir)
        status_path = run_dir / "report" / "status.json"
        status = json.loads(status_path.read_text(encoding="utf-8")) if status_path.exists() else {}
        typer.echo(
            f"{run_dir.name:40s} task={config['task']:9s} model={config['model']:6s} "
            f"epoch={status.get('latest_epoch', '?')}/{config['epochs']} "
            f"running={status.get('running', '?')}"
        )


@app.command()
def metrics(
    run: str = typer.Option(...), epoch: int = typer.Option(None, help="defaults to latest")
) -> None:
    run_dir = _run_dir(run)
    rows = _load_metrics(run_dir)
    target_epoch = epoch or _latest_epoch(run_dir)
    epoch_rows = [r for r in rows if r["epoch"] == target_epoch]
    if not epoch_rows:
        raise typer.BadParameter(f"no metrics for epoch {target_epoch}")
    last = epoch_rows[-1]
    secondary_key = "acc" if "acc" in last else "mae"
    typer.echo(f"run={run} epoch={target_epoch} ({len(epoch_rows)} steps)")
    typer.echo(f"  loss       start={epoch_rows[0]['loss']:.4f}  end={last['loss']:.4f}")
    typer.echo(
        f"  {secondary_key:10s} start={epoch_rows[0][secondary_key]:.4f}  end={last[secondary_key]:.4f}"
    )
    typer.echo(
        f"  grad_norm  min={min(r['grad_norm'] for r in epoch_rows):.4f}  max={max(r['grad_norm'] for r in epoch_rows):.4f}"
    )


@app.command()
def predict(
    run: str = typer.Option(...), index: int = typer.Option(...), epoch: int = typer.Option(None)
) -> None:
    run_dir = _run_dir(run)
    config = _load_config(run_dir)
    target_epoch = epoch or _latest_epoch(run_dir)
    predictions = torch.load(
        run_dir / "samples" / f"epoch_{target_epoch}_predictions.pt", weights_only=True
    )
    features = predictions["features_raw"][index].tolist()
    feature_str = ", ".join(
        f"{n}={v:.2f}" for n, v in zip(config["feature_names"], features, strict=True)
    )
    typer.echo(f"run={run} epoch={target_epoch} val_index={index}")
    typer.echo(f"  features: {feature_str}")
    if config["task"] == "classify":
        class_names = config["class_names"]
        probs = predictions["probs"][index].tolist()
        true_label = class_names[predictions["true"][index].item()]
        pred_label = class_names[predictions["pred"][index].item()]
        prob_str = ", ".join(f"{c}={p:.3f}" for c, p in zip(class_names, probs, strict=True))
        typer.echo(f"  true={true_label}  pred={pred_label}  probs=({prob_str})")
    else:
        typer.echo(
            f"  true={predictions['true'][index].item():.1f}g  pred={predictions['pred'][index].item():.1f}g"
        )


@app.command()
def misclassified(run: str = typer.Option(...), epoch: int = typer.Option(None)) -> None:
    run_dir = _run_dir(run)
    config = _load_config(run_dir)
    if config["task"] != "classify":
        raise typer.BadParameter(
            "`misclassified` only applies to classify runs; try `worst-residuals`"
        )
    target_epoch = epoch or _latest_epoch(run_dir)
    predictions = torch.load(
        run_dir / "samples" / f"epoch_{target_epoch}_predictions.pt", weights_only=True
    )
    class_names = config["class_names"]
    true, pred, probs = predictions["true"], predictions["pred"], predictions["probs"]
    wrong = (true != pred).nonzero(as_tuple=True)[0]
    typer.echo(f"run={run} epoch={target_epoch}: {len(wrong)}/{len(true)} misclassified")
    for i in wrong.tolist():
        conf = probs[i, pred[i]].item()
        typer.echo(
            f"  index={i}: true={class_names[true[i]]} pred={class_names[pred[i]]} confidence={conf:.3f}"
        )


@app.command("worst-residuals")
def worst_residuals(
    run: str = typer.Option(...), epoch: int = typer.Option(None), top: int = typer.Option(10)
) -> None:
    run_dir = _run_dir(run)
    config = _load_config(run_dir)
    if config["task"] != "regress":
        raise typer.BadParameter(
            "`worst-residuals` only applies to regress runs; try `misclassified`"
        )
    target_epoch = epoch or _latest_epoch(run_dir)
    predictions = torch.load(
        run_dir / "samples" / f"epoch_{target_epoch}_predictions.pt", weights_only=True
    )
    residual = (predictions["pred"] - predictions["true"]).squeeze(-1)
    order = torch.argsort(residual.abs(), descending=True)[:top]
    typer.echo(f"run={run} epoch={target_epoch}: top {top} worst residuals (g)")
    for i in order.tolist():
        typer.echo(
            f"  index={i}: true={predictions['true'][i].item():.1f} pred={predictions['pred'][i].item():.1f} "
            f"residual={residual[i].item():+.1f}"
        )


@app.command()
def boundary(run: str = typer.Option(...), epoch: int = typer.Option(None)) -> None:
    run_dir = _run_dir(run)
    config = _load_config(run_dir)
    if config["task"] != "classify":
        raise typer.BadParameter("`boundary` only applies to classify runs")
    target_epoch = epoch or _latest_epoch(run_dir)
    b = torch.load(run_dir / "boundary" / f"epoch_{target_epoch}.pt", weights_only=True)
    class_names = config["class_names"]
    counts = torch.bincount(b["class_grid"].flatten(), minlength=len(class_names))
    typer.echo(
        f"run={run} epoch={target_epoch}: grid {len(b['xs'])}x{len(b['ys'])}, mean confidence={b['confidence_grid'].mean():.3f}"
    )
    for name, count in zip(class_names, counts.tolist(), strict=True):
        typer.echo(f"  {name}: {count} grid cells ({100 * count / counts.sum().item():.1f}%)")


@app.command()
def compare(
    run: str = typer.Option(...), epochs: str = typer.Option(..., help="e.g. 1,10")
) -> None:
    run_dir = _run_dir(run)
    config = _load_config(run_dir)
    e1, e2 = (int(x) for x in epochs.split(","))
    rows = _load_metrics(run_dir)
    secondary_key = "acc" if config["task"] == "classify" else "mae"

    def _summary(e: int) -> dict:
        epoch_rows = [r for r in rows if r["epoch"] == e]
        return {
            "loss": epoch_rows[-1]["loss"],
            secondary_key: epoch_rows[-1][secondary_key],
            "grad_norm_max": max(r["grad_norm"] for r in epoch_rows),
        }

    s1, s2 = _summary(e1), _summary(e2)
    typer.echo(f"run={run}  epoch {e1} -> epoch {e2}")
    for key in s1:
        typer.echo(f"  {key:14s} {s1[key]:.4f} -> {s2[key]:.4f}  (delta {s2[key] - s1[key]:+.4f})")

    if config["task"] == "classify":
        b1 = torch.load(run_dir / "boundary" / f"epoch_{e1}.pt", weights_only=True)["class_grid"]
        b2 = torch.load(run_dir / "boundary" / f"epoch_{e2}.pt", weights_only=True)["class_grid"]
        changed = (b1 != b2).float().mean().item()
        typer.echo(f"  decision boundary: {changed * 100:.1f}% of grid cells changed class")


@app.command()
def serve(run: str = typer.Option(...), port: int = typer.Option(8000)) -> None:
    """Wrap `python -m http.server` rooted at the run's report/ dir.

    Needed because `fetch()` against report/status.json and data/*.json is
    blocked by browser CORS policy on file:// URLs.
    """
    run_dir = _run_dir(run)
    report_dir = run_dir / "report"
    if not report_dir.exists():
        raise typer.BadParameter(f"run {run} has no report/ dir yet")

    handler = lambda *args, **kwargs: http.server.SimpleHTTPRequestHandler(  # noqa: E731
        *args, directory=str(report_dir), **kwargs
    )
    with socketserver.TCPServer(("", port), handler) as httpd:
        typer.echo(f"serving {report_dir} at http://localhost:{port}  (Ctrl-C to stop)")
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            typer.echo("stopped")


if __name__ == "__main__":
    app()
