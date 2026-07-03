"use strict";

function resizeCanvasToImage(img, canvas) {
  const rect = img.getBoundingClientRect();
  canvas.width = rect.width;
  canvas.height = rect.height;
  canvas.style.width = `${rect.width}px`;
  canvas.style.height = `${rect.height}px`;
}

function drawPolygon(ctx, points, scaleX, scaleY, color, lineWidth) {
  if (points.length === 0) return;
  ctx.strokeStyle = color;
  ctx.lineWidth = lineWidth;
  ctx.beginPath();
  ctx.moveTo(points[0].x * scaleX, points[0].y * scaleY);
  for (let i = 1; i < points.length; i++) {
    ctx.lineTo(points[i].x * scaleX, points[i].y * scaleY);
  }
  ctx.closePath();
  ctx.stroke();
}

// ---------------------------------------------------------------------
// Global: which of the three sample images every cell reacts to.
// ---------------------------------------------------------------------

let currentImageId = 1;
const imageRadios = document.querySelectorAll('#image-select input[name="image"]');
for (const radio of imageRadios) {
  radio.addEventListener("change", () => {
    if (radio.checked) {
      currentImageId = Number(radio.value);
      onImageChanged();
    }
  });
}

// ---------------------------------------------------------------------
// Cell 0: shared foundation -- grayscale, Gaussian blur, Sobel gradient.
// ---------------------------------------------------------------------

const foundSigma = document.getElementById("found-sigma");
const foundSigmaVal = document.getElementById("found-sigma-val");
const foundSource = document.getElementById("found-source");
const foundGrayscale = document.getElementById("found-grayscale");
const foundGradient = document.getElementById("found-gradient");

function refreshFoundation() {
  const sigma = foundSigma.value;
  foundSigmaVal.textContent = Number(sigma).toFixed(1);
  const t = Date.now();
  foundSource.src = `/api/source?id=${currentImageId}&t=${t}`;
  foundGrayscale.src = `/api/grayscale?id=${currentImageId}&sigma=${sigma}&t=${t}`;
  foundGradient.src = `/api/gradient?id=${currentImageId}&sigma=${sigma}&t=${t}`;
}
foundSigma.addEventListener("input", refreshFoundation);

// ---------------------------------------------------------------------
// Cell 1: the automatic initial contour, shown for all three images at
// once (read-only -- it's deterministic per image, driven entirely by its
// config header).
// ---------------------------------------------------------------------

async function loadInitialContourPreview(id) {
  const img = document.getElementById(`init-image-${id}`);
  const canvas = document.getElementById(`init-canvas-${id}`);
  img.src = `/api/source?id=${id}`;
  await new Promise((resolve) => {
    if (img.complete) resolve();
    else img.addEventListener("load", resolve, { once: true });
  });
  resizeCanvasToImage(img, canvas);

  const res = await fetch(`/api/init?id=${id}`);
  const data = await res.json();
  const ctx = canvas.getContext("2d");
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  const scaleX = canvas.width / data.image_width;
  const scaleY = canvas.height / data.image_height;
  drawPolygon(ctx, data.points, scaleX, scaleY, "#ff6f6f", 2);
}

for (const id of [1, 2, 3]) {
  loadInitialContourPreview(id);
  window.addEventListener("resize", () => loadInitialContourPreview(id));
}

// ---------------------------------------------------------------------
// Cell 2: the snake itself -- sliders, a Run button that fetches the full
// per-iteration history, and playback controls to animate it.
// ---------------------------------------------------------------------

const snakeAlpha = document.getElementById("snake-alpha");
const snakeBeta = document.getElementById("snake-beta");
const snakeGamma = document.getElementById("snake-gamma");
const snakeEnergySigma = document.getElementById("snake-energy-sigma");
const snakeSearchRadius = document.getElementById("snake-search-radius");
const snakeIterations = document.getElementById("snake-iterations");
const snakePoints = document.getElementById("snake-points");

