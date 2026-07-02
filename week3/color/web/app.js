"use strict";

// ---------------------------------------------------------------------
// Cell 1: RGB -> Intensity
// ---------------------------------------------------------------------

const intensityMethodSelect = document.getElementById("intensity-method");
const sourceImage = document.getElementById("source-image");
const intensityImage = document.getElementById("intensity-image");
const pixelReadout = document.getElementById("pixel-readout");

function refreshIntensityImage() {
  const method = intensityMethodSelect.value;
  intensityImage.src = `/api/intensity?method=${method}&max_width=480&t=${Date.now()}`;
}
intensityMethodSelect.addEventListener("change", refreshIntensityImage);

// Mirrors week3::color::rgb_to_intensity (src/color.cpp) so the sampled
// pixel can be marked on the intensity panel without a round trip.
function rgbToIntensity(r, g, b, method) {
  if (method === "average") return Math.round((r + g + b) / 3);
  if (method === "lightness") return Math.round((Math.max(r, g, b) + Math.min(r, g, b)) / 2);
  return Math.round(0.299 * r + 0.587 * g + 0.114 * b); // luminosity
}

sourceImage.addEventListener("click", async (ev) => {
  const rect = sourceImage.getBoundingClientRect();
  const displayX = ev.clientX - rect.left;
  const displayY = ev.clientY - rect.top;
  const x = Math.round((displayX / rect.width) * sourceImage.naturalWidth);
  const y = Math.round((displayY / rect.height) * sourceImage.naturalHeight);

  const res = await fetch(`/api/pixel?x=${x}&y=${y}`);
  const px = await res.json();
  pixelReadout.textContent =
    `pixel (${x}, ${y}) of ${px.width}x${px.height} -> ` +
    `rgb(${px.r}, ${px.g}, ${px.b})  hsv(${px.h.toFixed(1)}°, ${(px.s * 100).toFixed(0)}%, ${(px.v * 100).toFixed(0)}%)`;

  setRgb(px.r, px.g, px.b);

  sampledPixel = {
    red: px.r,
    green: px.g,
    blue: px.b,
    intensity: rgbToIntensity(px.r, px.g, px.b, intensityMethodSelect.value),
  };
  drawAllHistograms();
});

// ---------------------------------------------------------------------
// Cell 2: Histogram (small multiples: one axed panel per channel, no
// alpha-blended overlay so bar colors never mix into fake hues)
// ---------------------------------------------------------------------

const histChannels = ["red", "green", "blue", "intensity"];
const histCanvases = {
  red: document.getElementById("hist-canvas-red"),
  green: document.getElementById("hist-canvas-green"),
  blue: document.getElementById("hist-canvas-blue"),
  intensity: document.getElementById("hist-canvas-intensity"),
};
const histReadouts = {
  red: document.getElementById("readout-red"),
  green: document.getElementById("readout-green"),
  blue: document.getElementById("readout-blue"),
  intensity: document.getElementById("readout-intensity"),
};
const histToggles = {
  red: document.getElementById("hist-red"),
  green: document.getElementById("hist-green"),
  blue: document.getElementById("hist-blue"),
  intensity: document.getElementById("hist-intensity"),
};
const histColors = {
  red: "#ff6f6f",
  green: "#79e07f",
  blue: "#5eb0ff",
  intensity: "#dcdcdc",
};
const histPad = { left: 40, right: 10, top: 8, bottom: 20 };
let histData = null;
let sampledPixel = null; // { red, green, blue, intensity } from the last clicked pixel

async function refreshHistogram() {
  const method = intensityMethodSelect.value;
  const res = await fetch(`/api/histogram?method=${method}`);
  histData = await res.json();
  drawAllHistograms();
}

function binGeometry(canvas) {
  const { width, height } = canvas;
  const plotW = width - histPad.left - histPad.right;
  const plotH = height - histPad.top - histPad.bottom;
  return { width, height, plotW, plotH, binWidth: plotW / 256 };
}

