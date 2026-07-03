"""Static-HTML + polling report layer.

`train.py` calls `init_report()` once at run start and `write_epoch_report()`
after every epoch. Everything is written atomically (tmp file + `os.replace`)
so a browser polling `status.json` never reads a half-written file.
"""

import json
import os
from datetime import UTC, datetime
from pathlib import Path

import torch

MAX_TABLE_ROWS = 20
BOUNDARY_JSON_RESOLUTION = 40


def _atomic_write(path: Path, text: str) -> None:
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, path)


def _atomic_write_json(path: Path, obj) -> None:
    _atomic_write(path, json.dumps(obj, indent=2))


def _now_iso() -> str:
    return datetime.now(UTC).isoformat(timespec="seconds")


def init_report(run_dir: Path, config: dict) -> None:
    report_dir = run_dir / "report"
    (report_dir / "data").mkdir(parents=True, exist_ok=True)
    _atomic_write(report_dir / "index.html", _render_index_html(config))
    _atomic_write_json(
        report_dir / "status.json",
        {
            "run_id": run_dir.name,
            "latest_epoch": 0,
            "total_epochs": config["epochs"],
            "running": True,
            "updated_at": _now_iso(),
        },
    )


def finalize_report(run_dir: Path) -> None:
    status_path = run_dir / "report" / "status.json"
    status = json.loads(status_path.read_text(encoding="utf-8"))
    status["running"] = False
    status["updated_at"] = _now_iso()
    _atomic_write_json(status_path, status)


def _read_metrics_history(run_dir: Path) -> dict:
    steps, epochs, loss, lr, grad_norm, secondary = [], [], [], [], [], []
    secondary_key = None
    with (run_dir / "metrics.jsonl").open(encoding="utf-8") as f:
        for line in f:
            row = json.loads(line)
            steps.append(row["step"])
            epochs.append(row["epoch"])
            loss.append(row["loss"])
            lr.append(row["lr"])
            grad_norm.append(row["grad_norm"])
            secondary_key = "acc" if "acc" in row else "mae"
            secondary.append(row[secondary_key])
    return {
        "step": steps,
        "epoch": epochs,
        "loss": loss,
        "lr": lr,
        "grad_norm": grad_norm,
        "secondary_key": secondary_key,
        "secondary": secondary,
    }


def write_epoch_report(
    run_dir: Path,
    epoch: int,
    task: str,
    class_names: list[str] | None,
    feature_names: list[str],
    feature_mean=None,
    feature_std=None,
) -> None:
    report_dir = run_dir / "report"
    metrics_history = _read_metrics_history(run_dir)

    predictions = torch.load(
        run_dir / "samples" / f"epoch_{epoch}_predictions.pt", weights_only=True
    )

    payload = {"epoch": epoch, "task": task, "metrics_history": metrics_history}

    if task == "classify":
        payload["class_names"] = class_names
        payload.update(
            _classify_epoch_payload(
                run_dir, epoch, predictions, class_names, feature_names, feature_mean, feature_std
            )
        )
    else:
        payload.update(_regress_epoch_payload(predictions, feature_names))

    _atomic_write_json(report_dir / "data" / f"epoch_{epoch}.json", payload)

    status_path = report_dir / "status.json"
    status = json.loads(status_path.read_text(encoding="utf-8"))
    status["latest_epoch"] = epoch
    status["updated_at"] = _now_iso()
    _atomic_write_json(status_path, status)


