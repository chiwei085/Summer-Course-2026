"""Single static-HTML report, written once after training finishes.

Unlike `basic_regression_classification`'s live-polling report, this one
has nothing to poll: all data (metrics history, per-epoch rollout samples,
the attention snapshot) is embedded directly in the page as JSON, so it
opens straight from disk (`file://...`) with no `explore.py serve` needed.
"""

import json
from pathlib import Path


def _read_metrics_history(run_dir: Path) -> list[dict]:
    with (run_dir / "metrics.jsonl").open(encoding="utf-8") as f:
        return [json.loads(line) for line in f]


def _read_samples(run_dir: Path, epochs: int) -> list[dict]:
    samples = []
    for epoch in range(1, epochs + 1):
        path = run_dir / "samples" / f"epoch_{epoch}.json"
        if path.exists():
            samples.append(json.loads(path.read_text(encoding="utf-8")))
    return samples


def _read_attention(run_dir: Path) -> dict | None:
    path = run_dir / "samples" / "attention.json"
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else None


def write_report(run_dir: Path, config: dict) -> None:
    report_dir = run_dir / "report"
    report_dir.mkdir(parents=True, exist_ok=True)

    payload = {
        "config": config,
        "metrics_history": _read_metrics_history(run_dir),
        "samples": _read_samples(run_dir, config["epochs"]),
        "attention": _read_attention(run_dir),
    }
    (report_dir / "index.html").write_text(_render_html(payload), encoding="utf-8")


