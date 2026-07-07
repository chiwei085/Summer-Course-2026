"""Single static-HTML report, written once after training finishes. Same
convention as the earlier labs: metrics history, per-epoch qualitative
samples, and the fusion (cross-attention) snapshot are all embedded
directly in the page as JSON -- including base64-encoded PNG thumbnails --
so it opens straight from disk with no server.
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


def _read_fusion_snapshot(run_dir: Path) -> dict | None:
    path = run_dir / "samples" / "fusion_snapshot.json"
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else None


def write_report(run_dir: Path, config: dict) -> None:
    report_dir = run_dir / "report"
    report_dir.mkdir(parents=True, exist_ok=True)

    payload = {
        "config": config,
        "metrics_history": _read_metrics_history(run_dir),
        "epoch_samples": _read_samples(run_dir, config["epochs"]),
        "fusion_snapshot": _read_fusion_snapshot(run_dir),
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
.sample-row { display: flex; gap: 1rem; flex-wrap: wrap; }
.sample-tile { flex: none; width: 320px; border-bottom: 1px solid var(--gridline); padding-bottom: 0.75rem; }
.sample-tile img { width: 128px; height: 128px; border-radius: 0.25rem; display: block; }
.sample-tile .instruction { font-size: 0.75rem; color: var(--ink-secondary); margin: 0.4rem 0; font-style: italic; }
.sample-tile .table-scroll { overflow-x: auto; }
.sample-tile table { font-size: 0.68rem; border-collapse: collapse; color: var(--ink-secondary); white-space: nowrap; }
.sample-tile th { text-align: right; padding: 0 0.5rem 0 0; color: var(--ink-muted); font-weight: 400; }
.sample-tile th:first-child { padding-right: 0.75rem; }
.sample-tile td { text-align: right; padding: 0 0.5rem 0 0; font-variant-numeric: tabular-nums; }
.epoch-label { color: var(--ink-muted); font-size: 0.85rem; margin: 0.75rem 0 0.4rem; }
#fusion-row { display: flex; gap: 1.5rem; align-items: flex-start; flex-wrap: wrap; }
#fusion-row canvas { width: 288px; height: 288px; flex: none; }
.word-attn { display: flex; flex-wrap: wrap; gap: 0.3rem; max-width: 320px; }
.word-attn span { padding: 0.15rem 0.4rem; border-radius: 0.25rem; font-size: 0.8rem; }
</style>
</head>
<body>
<h1>__TITLE__</h1>
<div class="meta">run <b>__RUN_ID__</b> &middot; dataset <a href="https://huggingface.co/datasets/HuggingFaceVLA/smol-libero" target="_blank" rel="noopener">HuggingFaceVLA/smol-libero</a>（LIBERO 精簡版：影像 + 語言指令 + 7 自由度動作）</div>
<div class="card">
  <h2>Config</h2>
  <div id="config-list"></div>
</div>
<div class="section-note">
  橫軸為訓練步數（step）；淺色虛線標示 epoch 邊界。動作預測正確率不是評分重點，這裡的圖表是用來確認整條資料流（影像 + 語言 + 動作歷史 → 下一個動作）確實有在收斂。
</div>
<div class="grid">
  <div class="card"><h2>Loss（7 軸 action token 的 cross-entropy 平均）</h2><canvas id="chart-loss"></canvas></div>
  <div class="card"><h2>Action L2 誤差（原始單位，7 軸合併，僅供參考）</h2><canvas id="chart-l2"></canvas></div>
  <div class="card"><h2>grad_norm（梯度範數）</h2><canvas id="chart-grad"></canvas></div>
</div>
<div class="card wide">
  <h2>每個 epoch 的預測：給定影像 + 指令，模型猜的下一步動作 vs. 示範者實際動作</h2>
  <div class="section-note">每張縮圖是該 window 開始時的觀測影像；表格比較 7 個動作軸（x, y, z, roll, pitch, yaw, gripper）在原始單位下的預測值與示範者實際值。</div>
  <div id="samples"></div>
</div>
<div class="card wide" id="fusion-card" style="display:none">
  <h2>Cross-attention 融合：動作 decoder 在看影像的哪裡、指令的哪個字？</h2>
  <p class="section-note" style="margin: -0.25rem 0 1rem">
    這是動作 decoder 每一層 cross-attention 的平均權重（averaged over heads and decode steps），對象是融合後的 [影像 patch; 指令文字] context。
    左邊熱力圖是影像 patch 的權重，右邊是每個字的權重深淺；兩邊合計權重列在下方，粗略反映模型這一步比較依賴視覺還是語言。
  </p>
  <div id="fusion-row"></div>
  <div id="fusion-totals" style="margin-top: 0.75rem; font-size: 0.8rem; color: var(--ink-secondary)"></div>
</div>

<script>
const DATA = __DATA_JSON__;
const PALETTE = { loss: "#3987e5", l2: "#199e70", grad: "#c98500" };
const ACTION_LABELS = ["x", "y", "z", "roll", "pitch", "yaw", "gripper"];

function color(name) { return getComputedStyle(document.documentElement).getPropertyValue(name).trim(); }

const CONFIG_GROUPS = [
  { label: "多模態架構", keys: ["camera", "image_size", "patch_size", "max_instruction_len", "bins_per_dim", "block_size", "n_embd", "n_head", "n_vision_layer", "n_lang_layer", "n_action_layer", "dropout", "vocab_size"] },
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

function renderSamples() {
  const container = document.getElementById("samples");
  container.innerHTML = DATA.epoch_samples.map((ep) => `
    <div>
      <div class="epoch-label">epoch ${ep.epoch} &middot; val_loss=${ep.val_loss.toFixed(4)} &middot; val action L2=${ep.val_action_l2.toFixed(4)}</div>
      <div class="sample-row">
        ${ep.samples.map((s) => `
          <div class="sample-tile">
            <img src="${s.image}" />
            <div class="instruction">"${s.instruction}"</div>
            <div class="table-scroll">
            <table>
              <tr><th></th>${ACTION_LABELS.map((l) => `<th>${l}</th>`).join("")}</tr>
              <tr><th style="color:${PALETTE.l2}">實際</th>${s.actual.map((v) => `<td>${v.toFixed(2)}</td>`).join("")}</tr>
              <tr><th style="color:${PALETTE.grad}">預測</th>${s.predicted.map((v) => `<td>${v.toFixed(2)}</td>`).join("")}</tr>
            </table>
            </div>
          </div>`).join("")}
      </div>
    </div>`).join("");
}

function drawFusionGrid(canvas, imageSrc, grid) {
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
        ctx.fillStyle = `rgba(57, 135, 229, ${(norm * 0.75).toFixed(2)})`;
        ctx.fillRect(c * cellW, r * cellH, cellW, cellH);
      }
    }
  };
  img.src = imageSrc;
}

function renderFusion() {
  const snap = DATA.fusion_snapshot;
  if (!snap) return;
  document.getElementById("fusion-card").style.display = "block";
  const container = document.getElementById("fusion-row");

  const maxWord = Math.max(...snap.word_attn, 1e-9);
  const wordsHtml = snap.words.map((w, i) => {
    const alpha = Math.min(1, snap.word_attn[i] / maxWord).toFixed(2);
    return `<span style="background: rgba(201, 133, 0, ${alpha})">${w}</span>`;
  }).join("");

  container.innerHTML = `
    <canvas id="fusion-canvas"></canvas>
    <div style="max-width: 320px">
      <div class="section-note" style="margin: 0 0 0.4rem">指令："${snap.instruction}"</div>
      <div class="word-attn">${wordsHtml}</div>
    </div>`;
  drawFusionGrid(document.getElementById("fusion-canvas"), snap.image, snap.vision_grid);

  const total = snap.vision_attn_total + snap.language_attn_total;
  document.getElementById("fusion-totals").textContent =
    `合計權重 -- 影像: ${(snap.vision_attn_total / total * 100).toFixed(1)}%　指令: ${(snap.language_attn_total / total * 100).toFixed(1)}%`;
}

initConfigList();
const mh = DATA.metrics_history;
drawLineChart(document.getElementById("chart-loss"), mh, "loss", PALETTE.loss);
drawLineChart(document.getElementById("chart-l2"), mh, "action_l2_error", PALETTE.l2);
drawLineChart(document.getElementById("chart-grad"), mh, "grad_norm", PALETTE.grad);
renderSamples();
renderFusion();
</script>
</body>
</html>
"""


def _render_html(payload: dict) -> str:
    title = "homework — VLA (vision + language + action)"
    html = _HTML_TEMPLATE
    html = html.replace("__TITLE__", title)
    html = html.replace("__RUN_ID__", payload["config"]["run_id"])
    html = html.replace("__DATA_JSON__", json.dumps(payload))
    return html