def _classify_epoch_payload(
    run_dir, epoch, predictions, class_names, feature_names, feature_mean, feature_std
) -> dict:
    true = predictions["true"]
    pred = predictions["pred"]
    probs = predictions["probs"]
    features_raw = predictions["features_raw"]

    n_classes = len(class_names)
    confusion = [[0] * n_classes for _ in range(n_classes)]
    for t, p in zip(true.tolist(), pred.tolist(), strict=True):
        confusion[t][p] += 1

    rows = []
    for i in range(len(true)):
        if true[i].item() != pred[i].item():
            rows.append(
                {
                    "index": i,
                    "features": dict(zip(feature_names, features_raw[i].tolist(), strict=True)),
                    "true": class_names[true[i].item()],
                    "pred": class_names[pred[i].item()],
                    "confidence": round(probs[i, pred[i]].item(), 3),
                    "correct": False,
                }
            )
    rows.sort(key=lambda r: r["confidence"], reverse=True)
    rows = rows[:MAX_TABLE_ROWS]

    boundary_path = run_dir / "boundary" / f"epoch_{epoch}.pt"
    boundary = None
    if boundary_path.exists():
        b = torch.load(boundary_path, weights_only=True)
        step = max(1, len(b["xs"]) // BOUNDARY_JSON_RESOLUTION)
        # boundary grid is in standardized feature space; convert to raw units
        # (mm) so it lines up with `val_points`, which are already raw.
        xs_raw = b["xs"] * feature_std[0] + feature_mean[0]
        ys_raw = b["ys"] * feature_std[1] + feature_mean[1]
        boundary = {
            "xs": xs_raw[::step].tolist(),
            "ys": ys_raw[::step].tolist(),
            "class_grid": b["class_grid"][::step, ::step].tolist(),
        }

    val_points = {
        "x0": features_raw[:, 0].tolist() if features_raw.shape[1] >= 1 else [],
        "x1": features_raw[:, 1].tolist() if features_raw.shape[1] >= 2 else [],
        "true": [class_names[t] for t in true.tolist()],
        "pred": [class_names[p] for p in pred.tolist()],
        "correct": [bool(t == p) for t, p in zip(true.tolist(), pred.tolist(), strict=True)],
    }

    return {
        "confusion_matrix": confusion,
        "misclassified": rows,
        "boundary": boundary,
        "val_points": val_points,
    }


def _regress_epoch_payload(predictions, feature_names) -> dict:
    true = predictions["true"].squeeze(-1)
    pred = predictions["pred"].squeeze(-1)
    features_raw = predictions["features_raw"]
    residual = pred - true

    counts, edges = torch.histogram(residual, bins=12)

    rows = []
    for i in torch.argsort(residual.abs(), descending=True)[:MAX_TABLE_ROWS].tolist():
        rows.append(
            {
                "index": i,
                "features": dict(zip(feature_names, features_raw[i].tolist(), strict=True)),
                "true": round(true[i].item(), 1),
                "pred": round(pred[i].item(), 1),
                "residual": round(residual[i].item(), 1),
            }
        )

    return {
        "residual_hist": {"bin_edges": edges.tolist(), "counts": counts.tolist()},
        "worst_residuals": rows,
    }


# ── static HTML shell ───────────────────────────────────────────────────────

_INDEX_HTML_TEMPLATE = """<!doctype html>
<html lang="zh-Hant">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>__TITLE__</title>
<style>
:root {
  --bg: #0d0d0d;
  --surface: #1a1a19;
  --ink: #ffffff;
  --ink-secondary: #c3c2b7;
  --ink-muted: #898781;
  --gridline: #2c2c2a;
  --border: rgba(255,255,255,0.10);
  --good: #0ca30c;
  --critical: #d03b3b;
  --cat-0: #3987e5;
  --cat-1: #199e70;
  --cat-2: #c98500;
}
@media (prefers-color-scheme: light) {
  :root {
    --bg: #fcfcfb;
    --surface: #ffffff;
    --ink: #16160f;
    --ink-secondary: #55534a;
    --ink-muted: #82806f;
    --gridline: #e5e3da;
    --border: rgba(0,0,0,0.10);
  }
}
* { box-sizing: border-box; }
body {
  margin: 0;
  background: var(--bg);
  color: var(--ink);
  font-family: system-ui, -apple-system, "Segoe UI", sans-serif;
  padding: 2rem;
}
h1 { font-weight: 500; font-size: 1.4rem; margin: 0 0 0.25rem; }
h2 { font-weight: 500; font-size: 1rem; color: var(--ink-secondary); margin: 0 0 0.75rem; }
.meta { color: var(--ink-muted); font-size: 0.85rem; margin-bottom: 1.5rem; }
.badge {
  display: inline-block; padding: 0.15rem 0.6rem; border-radius: 1rem;
  font-size: 0.8rem; border: 1px solid var(--border);
}
.badge.running { color: var(--good); }
.badge.done { color: var(--ink-muted); }
.grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(320px, 1fr)); gap: 1rem; }
.card {
  background: var(--surface); border: 1px solid var(--border); border-radius: 0.5rem;
  padding: 1rem 1.25rem; margin-bottom: 1rem;
  min-width: 0; max-width: 100%;
}
.card.wide { grid-column: 1 / -1; }
canvas { width: 100%; height: 220px; display: block; }
.table-wrap { max-width: 100%; overflow-x: auto; }
table { border-collapse: collapse; width: 100%; font-size: 0.85rem; }
th, td { padding: 0.35rem 0.6rem; text-align: right; border-bottom: 1px solid var(--gridline); font-variant-numeric: tabular-nums; white-space: nowrap; }
th:first-child, td:first-child { text-align: left; }
.status-ok { color: var(--good); }
.status-bad { color: var(--critical); }
.legend { display: flex; gap: 1rem; flex-wrap: wrap; margin-top: 0.5rem; font-size: 0.8rem; color: var(--ink-secondary); }
.legend .swatch { display: inline-block; width: 0.7rem; height: 0.7rem; border-radius: 2px; margin-right: 0.35rem; vertical-align: -1px; }
.config-list { display: flex; flex-wrap: wrap; gap: 0.5rem 1.5rem; font-size: 0.85rem; color: var(--ink-secondary); }
.config-list b { color: var(--ink); }
</style>
</head>
<body>
<h1>__TITLE__</h1>
<div class="meta">run <b id="run-id">__RUN_ID__</b> &middot; <span id="status-badge" class="badge running">running</span></div>
<div class="card">
  <h2>Config</h2>
  <div class="config-list" id="config-list"></div>
</div>
<div class="grid">
  <div class="card"><h2>Loss</h2><canvas id="chart-loss"></canvas></div>
  <div class="card"><h2 id="secondary-title">Metric</h2><canvas id="chart-secondary"></canvas></div>
  <div class="card"><h2>grad_norm</h2><canvas id="chart-grad"></canvas></div>
</div>
<div id="task-panels"></div>

<script>
const CONFIG = __CONFIG_JSON__;
const PALETTE = ["#3987e5", "#199e70", "#c98500", "#008300", "#9085e9", "#e66767", "#d55181", "#d95926"];
let cssVar = null;

function initConfigList() {
  const list = document.getElementById("config-list");
  const entries = Object.entries(CONFIG);
  list.innerHTML = entries.map(([k, v]) => `<span><b>${k}</b>: ${JSON.stringify(v)}</span>`).join("");
}

function color(name) { return getComputedStyle(document.documentElement).getPropertyValue(name).trim(); }

function drawLineChart(canvas, xs, ys, { yLabel = "", color: lineColor } = {}) {
  const ctx = canvas.getContext("2d");
  const w = canvas.width = canvas.clientWidth * devicePixelRatio;
  const h = canvas.height = canvas.clientHeight * devicePixelRatio;
  ctx.clearRect(0, 0, w, h);
  if (!xs.length) return;
  const pad = 32 * devicePixelRatio;
  const xMin = Math.min(...xs), xMax = Math.max(...xs);
  const yMin = Math.min(...ys), yMax = Math.max(...ys);
  const xr = xMax - xMin || 1, yr = yMax - yMin || 1;
  const toX = (x) => pad + ((x - xMin) / xr) * (w - pad * 1.5);
  const toY = (y) => h - pad - ((y - yMin) / yr) * (h - pad * 1.5);

  ctx.strokeStyle = color("--gridline");
  ctx.lineWidth = 1;
  for (let i = 0; i <= 4; i++) {
    const gy = pad + (i / 4) * (h - pad * 1.5);
    ctx.beginPath(); ctx.moveTo(pad, gy); ctx.lineTo(w - pad * 0.5, gy); ctx.stroke();
  }

  ctx.strokeStyle = lineColor || color("--cat-0");
  ctx.lineWidth = 1.5 * devicePixelRatio;
  ctx.beginPath();
  xs.forEach((x, i) => {
    const px = toX(x), py = toY(ys[i]);
    i === 0 ? ctx.moveTo(px, py) : ctx.lineTo(px, py);
  });
  ctx.stroke();

  ctx.fillStyle = color("--ink-muted");
  ctx.font = `${11 * devicePixelRatio}px system-ui`;
  ctx.textAlign = "left";
  ctx.fillText(yMax.toFixed(3), 4, toY(yMax) + 4 * devicePixelRatio);
  ctx.fillText(yMin.toFixed(3), 4, toY(yMin) + 4 * devicePixelRatio);
}

function renderConfusion(matrix, classNames) {
  const max = Math.max(...matrix.flat(), 1);
  let html = '<h2>Confusion matrix</h2><div class="table-wrap"><table><tr><th></th>' +
    classNames.map((c) => `<th>${c}</th>`).join("") + "</tr>";
  matrix.forEach((row, i) => {
    html += `<tr><th>${classNames[i]}</th>` + row.map((v) => {
      const alpha = (v / max).toFixed(2);
      return `<td style="background: rgba(57,135,229,${alpha})">${v}</td>`;
    }).join("") + "</tr>";
  });
  html += "</table></div>";
  return html;
}

function renderBoundaryCanvas(canvas, boundary, valPoints, classNames) {
  const ctx = canvas.getContext("2d");
  const w = canvas.width = canvas.clientWidth * devicePixelRatio;
  const h = canvas.height = canvas.clientHeight * devicePixelRatio;
  ctx.clearRect(0, 0, w, h);
  if (!boundary) return;
  const { xs, ys, class_grid } = boundary;
  const xMin = xs[0], xMax = xs[xs.length - 1], yMin = ys[0], yMax = ys[ys.length - 1];
  const toX = (x) => ((x - xMin) / (xMax - xMin)) * w;
  const toY = (y) => h - ((y - yMin) / (yMax - yMin)) * h;
  const cellW = w / xs.length, cellH = h / ys.length;

  for (let j = 0; j < ys.length; j++) {
    for (let i = 0; i < xs.length; i++) {
      const cls = class_grid[j][i];
      ctx.fillStyle = PALETTE[cls] + "33";
      ctx.fillRect(toX(xs[i]) - cellW / 2, toY(ys[j]) - cellH / 2, cellW + 1, cellH + 1);
    }
  }

  if (valPoints) {
    for (let k = 0; k < valPoints.x0.length; k++) {
      const px = toX(valPoints.x0[k]), py = toY(valPoints.x1[k]);
      const clsIdx = classNames.indexOf(valPoints.true[k]);
      ctx.strokeStyle = ctx.fillStyle = PALETTE[clsIdx];
      const r = 4 * devicePixelRatio;
      if (valPoints.correct[k]) {
        ctx.beginPath(); ctx.arc(px, py, r, 0, 2 * Math.PI); ctx.fill();
      } else {
        ctx.lineWidth = 2 * devicePixelRatio;
        ctx.beginPath();
        ctx.moveTo(px - r, py - r); ctx.lineTo(px + r, py + r);
        ctx.moveTo(px + r, py - r); ctx.lineTo(px - r, py + r);
        ctx.stroke();
      }
    }
  }
}

function renderHistogram(canvas, hist) {
  const ctx = canvas.getContext("2d");
  const w = canvas.width = canvas.clientWidth * devicePixelRatio;
  const h = canvas.height = canvas.clientHeight * devicePixelRatio;
  ctx.clearRect(0, 0, w, h);
  const { bin_edges, counts } = hist;
  const max = Math.max(...counts, 1);
  const barW = w / counts.length;
  counts.forEach((c, i) => {
    const barH = (c / max) * (h - 20 * devicePixelRatio);
    ctx.fillStyle = color("--cat-0");
    ctx.fillRect(i * barW + 2, h - barH, barW - 4, barH);
  });
  ctx.fillStyle = color("--ink-muted");
  ctx.font = `${10 * devicePixelRatio}px system-ui`;
  ctx.textAlign = "center";
  ctx.fillText(bin_edges[0].toFixed(0), barW / 2, h - 4);
  ctx.fillText(bin_edges[bin_edges.length - 1].toFixed(0), w - barW / 2, h - 4);
}

function renderTable(rows, columns) {
  let html = '<div class="table-wrap"><table><tr>' + columns.map((c) => `<th>${c.label}</th>`).join("") + "</tr>";
  for (const row of rows) {
    html += "<tr>" + columns.map((c) => `<td>${c.render(row)}</td>`).join("") + "</tr>";
  }
  html += "</table></div>";
  return html;
}

function renderTaskPanels(data) {
  const panels = document.getElementById("task-panels");
  document.getElementById("secondary-title").textContent = data.metrics_history.secondary_key === "acc" ? "Accuracy" : "MAE";

  if (data.task === "classify") {
    const classNames = data.class_names;
    const featureCols = Object.keys(data.misclassified[0]?.features || {});
    panels.innerHTML = `
      <div class="grid">
        <div class="card">${renderConfusion(data.confusion_matrix, classNames)}</div>
        <div class="card">
          <h2>Decision boundary</h2>
          <canvas id="chart-boundary" style="height:280px"></canvas>
          <div class="legend">
            ${classNames.map((c, i) => `<span><span class="swatch" style="background:${PALETTE[i]}"></span>${c}</span>`).join("")}
            <span>&#9679; correct</span><span>&#10005; wrong</span>
          </div>
        </div>
        <div class="card wide">
          <h2>Misclassified (worst confidence first)</h2>
          ${renderTable(data.misclassified, [
            ...featureCols.map((f) => ({ label: f, render: (r) => r.features[f].toFixed(2) })),
            { label: "true", render: (r) => r.true },
            { label: "pred", render: (r) => r.pred },
            { label: "conf.", render: (r) => r.confidence.toFixed(2) },
            { label: "status", render: () => '<span class="status-bad">&#10005; wrong</span>' },
          ])}
        </div>
      </div>`;
    renderBoundaryCanvas(document.getElementById("chart-boundary"), data.boundary, data.val_points, classNames);
  } else {
    const featureCols = Object.keys(data.worst_residuals[0]?.features || {});
    panels.innerHTML = `
      <div class="grid">
        <div class="card"><h2>Residual histogram (pred &minus; true, body_mass_g)</h2><canvas id="chart-hist"></canvas></div>
        <div class="card wide">
          <h2>Worst residuals</h2>
          ${renderTable(data.worst_residuals, [
            ...featureCols.map((f) => ({ label: f, render: (r) => r.features[f].toFixed(2) })),
            { label: "true (g)", render: (r) => r.true },
            { label: "pred (g)", render: (r) => r.pred },
            { label: "residual", render: (r) => r.residual },
          ])}
        </div>
      </div>`;
    renderHistogram(document.getElementById("chart-hist"), data.residual_hist);
  }
}

function renderEpoch(data) {
  const mh = data.metrics_history;
  drawLineChart(document.getElementById("chart-loss"), mh.step, mh.loss);
  drawLineChart(document.getElementById("chart-secondary"), mh.step, mh.secondary, { color: color("--cat-1") });
  drawLineChart(document.getElementById("chart-grad"), mh.step, mh.grad_norm, { color: color("--cat-2") });
  renderTaskPanels(data);
}

let pollTimer = null;
let lastEpoch = 0;

async function fetchJSON(url) {
  const res = await fetch(url + "?t=" + Date.now());
  return res.json();
}

async function poll() {
  const status = await fetchJSON("status.json");
  const badge = document.getElementById("status-badge");
  badge.textContent = status.running ? "running" : "finished";
  badge.className = "badge " + (status.running ? "running" : "done");
  if (status.latest_epoch !== lastEpoch && status.latest_epoch > 0) {
    lastEpoch = status.latest_epoch;
    const data = await fetchJSON(`data/epoch_${status.latest_epoch}.json`);
    renderEpoch(data);
  }
  if (!status.running && pollTimer) {
    clearInterval(pollTimer);
    pollTimer = null;
  }
}

initConfigList();
poll();
pollTimer = setInterval(poll, 3000);
</script>
</body>
</html>
"""


def _render_index_html(config: dict) -> str:
    title = f"basic_regression_classification — {config['task']} — {config['model']}"
    html = _INDEX_HTML_TEMPLATE
    html = html.replace("__TITLE__", title)
    html = html.replace("__RUN_ID__", config["run_id"])
    html = html.replace("__CONFIG_JSON__", json.dumps(config))
    return html