function drawAxes(ctx, canvas, maxCount) {
  const { width, height, plotW, plotH } = binGeometry(canvas);
  ctx.strokeStyle = "#3a4150";
  ctx.fillStyle = "#8b93a3";
  ctx.font = "10px sans-serif";
  ctx.lineWidth = 1;

  // Axis lines.
  ctx.beginPath();
  ctx.moveTo(histPad.left, histPad.top);
  ctx.lineTo(histPad.left, histPad.top + plotH);
  ctx.lineTo(histPad.left + plotW, histPad.top + plotH);
  ctx.stroke();

  // Y ticks: 0 and max count.
  ctx.textAlign = "right";
  ctx.textBaseline = "top";
  ctx.fillText("0", histPad.left - 6, histPad.top + plotH - 9);
  ctx.textBaseline = "top";
  ctx.fillText(String(maxCount), histPad.left - 6, histPad.top - 2);
  ctx.textAlign = "left";
  ctx.fillText("count", 2, histPad.top - 2);

  // X ticks: 0, 64, 128, 192, 255 (bin value = intensity level).
  ctx.textAlign = "center";
  ctx.textBaseline = "top";
  for (const v of [0, 64, 128, 192, 255]) {
    const x = histPad.left + (v / 255) * plotW;
    ctx.beginPath();
    ctx.moveTo(x, histPad.top + plotH);
    ctx.lineTo(x, histPad.top + plotH + 3);
    ctx.stroke();
    ctx.fillText(String(v), x, histPad.top + plotH + 5);
  }
  ctx.textAlign = "right";
  ctx.fillText("value", width - 2, histPad.top + plotH + 5);
}

function drawPanel(channel) {
  const canvas = histCanvases[channel];
  const ctx = canvas.getContext("2d");
  const { width, height, plotW, plotH, binWidth } = binGeometry(canvas);
  ctx.clearRect(0, 0, width, height);
  if (!histData) return;

  const bins = histData[channel];
  const maxCount = Math.max(1, ...bins);
  drawAxes(ctx, canvas, maxCount);

  ctx.fillStyle = histColors[channel];
  ctx.beginPath();
  for (let bin = 0; bin < 256; bin++) {
    const barHeight = (bins[bin] / maxCount) * plotH;
    ctx.rect(
      histPad.left + bin * binWidth,
      histPad.top + plotH - barHeight,
      Math.max(1, binWidth),
      barHeight
    );
  }
  ctx.fill();

  // Marker for the last-sampled pixel's value in this channel.
  if (sampledPixel) {
    const v = sampledPixel[channel];
    const x = histPad.left + (v / 255) * plotW;
    ctx.strokeStyle = "#fff";
    ctx.lineWidth = 1.5;
    ctx.beginPath();
    ctx.moveTo(x, histPad.top);
    ctx.lineTo(x, histPad.top + plotH);
    ctx.stroke();
    ctx.fillStyle = "#fff";
    ctx.font = "10px sans-serif";
    ctx.textAlign = v > 220 ? "right" : "left";
    ctx.textBaseline = "top";
    ctx.fillText(`sampled=${v}`, x + (v > 220 ? -3 : 3), histPad.top + 1);
  }
}

function drawAllHistograms() {
  for (const ch of histChannels) {
    const panel = document.getElementById(`panel-${ch}`);
    panel.style.display = histToggles[ch].checked ? "" : "none";
    if (histToggles[ch].checked) drawPanel(ch);
  }
}

for (const toggle of Object.values(histToggles)) {
  toggle.addEventListener("change", drawAllHistograms);
}