const snakeAlphaVal = document.getElementById("snake-alpha-val");
const snakeBetaVal = document.getElementById("snake-beta-val");
const snakeGammaVal = document.getElementById("snake-gamma-val");
const snakeEnergySigmaVal = document.getElementById("snake-energy-sigma-val");
const snakeSearchRadiusVal = document.getElementById("snake-search-radius-val");
const snakeIterationsVal = document.getElementById("snake-iterations-val");
const snakePointsVal = document.getElementById("snake-points-val");

const snakeRunBtn = document.getElementById("snake-run");
const snakeDownloadBtn = document.getElementById("snake-download");
const snakeStatus = document.getElementById("snake-status");
const snakeImage = document.getElementById("snake-image");
const snakeCanvas = document.getElementById("snake-canvas");

const snakePlayBtn = document.getElementById("snake-play");
const snakeStepBackBtn = document.getElementById("snake-step-back");
const snakeStepFwdBtn = document.getElementById("snake-step-fwd");
const snakeFrameSlider = document.getElementById("snake-frame");
const snakeFrameLabel = document.getElementById("snake-frame-label");
const snakeSpeed = document.getElementById("snake-speed");
const snakeSpeedVal = document.getElementById("snake-speed-val");

function syncSliderLabels() {
  snakeAlphaVal.textContent = Number(snakeAlpha.value).toFixed(2);
  snakeBetaVal.textContent = Number(snakeBeta.value).toFixed(2);
  snakeGammaVal.textContent = Number(snakeGamma.value).toFixed(2);
  snakeEnergySigmaVal.textContent = Number(snakeEnergySigma.value).toFixed(1);
  snakeSearchRadiusVal.textContent = snakeSearchRadius.value;
  snakeIterationsVal.textContent = snakeIterations.value;
  snakePointsVal.textContent = snakePoints.value;
  snakeSpeedVal.textContent = snakeSpeed.value;
}
for (const el of [snakeAlpha, snakeBeta, snakeGamma, snakeEnergySigma,
                   snakeSearchRadius, snakeIterations, snakePoints, snakeSpeed]) {
  el.addEventListener("input", syncSliderLabels);
}
syncSliderLabels();

let snakeFrames = [];
let snakeImageDims = { width: 1, height: 1 };
let currentFrame = 0;
let playing = false;
let playTimer = null;

function drawSnakeFrame() {
  const canvas = snakeCanvas;
  resizeCanvasToImage(snakeImage, canvas);
  const ctx = canvas.getContext("2d");
  ctx.clearRect(0, 0, canvas.width, canvas.height);
  if (snakeFrames.length === 0) return;
  const scaleX = canvas.width / snakeImageDims.width;
  const scaleY = canvas.height / snakeImageDims.height;

  // Faint preview of the starting contour so convergence is visible at a
  // glance, plus the current frame drawn on top.
  drawPolygon(ctx, snakeFrames[0], scaleX, scaleY, "rgba(255, 111, 111, 0.35)", 1.5);
  drawPolygon(ctx, snakeFrames[currentFrame], scaleX, scaleY, "#3ddc70", 2.5);

  snakeFrameSlider.value = String(currentFrame);
  snakeFrameLabel.textContent = `frame ${currentFrame} / ${snakeFrames.length - 1}`;
}

function stopPlayback() {
  playing = false;
  snakePlayBtn.textContent = "▶ Play";
  if (playTimer !== null) {
    clearInterval(playTimer);
    playTimer = null;
  }
}

function startPlayback() {
  if (snakeFrames.length === 0) return;
  playing = true;
  snakePlayBtn.textContent = "⏸ Pause";
  const tick = () => {
    if (currentFrame >= snakeFrames.length - 1) {
      stopPlayback();
      return;
    }
    currentFrame += 1;
    drawSnakeFrame();
  };
  playTimer = setInterval(tick, 1000 / Number(snakeSpeed.value));
}

snakePlayBtn.addEventListener("click", () => {
  if (playing) stopPlayback();
  else {
    if (currentFrame >= snakeFrames.length - 1) currentFrame = 0;
    startPlayback();
  }
});
snakeStepBackBtn.addEventListener("click", () => {
  stopPlayback();
  currentFrame = Math.max(0, currentFrame - 1);
  drawSnakeFrame();
});
snakeStepFwdBtn.addEventListener("click", () => {
  stopPlayback();
  currentFrame = Math.min(snakeFrames.length - 1, currentFrame + 1);
  drawSnakeFrame();
});
snakeFrameSlider.addEventListener("input", () => {
  stopPlayback();
  currentFrame = Number(snakeFrameSlider.value);
  drawSnakeFrame();
});

