"""Single static-HTML report, written once after training finishes.

Same convention as `basic_sequence_bc`'s report: everything (metrics
history, per-epoch prediction panels, the encoder snapshot) is embedded
directly in the page as JSON -- including base64-encoded PNG thumbnails of
the sampled frames -- so it opens straight from disk with no server.
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


def _read_encoder_snapshot(run_dir: Path) -> dict | None:
    path = run_dir / "samples" / "encoder_snapshot.json"
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else None


def write_report(run_dir: Path, config: dict) -> None:
    report_dir = run_dir / "report"
    report_dir.mkdir(parents=True, exist_ok=True)

    payload = {
        "config": config,
        "metrics_history": _read_metrics_history(run_dir),
        "epoch_samples": _read_samples(run_dir, config["epochs"]),
        "encoder_snapshot": _read_encoder_snapshot(run_dir),
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
.config-group { margin-bottom: 0.6rem; }
.config-group:last-child { margin-bottom: 0; }
.config-group-label {
  font-size: 0.72rem; color: var(--ink-muted); text-transform: uppercase;
  letter-spacing: 0.05em; margin-bottom: 0.3rem;
}
.config-row { display: flex; flex-wrap: wrap; gap: 0.4rem 1.5rem; font-size: 0.85rem; color: var(--ink-secondary); }
.config-row b { color: var(--ink); }
.section-note { color: var(--ink-muted); font-size: 0.8rem; margin: -0.4rem 0 1rem; }
.sample-row { display: flex; gap: 1rem; flex-wrap: wrap; overflow-x: auto; padding-bottom: 0.5rem; }
.sample-tile { flex: none; text-align: center; }
.sample-tile canvas { width: 120px; height: 120px; display: block; }
.sample-tile .legend { font-size: 0.7rem; color: var(--ink-muted); margin-top: 0.2rem; }
.epoch-label { color: var(--ink-muted); font-size: 0.85rem; margin: 0.75rem 0 0.4rem; }
#snapshot-row { display: flex; gap: 1.5rem; align-items: flex-start; flex-wrap: wrap; }
#snapshot-row canvas { width: 288px; height: 288px; flex: none; }
</style>
</head>
<body>
<h1>__TITLE__</h1>
<div class="meta">run <b>__RUN_ID__</b> &middot; dataset <a href="https://huggingface.co/datasets/lerobot/pusht_image" target="_blank" rel="noopener">lerobot/pusht_image</a>（同一個 push-T 示範，這次含 96x96 影像觀測）</div>
<div class="card">
  <h2>Config</h2>
  <div id="config-list"></div>
</div>
<div class="section-note">
  橫軸為訓練步數（step）；淺色虛線標示 epoch 邊界。
</div>
<div class="grid">
  <div class="card"><h2>Loss（action 迴歸 MSE）</h2><canvas id="chart-loss"></canvas></div>
  <div class="card"><h2>L2 誤差（像素）</h2><canvas id="chart-l2"></canvas></div>
  <div class="card"><h2>grad_norm（梯度範數）</h2><canvas id="chart-grad"></canvas></div>
</div>
<div class="card wide">
  <h2>每個 epoch 的預測：模型看到這張圖，猜的下一步動作 vs. 示範者實際動作</h2>
  <div class="section-note">綠色點是示範者實際的下一步動作，橘色點是模型的預測。隨著訓練進行，橘色點應該越來越靠近綠色點。</div>
  <div id="samples"></div>
</div>
<div class="card wide" id="snapshot-card" style="display:none">
  <h2 id="snapshot-title">Encoder 在看哪裡？</h2>
  <p id="snapshot-note" style="color: var(--ink-muted); font-size: 0.85rem; margin-top: 0"></p>
  <div id="snapshot-row"></div>
</div>

<script>
const DATA = __DATA_JSON__;
const PALETTE = { loss: "#3987e5", l2: "#199e70", grad: "#c98500", actual: "#199e70", predicted: "#c98500" };

function color(name) { return getComputedStyle(document.documentElement).getPropertyValue(name).trim(); }

const CONFIG_GROUPS = [
  { label: "模型架構", keys: ["model", "patch_size", "n_embd", "n_head", "n_layer", "dropout"] },
  { label: "訓練設定", keys: ["epochs", "steps_per_epoch", "lr", "batch_size", "seed", "device"] },
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

function drawSampleTile(canvas, sample) {
  const ctx = canvas.getContext("2d");
  const w = canvas.width = canvas.clientWidth * devicePixelRatio;
  const h = canvas.height = canvas.clientHeight * devicePixelRatio;
  const CANVAS_SIZE = 512;
  const scale = Math.min(w, h) / CANVAS_SIZE;
  const img = new Image();
  img.onload = () => {
    ctx.drawImage(img, 0, 0, w, h);
    function dot(xy, fillColor) {
      const [x, y] = [xy[0] * scale, xy[1] * scale];
      ctx.fillStyle = fillColor;
      ctx.beginPath(); ctx.arc(x, y, 4 * devicePixelRatio, 0, Math.PI * 2); ctx.fill();
      ctx.strokeStyle = "rgba(0,0,0,0.5)"; ctx.lineWidth = 1; ctx.stroke();
    }
    dot(sample.actual_xy, PALETTE.actual);
    dot(sample.predicted_xy, PALETTE.predicted);
  };
  img.src = sample.image;
}

function renderSamples() {
  const container = document.getElementById("samples");
  container.innerHTML = DATA.epoch_samples.map((ep, epIdx) => `
    <div>
      <div class="epoch-label">epoch ${ep.epoch} &middot; val_loss=${ep.val_loss.toFixed(4)} &middot; val L2=${ep.val_l2_error.toFixed(1)}px</div>
      <div class="sample-row">
        ${ep.samples.map((s, i) => `
          <div class="sample-tile">
            <canvas id="tile-${epIdx}-${i}"></canvas>
            <div class="legend"><span style="color:${PALETTE.actual}">●</span>實際 &nbsp;<span style="color:${PALETTE.predicted}">●</span>預測</div>
          </div>`).join("")}
      </div>
    </div>`).join("");
  DATA.epoch_samples.forEach((ep, epIdx) => {
    ep.samples.forEach((s, i) => drawSampleTile(document.getElementById(`tile-${epIdx}-${i}`), s));
  });
}

function drawGridOverlay(canvas, imageSrc, grid) {
  const ctx = canvas.getContext("2d");
  const w = canvas.width = canvas.clientWidth * devicePixelRatio;
  const h = canvas.height = canvas.clientHeight * devicePixelRatio;
  const img = new Image();
  img.onload = () => {
    ctx.drawImage(img, 0, 0, w, h);
    const rows = grid.length, cols = grid[0].length;
    const cellW = w / cols, cellH = h / rows;
    const flat = grid.flat();
    const maxV = Math.max(...flat), minV = Math.min(...flat);
    const range = (maxV - minV) || 1;
    for (let r = 0; r < rows; r++) {
      for (let c = 0; c < cols; c++) {
        const norm = (grid[r][c] - minV) / range;
        ctx.fillStyle = `rgba(201, 133, 0, ${(norm * 0.75).toFixed(2)})`;
        ctx.fillRect(c * cellW, r * cellH, cellW, cellH);
      }
    }
  };
  img.src = imageSrc;
}

function renderSnapshot() {
  const snap = DATA.encoder_snapshot;
  if (!snap) return;
  document.getElementById("snapshot-card").style.display = "block";
  const isVit = snap.kind === "vit";
  document.getElementById("snapshot-title").textContent =
    isVit ? "ViT：CLS token 對每個 patch 的注意力" : "CNN：輸入梯度顯著圖（saliency）";
  document.getElementById("snapshot-note").textContent = isVit
    ? "顏色越深代表 CLS token（用來做最終預測的向量）越依賴那個 patch。這跟 basic_sequence_bc 印出的注意力矩陣是同一個機制，只是這裡的「序列」是攤平的影像 patch，不是時間步——所以不需要 causal mask：patch 之間沒有先後順序，没有「未來」可以偷看。"
    : "CNN 沒有注意力權重可以直接印出來；這裡改用「輸入梯度」——把預測值對每個像素微分，顏色越深代表微調那個像素對預測的影響越大，等於是模型隱含的「關注區域」。";
  const container = document.getElementById("snapshot-row");
  container.innerHTML = `<canvas id="snapshot-canvas"></canvas>`;
  drawGridOverlay(document.getElementById("snapshot-canvas"), snap.image, snap.grid);
}

initConfigList();
const mh = DATA.metrics_history;
drawLineChart(document.getElementById("chart-loss"), mh, "loss", PALETTE.loss);
drawLineChart(document.getElementById("chart-l2"), mh, "l2_error_px", PALETTE.l2);
drawLineChart(document.getElementById("chart-grad"), mh, "grad_norm", PALETTE.grad);
renderSamples();
renderSnapshot();
</script>
</body>
</html>
"""


def _render_html(payload: dict) -> str:
    title = f"basic_vision_representation — {payload['config']['model']}"
    html = _HTML_TEMPLATE
    html = html.replace("__TITLE__", title)
    html = html.replace("__RUN_ID__", payload["config"]["run_id"])
    html = html.replace("__DATA_JSON__", json.dumps(payload))
    return html