// Hover a panel to read the exact bin (value + pixel count) under the cursor.
for (const channel of histChannels) {
  const canvas = histCanvases[channel];
  canvas.addEventListener("mousemove", (ev) => {
    if (!histData) return;
    const rect = canvas.getBoundingClientRect();
    const scaleX = canvas.width / rect.width;
    const canvasX = (ev.clientX - rect.left) * scaleX;
    const { plotW } = binGeometry(canvas);
    const bin = Math.min(255, Math.max(0, Math.round(((canvasX - histPad.left) / plotW) * 255)));
    const count = histData[channel][bin];
    histReadouts[channel].textContent = `bin ${bin}  (value = ${bin})  ->  count = ${count} px`;
  });
  canvas.addEventListener("mouseleave", () => {
    histReadouts[channel].textContent = "hover to inspect a bin";
  });
}

// ---------------------------------------------------------------------
// Cell 2b: shuffle demo -- same multiset of pixels, random positions,
// identical histogram. Proves a histogram discards spatial information.
// ---------------------------------------------------------------------

const shuffleBtn = document.getElementById("shuffle-btn");
const shuffleStatus = document.getElementById("shuffle-status");
const shuffleOriginalCanvas = document.getElementById("shuffle-original");
const shuffleShuffledCanvas = document.getElementById("shuffle-shuffled");

function intensityHistogramFromImageData(data, method) {
  const bins = new Array(256).fill(0);
  for (let i = 0; i < data.length; i += 4) {
    bins[rgbToIntensity(data[i], data[i + 1], data[i + 2], method)]++;
  }
  return bins;
}

function histogramsEqual(a, b) {
  return a.length === b.length && a.every((v, i) => v === b[i]);
}

shuffleBtn.addEventListener("click", () => {
  const w = sourceImage.naturalWidth;
  const h = sourceImage.naturalHeight;
  const work = document.createElement("canvas");
  work.width = w;
  work.height = h;
  const workCtx = work.getContext("2d");
  workCtx.drawImage(sourceImage, 0, 0, w, h);
  const original = workCtx.getImageData(0, 0, w, h);

  // Fisher-Yates shuffle over whole RGBA pixels (4-byte groups).
  const pixelCount = w * h;
  const order = new Uint32Array(pixelCount);
  for (let i = 0; i < pixelCount; i++) order[i] = i;
  for (let i = pixelCount - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [order[i], order[j]] = [order[j], order[i]];
  }
  const shuffled = workCtx.createImageData(w, h);
  for (let i = 0; i < pixelCount; i++) {
    const src = order[i] * 4;
    const dst = i * 4;
    shuffled.data[dst] = original.data[src];
    shuffled.data[dst + 1] = original.data[src + 1];
    shuffled.data[dst + 2] = original.data[src + 2];
    shuffled.data[dst + 3] = original.data[src + 3];
  }

  const method = intensityMethodSelect.value;
  const before = intensityHistogramFromImageData(original.data, method);
  const after = intensityHistogramFromImageData(shuffled.data, method);

  const drawInto = (canvas, imageData) => {
    canvas.width = w;
    canvas.height = h;
    canvas.getContext("2d").putImageData(imageData, 0, 0);
  };
  drawInto(shuffleOriginalCanvas, original);
  drawInto(shuffleShuffledCanvas, shuffled);

  shuffleStatus.textContent = histogramsEqual(before, after)
    ? "✓ intensity histograms are bin-for-bin identical -- only pixel positions changed"
    : "unexpected: histograms differ (this should never happen for a pure shuffle)";
});

// ---------------------------------------------------------------------
// Cell 3: RGB cube <-> HSV cone
// ---------------------------------------------------------------------

const sliders = {
  r: document.getElementById("slider-r"),
  g: document.getElementById("slider-g"),
  b: document.getElementById("slider-b"),
  h: document.getElementById("slider-h"),
  s: document.getElementById("slider-s"),
  v: document.getElementById("slider-v"),
};
const labels = {
  r: document.getElementById("val-r"),
  g: document.getElementById("val-g"),
  b: document.getElementById("val-b"),
  h: document.getElementById("val-h"),
  s: document.getElementById("val-s"),
  v: document.getElementById("val-v"),
};
const colorPreview = document.getElementById("color-preview");
const cubeCanvas = document.getElementById("cube-canvas");
const coneCanvas = document.getElementById("cone-canvas");
const hueWheel = document.getElementById("hue-wheel");