function setPlaybackEnabled(enabled) {
  snakePlayBtn.disabled = !enabled;
  snakeStepBackBtn.disabled = !enabled;
  snakeStepFwdBtn.disabled = !enabled;
  snakeFrameSlider.disabled = !enabled;
  snakeDownloadBtn.disabled = !enabled;
}

function downloadBlob(blob, filename) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement("a");
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}

async function downloadSnakeResult() {
  if (snakeFrames.length === 0) return;
  const composite = document.createElement("canvas");
  composite.width = snakeCanvas.width;
  composite.height = snakeCanvas.height;
  const ctx = composite.getContext("2d");
  ctx.drawImage(snakeImage, 0, 0, composite.width, composite.height);
  ctx.drawImage(snakeCanvas, 0, 0);

  const blob = await new Promise((resolve) => composite.toBlob(resolve, "image/png"));
  downloadBlob(blob, `snake-result-image${currentImageId}.png`);

  const prevStatus = snakeStatus.textContent;
  snakeStatus.textContent = "downloaded result image";
  setTimeout(() => {
    snakeStatus.textContent = prevStatus;
  }, 3000);
}
snakeDownloadBtn.addEventListener("click", downloadSnakeResult);

async function runSnake() {
  stopPlayback();
  snakeRunBtn.disabled = true;
  snakeStatus.textContent = "solving...";
  setPlaybackEnabled(false);

  const params = new URLSearchParams({
    id: String(currentImageId),
    alpha: snakeAlpha.value,
    beta: snakeBeta.value,
    gamma: snakeGamma.value,
    energy_sigma: snakeEnergySigma.value,
    search_radius: snakeSearchRadius.value,
    iterations: snakeIterations.value,
    points: snakePoints.value,
  });

  try {
    const res = await fetch(`/api/run?${params.toString()}`);
    const data = await res.json();
    snakeFrames = data.frames;
    snakeImageDims = { width: data.image_width, height: data.image_height };
    currentFrame = 0;
    snakeFrameSlider.min = "0";
    snakeFrameSlider.max = String(snakeFrames.length - 1);
    drawSnakeFrame();
    setPlaybackEnabled(true);
    snakeStatus.textContent =
      `converged in ${snakeFrames.length - 1} iteration(s) -- press Play or scrub the frame slider`;
  } catch (err) {
    snakeStatus.textContent = `failed: ${err}`;
  } finally {
    snakeRunBtn.disabled = false;
  }
}
snakeRunBtn.addEventListener("click", runSnake);

async function loadSnakeDefaults(id) {
  const res = await fetch(`/api/defaults?id=${id}`);
  const data = await res.json();
  snakeAlpha.value = data.snake.alpha;
  snakeBeta.value = data.snake.beta;
  snakeGamma.value = data.snake.gamma;
  snakeEnergySigma.value = data.snake.energy_sigma;
  snakeSearchRadius.value = data.snake.search_radius;
  snakeIterations.value = data.snake.iterations;
  snakePoints.value = data.init.num_points;
  foundSigma.value = data.init.blur_sigma;
  syncSliderLabels();
}

async function onImageChanged() {
  stopPlayback();
  snakeFrames = [];
  currentFrame = 0;
  setPlaybackEnabled(false);
  snakeFrameLabel.textContent = "frame 0 / 0";
  snakeStatus.textContent = "idle -- click Run to solve, then play back the animation";

  await loadSnakeDefaults(currentImageId);
  refreshFoundation();

  snakeImage.src = `/api/source?id=${currentImageId}&t=${Date.now()}`;
  await new Promise((resolve) => {
    if (snakeImage.complete) resolve();
    else snakeImage.addEventListener("load", resolve, { once: true });
  });
  resizeCanvasToImage(snakeImage, snakeCanvas);
  snakeCanvas.getContext("2d").clearRect(0, 0, snakeCanvas.width, snakeCanvas.height);
}

onImageChanged();