_HTML_TEMPLATE = """<!doctype html>
<html lang="zh-Hant">
<head>
<meta charset="utf-8" />
<meta name="viewport" content="width=device-width, initial-scale=1" />
<title>__TITLE__</title>
<style>
:root {
  --bg: #0d0d0d; --surface: #1a1a19; --ink: #ffffff; --ink-secondary: #c3c2b7;
  --ink-muted: #898781; --gridline: #2c2c2a; --border: rgba(255,255,255,0.10);
  --cat-0: #3987e5; --cat-1: #199e70; --cat-2: #c98500;
}
@media (prefers-color-scheme: light) {
  :root {
    --bg: #fcfcfb; --surface: #ffffff; --ink: #16160f; --ink-secondary: #55534a;
    --ink-muted: #82806f; --gridline: #e5e3da; --border: rgba(0,0,0,0.10);
  }
}
* { box-sizing: border-box; }
body {
  margin: 0; background: var(--bg); color: var(--ink);
  font-family: system-ui, -apple-system, "Segoe UI", sans-serif; padding: 2rem;
}
h1 { font-weight: 500; font-size: 1.4rem; margin: 0 0 0.25rem; }
h2 { font-weight: 500; font-size: 1rem; color: var(--ink-secondary); margin: 0 0 0.75rem; }
.meta { color: var(--ink-muted); font-size: 0.85rem; margin-bottom: 1.5rem; }
.grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(320px, 1fr)); gap: 1rem; }
.card {
  background: var(--surface); border: 1px solid var(--border); border-radius: 0.5rem;
  padding: 1rem 1.25rem; margin-bottom: 1rem; min-width: 0; max-width: 100%;
}
.card.wide { grid-column: 1 / -1; }
canvas { width: 100%; height: 220px; display: block; }
#chart-traj { height: 320px; max-width: 320px; margin: 0 auto; }
.config-group { margin-bottom: 0.6rem; }
.config-group:last-child { margin-bottom: 0; }
.config-group-label {
  font-size: 0.72rem; color: var(--ink-muted); text-transform: uppercase;
  letter-spacing: 0.05em; margin-bottom: 0.3rem;
}
.config-row { display: flex; flex-wrap: wrap; gap: 0.4rem 1.5rem; font-size: 0.85rem; color: var(--ink-secondary); }
.config-row b { color: var(--ink); }
.section-note { color: var(--ink-muted); font-size: 0.8rem; margin: -0.4rem 0 1rem; }
.traj-row { display: flex; gap: 1.5rem; flex-wrap: wrap; align-items: flex-start; }
.traj-meta { font-size: 0.85rem; color: var(--ink-secondary); min-width: 160px; padding-top: 0.5rem; }
.traj-meta .epoch-label { color: var(--ink-muted); margin-bottom: 0.4rem; }
.traj-meta .legend { display: flex; align-items: center; gap: 0.4rem; margin-top: 0.3rem; }
.traj-meta .swatch { width: 14px; height: 3px; display: inline-block; }
#attn-table { border-collapse: collapse; font-family: ui-monospace, monospace; font-size: 0.72rem; }
#attn-table td, #attn-table th { padding: 0; text-align: center; }
</style>
</head>
<body>
<h1>__TITLE__</h1>
<div class="meta">run <b>__RUN_ID__</b> &middot; dataset <a href="https://huggingface.co/datasets/lerobot/pusht_keypoints" target="_blank" rel="noopener">lerobot/pusht_keypoints</a>（真實機器人示範資料，只用 action 序列）</div>
<div class="card">
  <h2>Config</h2>
  <div id="config-list"></div>
</div>
<div class="section-note">
  橫軸為訓練步數（step）；淺色虛線標示 epoch 邊界，方便對照下方每個 epoch 的 rollout 樣本。
</div>
<div class="grid">
  <div class="card"><h2>Loss（next-action-token cross-entropy）</h2><canvas id="chart-loss"></canvas></div>
  <div class="card"><h2>Perplexity（困惑度）</h2><canvas id="chart-ppl"></canvas></div>
  <div class="card"><h2>grad_norm（梯度範數）</h2><canvas id="chart-grad"></canvas></div>
</div>
<div class="card wide">
  <h2>每個 epoch 的 rollout：預測動作序列 vs. 示範者實際動作</h2>
  <div class="section-note" id="samples-note" style="margin-top: -0.25rem"></div>
  <div id="samples"></div>
</div>
<div class="card wide" id="attention-card" style="display:none">
  <h2>Causal attention（最後一個 checkpoint，averaged over heads）</h2>
  <p style="color: var(--ink-muted); font-size: 0.85rem; margin-top: 0">
    橫軸 = 被關注的動作步（key），縱軸 = 正在預測的動作步（query）。
    <b>檢查右上角是否趨近全 0</b> —— 這就是 causal mask 生效的直接證據：
    每一步只能往左邊、更早發生的動作看，看不到自己之後才發生的動作
    （這正是為什麼 BC policy 的「歷史動作」也必須套用同一種因果限制：
    訓練時不能偷看還沒發生的未來）。
  </p>
  <div id="attention-grid" style="overflow-x: auto"></div>
</div>

<script>
const DATA = __DATA_JSON__;
const PALETTE = { loss: "#3987e5", ppl: "#199e70", grad: "#c98500", actual: "#199e70", predicted: "#c98500" };

function color(name) { return getComputedStyle(document.documentElement).getPropertyValue(name).trim(); }

const CONFIG_GROUPS = [
  { label: "模型架構", keys: ["model", "vocab_size", "bins_per_dim", "block_size", "n_embd", "n_head", "n_layer", "dropout"] },
  { label: "訓練設定", keys: ["epochs", "steps_per_epoch", "lr", "batch_size", "seed", "device"] },
  { label: "Rollout 設定", keys: ["val_episode", "prompt_len", "gen_length", "temperature"] },
];

function initConfigList() {
  const list = document.getElementById("config-list");
  list.innerHTML = CONFIG_GROUPS.map((group) => {
    const rows = group.keys
      .filter((k) => k in DATA.config)
      .map((k) => `<span><b>${k}</b>: ${JSON.stringify(DATA.config[k])}</span>`)
      .join("");
    return `<div class="config-group">
      <div class="config-group-label">${group.label}</div>
      <div class="config-row">${rows}</div>
    </div>`;
  }).join("");
}

function drawLineChart(canvas, rows, yKey, lineColor) {
  const xs = rows.map((r) => r.step);
  const ys = rows.map((r) => r[yKey]);
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

  const stepsPerEpoch = DATA.config.steps_per_epoch;
  if (stepsPerEpoch) {
    ctx.strokeStyle = color("--ink-muted");
    ctx.globalAlpha = 0.4;
    ctx.setLineDash([2 * devicePixelRatio, 3 * devicePixelRatio]);
    const maxEpoch = Math.floor(xMax / stepsPerEpoch);
    for (let e = 1; e <= maxEpoch; e++) {
      const gx = toX(e * stepsPerEpoch);
      ctx.beginPath(); ctx.moveTo(gx, pad * 0.5); ctx.lineTo(gx, h - pad); ctx.stroke();
    }
    ctx.setLineDash([]);
    ctx.globalAlpha = 1;
  }

  ctx.strokeStyle = lineColor;
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

function drawTrajectory(canvas, sample) {
  const ctx = canvas.getContext("2d");
  const w = canvas.width = canvas.clientWidth * devicePixelRatio;
  const h = canvas.height = canvas.clientHeight * devicePixelRatio;
  ctx.clearRect(0, 0, w, h);
  const CANVAS_SIZE = 512;
  const scale = Math.min(w, h) / CANVAS_SIZE;
  const toPx = ([x, y]) => [x * scale, y * scale];

  ctx.strokeStyle = color("--gridline");
  ctx.strokeRect(0, 0, w, h);

  function drawPath(points, strokeColor, dashed) {
    if (!points.length) return;
    ctx.strokeStyle = strokeColor;
    ctx.lineWidth = 2 * devicePixelRatio;
    ctx.setLineDash(dashed ? [4 * devicePixelRatio, 4 * devicePixelRatio] : []);
    ctx.beginPath();
    points.forEach((p, i) => {
      const [px, py] = toPx(p);
      i === 0 ? ctx.moveTo(px, py) : ctx.lineTo(px, py);
    });
    ctx.stroke();
    ctx.setLineDash([]);
  }

  drawPath(sample.prompt_xy, color("--ink-muted"), false);
  drawPath(sample.actual_xy, PALETTE.actual, false);
  drawPath(sample.predicted_xy, PALETTE.predicted, true);

  // mark the handoff point where the prompt ends and rollout begins
  if (sample.prompt_xy.length) {
    const [px, py] = toPx(sample.prompt_xy[sample.prompt_xy.length - 1]);
    ctx.fillStyle = color("--ink");
    ctx.beginPath(); ctx.arc(px, py, 3 * devicePixelRatio, 0, Math.PI * 2); ctx.fill();
  }
}

function renderSamples() {
  const container = document.getElementById("samples");
  document.getElementById("samples-note").textContent =
    DATA.config.model === "bigram"
      ? "bigram 模型只看「前一步的動作」，rollout 通常很快偏離真實軌跡，這是預期行為。"
      : "隨著訓練進行，橘色虛線（模型 rollout）應該越來越貼近綠色實線（示範者實際動作）。";
  container.innerHTML = DATA.samples.map((s, i) => `
    <div class="traj-row" style="margin-bottom: 1rem; border-bottom: 1px solid var(--gridline); padding-bottom: 1rem;">
      <canvas id="chart-traj-${i}" style="width:280px;height:280px;flex:none"></canvas>
      <div class="traj-meta">
        <div class="epoch-label">epoch ${s.epoch} &middot; val_loss=${s.val_loss.toFixed(3)}</div>
        <div>prompt 步數: ${s.prompt_xy.length}</div>
        <div>rollout L2 誤差: ${s.l2_error.toFixed(1)}px</div>
        <div class="legend"><span class="swatch" style="background:${color('--ink-muted')}"></span>prompt（真實）</div>
        <div class="legend"><span class="swatch" style="background:${PALETTE.actual}"></span>實際動作</div>
        <div class="legend"><span class="swatch" style="background:${PALETTE.predicted};border-top:2px dashed ${PALETTE.predicted}"></span>模型 rollout</div>
      </div>
    </div>`).join("");
  DATA.samples.forEach((s, i) => drawTrajectory(document.getElementById(`chart-traj-${i}`), s));
}

function renderAttention() {
  if (!DATA.attention) return;
  document.getElementById("attention-card").style.display = "block";
  const { labels, attn } = DATA.attention;
  const container = document.getElementById("attention-grid");
  let html = `<table id="attn-table"><tr><th></th>` +
    labels.map((l) => `<th style="width:22px">${l}</th>`).join("") + `</tr>`;
  attn.forEach((row, i) => {
    html += `<tr><th style="text-align:right;padding-right:4px">${labels[i]}</th>`;
    html += row.map((v) => {
      const alpha = Math.min(1, v * 3).toFixed(2);
      return `<td style="width:22px;height:22px;background:rgba(57,135,229,${alpha})"></td>`;
    }).join("");
    html += `</tr>`;
  });
  html += `</table>`;
  container.innerHTML = html;
}

initConfigList();
const mh = DATA.metrics_history;
drawLineChart(document.getElementById("chart-loss"), mh, "loss", PALETTE.loss);
drawLineChart(document.getElementById("chart-ppl"), mh, "perplexity", PALETTE.ppl);
drawLineChart(document.getElementById("chart-grad"), mh, "grad_norm", PALETTE.grad);
renderSamples();
renderAttention();
</script>
</body>
</html>
"""


def _render_html(payload: dict) -> str:
    title = f"basic_sequence_bc — {payload['config']['model']}"
    html = _HTML_TEMPLATE
    html = html.replace("__TITLE__", title)
    html = html.replace("__RUN_ID__", payload["config"]["run_id"])
    html = html.replace("__DATA_JSON__", json.dumps(payload))
    return html