let state = { r: 255, g: 0, b: 0, h: 0, s: 1, v: 1 };
let updating = false; // reentrancy guard while syncing sliders <-> state

function normalizeHue(h) {
  let wrapped = h % 360;
  if (wrapped < 0) wrapped += 360;
  return wrapped;
}

// Shortest signed step from `from` to `to` around the hue wheel, mirroring
// week3::color::hue_delta on the C++ side. Used by the wrap-around demo so
// the animation crosses through red (0°) instead of the long way around.
function hueDelta(from, to) {
  const raw = normalizeHue(to) - normalizeHue(from);
  if (raw > 180) return raw - 360;
  if (raw < -180) return raw + 360;
  return raw;
}

async function fetchRgbToHsv(r, g, b) {
  const res = await fetch(`/api/rgb-to-hsv?r=${r}&g=${g}&b=${b}`);
  return res.json();
}
async function fetchHsvToRgb(h, s, v) {
  const res = await fetch(`/api/hsv-to-rgb?h=${h}&s=${s}&v=${v}`);
  return res.json();
}

function renderSliders() {
  sliders.r.value = state.r;
  sliders.g.value = state.g;
  sliders.b.value = state.b;
  sliders.h.value = Math.round(state.h);
  sliders.s.value = Math.round(state.s * 100);
  sliders.v.value = Math.round(state.v * 100);
  labels.r.textContent = state.r;
  labels.g.textContent = state.g;
  labels.b.textContent = state.b;
  labels.h.textContent = `${Math.round(state.h)}°`;
  labels.s.textContent = `${Math.round(state.s * 100)}%`;
  labels.v.textContent = `${Math.round(state.v * 100)}%`;
  colorPreview.style.background = `rgb(${state.r}, ${state.g}, ${state.b})`;
  drawCube();
  drawCone();
  drawHueWheel();
}

async function setRgb(r, g, b) {
  if (updating) return;
  updating = true;
  const hsv = await fetchRgbToHsv(r, g, b);
  state = { r, g, b, h: hsv.h, s: hsv.s, v: hsv.v };
  renderSliders();
  updating = false;
}

async function setHsv(h, s, v) {
  if (updating) return;
  updating = true;
  h = normalizeHue(h);
  const rgb = await fetchHsvToRgb(h, s, v);
  state = { r: rgb.r, g: rgb.g, b: rgb.b, h, s, v };
  renderSliders();
  updating = false;
}

sliders.r.addEventListener("input", () =>
  setRgb(+sliders.r.value, +sliders.g.value, +sliders.b.value)
);
sliders.g.addEventListener("input", () =>
  setRgb(+sliders.r.value, +sliders.g.value, +sliders.b.value)
);
sliders.b.addEventListener("input", () =>
  setRgb(+sliders.r.value, +sliders.g.value, +sliders.b.value)
);
sliders.h.addEventListener("input", () =>
  setHsv(+sliders.h.value, +sliders.s.value / 100, +sliders.v.value / 100)
);
sliders.s.addEventListener("input", () =>
  setHsv(+sliders.h.value, +sliders.s.value / 100, +sliders.v.value / 100)
);
sliders.v.addEventListener("input", () =>
  setHsv(+sliders.h.value, +sliders.s.value / 100, +sliders.v.value / 100)
);

// --- RGB cube: isometric projection, R along x, G along depth, B along y ---

function project3d(x, y, z, cx, cy, scale) {
  // Simple isometric-ish projection.
  const angle = Math.PI / 6;
  const px = (x - z) * Math.cos(angle);
  const py = (x + z) * Math.sin(angle) - y;
  return [cx + px * scale, cy + py * scale];
}

function drawCube() {
  const ctx = cubeCanvas.getContext("2d");
  const { width, height } = cubeCanvas;
  ctx.clearRect(0, 0, width, height);
  const cx = width / 2;
  const cy = height / 2 + 15;
  const scale = 105;

  const corners = [];
  for (let x = 0; x <= 1; x++) {
    for (let y = 0; y <= 1; y++) {
      for (let z = 0; z <= 1; z++) {
        corners.push([x, y, z]);
      }
    }
  }
  const edges = [];
  for (let i = 0; i < corners.length; i++) {
    for (let j = i + 1; j < corners.length; j++) {
      const [a, b_] = [corners[i], corners[j]];
      const diff = a.reduce((acc, v, k) => acc + Math.abs(v - b_[k]), 0);
      if (diff === 1) edges.push([a, b_]);
    }
  }

  ctx.strokeStyle = "#3a4150";
  ctx.lineWidth = 1;
  for (const [a, b_] of edges) {
    const [ax, ay] = project3d(a[0], a[1], a[2], cx, cy, scale);
    const [bx, by] = project3d(b_[0], b_[1], b_[2], cx, cy, scale);
    ctx.beginPath();
    ctx.moveTo(ax, ay);
    ctx.lineTo(bx, by);
    ctx.stroke();
  }

  // Axis labels at the far corners.
  ctx.fillStyle = "#8b93a3";
  ctx.font = "11px sans-serif";
  const [rx, ry] = project3d(1.15, 0, 0, cx, cy, scale);
  ctx.fillText("R", rx, ry);
  const [gx, gy] = project3d(0, 1.15, 0, cx, cy, scale);
  ctx.fillText("G", gx, gy);
  const [zx, zy] = project3d(0, 0, 1.15, cx, cy, scale);
  ctx.fillText("B", zx, zy);

  // Marker at the current color's position in the cube.
  const [mx, my] = project3d(state.r / 255, state.g / 255, state.b / 255, cx, cy, scale);
  ctx.beginPath();
  ctx.fillStyle = `rgb(${state.r}, ${state.g}, ${state.b})`;
  ctx.strokeStyle = "#fff";
  ctx.lineWidth = 1.5;
  ctx.arc(mx, my, 7, 0, Math.PI * 2);
  ctx.fill();
  ctx.stroke();
}

// --- HSV cone: apex (V=0, black) at the bottom, base (V=1) circle on top ---

function drawCone() {
  const ctx = coneCanvas.getContext("2d");
  const { width, height } = coneCanvas;
  ctx.clearRect(0, 0, width, height);
  const cx = width / 2;
  const apexY = height - 40;
  const topY = 40;
  const maxRadius = 110;

  // Outline: apex point, two slanted sides, base ellipse.
  ctx.strokeStyle = "#3a4150";
  ctx.beginPath();
  ctx.moveTo(cx, apexY);
  ctx.lineTo(cx - maxRadius, topY);
  ctx.moveTo(cx, apexY);
  ctx.lineTo(cx + maxRadius, topY);
  ctx.stroke();
  ctx.beginPath();
  ctx.ellipse(cx, topY, maxRadius, maxRadius * 0.28, 0, 0, Math.PI * 2);
  ctx.stroke();

  // Sample the hue ring at the base so the cone reads as an HSV solid.
  const steps = 96;
  for (let i = 0; i < steps; i++) {
    const hue = (i / steps) * 360;
    const [x1, y1] = conePoint(hue, 1, 1, cx, apexY, topY, maxRadius);
    const [x2, y2] = conePoint((i + 1) / steps * 360, 1, 1, cx, apexY, topY, maxRadius);
    ctx.strokeStyle = `hsl(${hue}, 100%, 50%)`;
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.moveTo(x1, y1);
    ctx.lineTo(x2, y2);
    ctx.stroke();
  }

  const [mx, my] = conePoint(state.h, state.s, state.v, cx, apexY, topY, maxRadius);
  ctx.beginPath();
  ctx.fillStyle = `rgb(${state.r}, ${state.g}, ${state.b})`;
  ctx.strokeStyle = "#fff";
  ctx.lineWidth = 1.5;
  ctx.arc(mx, my, 7, 0, Math.PI * 2);
  ctx.fill();
  ctx.stroke();
}

function conePoint(hueDeg, s, v, cx, apexY, topY, maxRadius) {
  const rad = (hueDeg * Math.PI) / 180;
  const y = apexY - v * (apexY - topY);
  const radius = s * v * maxRadius;
  const squash = 0.28;
  return [cx + Math.cos(rad) * radius, y - Math.sin(rad) * radius * squash];
}

// --- Hue wheel: draggable dial, demonstrates the 0/360 seam directly ---

function drawHueWheel() {
  const ctx = hueWheel.getContext("2d");
  const { width, height } = hueWheel;
  ctx.clearRect(0, 0, width, height);
  const cx = width / 2;
  const cy = height / 2;
  const outer = Math.min(cx, cy) - 4;
  const inner = outer - 22;

  const steps = 180;
  for (let i = 0; i < steps; i++) {
    const a0 = (i / steps) * Math.PI * 2;
    const a1 = ((i + 1) / steps) * Math.PI * 2;
    const hue = (i / steps) * 360;
    ctx.beginPath();
    ctx.arc(cx, cy, outer, a0, a1);
    ctx.arc(cx, cy, inner, a1, a0, true);
    ctx.closePath();
    ctx.fillStyle = `hsl(${hue}, 100%, 50%)`;
    ctx.fill();
  }

  // Handle at the current hue. Angle 0 points right (matches conePoint).
  const rad = (state.h * Math.PI) / 180;
  const hx = cx + Math.cos(rad) * (inner + outer) / 2;
  const hy = cy - Math.sin(rad) * (inner + outer) / 2;
  ctx.beginPath();
  ctx.arc(hx, hy, 9, 0, Math.PI * 2);
  ctx.fillStyle = `hsl(${state.h}, 100%, 50%)`;
  ctx.strokeStyle = "#fff";
  ctx.lineWidth = 2;
  ctx.fill();
  ctx.stroke();
}

let draggingHue = false;
function angleFromEvent(ev) {
  const rect = hueWheel.getBoundingClientRect();
  const cx = rect.left + rect.width / 2;
  const cy = rect.top + rect.height / 2;
  const dx = ev.clientX - cx;
  const dy = -(ev.clientY - cy);
  // atan2 covers the full circle continuously, including the seam at the
  // top where angle wraps from just under 360° back to 0° -- exactly the
  // red hue boundary, so no special-casing is needed here.
  let deg = (Math.atan2(dy, dx) * 180) / Math.PI;
  return normalizeHue(deg);
}
hueWheel.addEventListener("mousedown", (ev) => {
  draggingHue = true;
  setHsv(angleFromEvent(ev), state.s, state.v);
});
window.addEventListener("mousemove", (ev) => {
  if (!draggingHue) return;
  setHsv(angleFromEvent(ev), state.s, state.v);
});
window.addEventListener("mouseup", () => (draggingHue = false));

// --- Wrap-around demo: animate hue 350° -> 10° the short way, through red ---

document.getElementById("wrap-demo").addEventListener("click", async () => {
  const from = 350;
  const to = 10;
  const delta = hueDelta(from, to); // +20, not -340
  const durationMs = 1400;
  const start = performance.now();

  await setHsv(from, 1, 1);

  function step(now) {
    const t = Math.min(1, (now - start) / durationMs);
    const hue = normalizeHue(from + delta * t);
    setHsv(hue, 1, 1);
    if (t < 1) requestAnimationFrame(step);
  }
  requestAnimationFrame(step);
});

// ---------------------------------------------------------------------
// Boot
// ---------------------------------------------------------------------

refreshIntensityImage();
refreshHistogram();
setRgb(state.r, state.g, state.b);
