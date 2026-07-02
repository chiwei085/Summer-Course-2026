"use strict";

// ---------------------------------------------------------------------
// Cell 0: render every LaTeX formula placed in a <span class="eq"
// data-tex="..."> with the vendored KaTeX build (no CDN, per project
// convention).
// ---------------------------------------------------------------------

for (const el of document.querySelectorAll(".eq")) {
  katex.render(el.dataset.tex, el, { throwOnError: false, displayMode: false });
}

// ---------------------------------------------------------------------
// Cell 1: Edge detection (Canny)
// ---------------------------------------------------------------------

const cannyLow = document.getElementById("canny-low");
const cannyHigh = document.getElementById("canny-high");
const cannyLowVal = document.getElementById("canny-low-val");
const cannyHighVal = document.getElementById("canny-high-val");
const edgesCanny = document.getElementById("edges-canny");

function refreshCanny() {
  const low = cannyLow.value;
  const high = cannyHigh.value;
  cannyLowVal.textContent = low;
  cannyHighVal.textContent = high;
  edgesCanny.src = `/api/edges/canny?low=${low}&high=${high}&max_width=480&t=${Date.now()}`;
}
cannyLow.addEventListener("input", refreshCanny);
cannyHigh.addEventListener("input", refreshCanny);

// ---------------------------------------------------------------------
// Cell 2: Corner detection (Harris) -- image served as PNG, corner markers
// served as a JSON point list and drawn client-side on an overlay canvas,
// the same pattern week3/calibration uses for its reprojection overlay.
// ---------------------------------------------------------------------

const harrisK = document.getElementById("harris-k");
const harrisThreshold = document.getElementById("harris-threshold");
const harrisWindowRadius = document.getElementById("harris-window-radius");
const harrisNmsRadius = document.getElementById("harris-nms-radius");
const harrisKVal = document.getElementById("harris-k-val");
const harrisThresholdVal = document.getElementById("harris-threshold-val");
const harrisWindowRadiusVal = document.getElementById("harris-window-radius-val");
const harrisNmsRadiusVal = document.getElementById("harris-nms-radius-val");
const cornersImage = document.getElementById("corners-image");
const cornersCanvas = document.getElementById("corners-canvas");
const cornersReadout = document.getElementById("corners-readout");

let cornersData = null;

function resizeCanvasToImage(img, canvas) {
  const rect = img.getBoundingClientRect();
  canvas.width = rect.width;
  canvas.height = rect.height;
  canvas.style.width = `${rect.width}px`;
  canvas.style.height = `${rect.height}px`;
}

function drawCorners() {
  resizeCanvasToImage(cornersImage, cornersCanvas);
  const ctx = cornersCanvas.getContext("2d");
  ctx.clearRect(0, 0, cornersCanvas.width, cornersCanvas.height);
  if (!cornersData) return;

  const scaleX = cornersCanvas.width / cornersData.image_width;
  const scaleY = cornersCanvas.height / cornersData.image_height;
  ctx.strokeStyle = "#ffd166";
  ctx.lineWidth = 1.5;
  for (const corner of cornersData.corners) {
    const cx = corner.x * scaleX;
    const cy = corner.y * scaleY;
    ctx.beginPath();
    ctx.arc(cx, cy, 4, 0, Math.PI * 2);
    ctx.stroke();
  }
}

async function refreshCorners() {
  const k = harrisK.value;
  const thresholdScaled = Number(harrisThreshold.value) * 1e11;
  const windowRadius = harrisWindowRadius.value;
  const nmsRadius = harrisNmsRadius.value;
  harrisKVal.textContent = Number(k).toFixed(3);
  harrisThresholdVal.textContent = harrisThreshold.value;
  harrisWindowRadiusVal.textContent = windowRadius;
  harrisNmsRadiusVal.textContent = nmsRadius;

  const res = await fetch(
    `/api/corners/detect?k=${k}&threshold=${thresholdScaled}` +
      `&window_radius=${windowRadius}&nms_radius=${nmsRadius}&max_width=640`
  );
  cornersData = await res.json();
  drawCorners();
  cornersReadout.textContent = `${cornersData.corners.length} corner(s) detected`;
}
harrisK.addEventListener("input", refreshCorners);
harrisThreshold.addEventListener("input", refreshCorners);
harrisWindowRadius.addEventListener("input", refreshCorners);
harrisNmsRadius.addEventListener("input", refreshCorners);

cornersCanvas.addEventListener("mousemove", (ev) => {
  if (!cornersData) return;
  const rect = cornersCanvas.getBoundingClientRect();
  const mx = ev.clientX - rect.left;
  const my = ev.clientY - rect.top;
  const scaleX = cornersCanvas.width / cornersData.image_width;
  const scaleY = cornersCanvas.height / cornersData.image_height;

  let closest = null;
  let closestDist = Infinity;
  for (const corner of cornersData.corners) {
    const cx = corner.x * scaleX;
    const cy = corner.y * scaleY;
    const dist = Math.hypot(mx - cx, my - cy);
    if (dist < closestDist) {
      closestDist = dist;
      closest = corner;
    }
  }
  if (closest && closestDist < 10) {
    cornersReadout.textContent =
      `corner (${closest.x}, ${closest.y})  response=${closest.response.toExponential(3)}`;
  } else {
    cornersReadout.textContent = `${cornersData.corners.length} corner(s) detected -- hover a marker to inspect it`;
  }
});

cornersImage.addEventListener("load", drawCorners);
window.addEventListener("resize", () => {
  if (cornersData) drawCorners();
});

// ---------------------------------------------------------------------
// Cell 3: Line detection (Hough transform) -- same PNG-image +
// JSON-overlay-drawn-on-canvas pattern as cell 2.
// ---------------------------------------------------------------------

const houghControls = {
  cannyLow: ["hough-canny-low", "hough-canny-low-val", "canny_low"],
  cannyHigh: ["hough-canny-high", "hough-canny-high-val", "canny_high"],
  threshold: ["hough-threshold", "hough-threshold-val", "threshold"],
  thetaStep: ["hough-theta-step", "hough-theta-step-val", "theta_step"],
  rhoStep: ["hough-rho-step", "hough-rho-step-val", "rho_step"],
  maxLines: ["hough-max-lines", "hough-max-lines-val", "max_lines"],
  minThetaSep: [
    "hough-min-theta-sep",
    "hough-min-theta-sep-val",
    "min_theta_sep",
  ],
  minRhoSep: ["hough-min-rho-sep", "hough-min-rho-sep-val", "min_rho_sep"],
  maxPointDistance: [
    "hough-max-point-distance",
    "hough-max-point-distance-val",
    "max_point_distance",
  ],
  maxGap: ["hough-max-gap", "hough-max-gap-val", "max_gap"],
  minLength: ["hough-min-length", "hough-min-length-val", "min_length"],
};
for (const key of Object.keys(houghControls)) {
  const [inputId, valId, param] = houghControls[key];
  houghControls[key] = {
    input: document.getElementById(inputId),
    val: document.getElementById(valId),
    param,
  };
}
const linesImage = document.getElementById("lines-image");
const linesCanvas = document.getElementById("lines-canvas");
const linesReadout = document.getElementById("lines-readout");

let linesData = null;

function drawLines() {
  resizeCanvasToImage(linesImage, linesCanvas);
  const ctx = linesCanvas.getContext("2d");
  ctx.clearRect(0, 0, linesCanvas.width, linesCanvas.height);
  if (!linesData) return;

  const scaleX = linesCanvas.width / linesData.image_width;
  const scaleY = linesCanvas.height / linesData.image_height;
  ctx.strokeStyle = "#3ddc70";
  ctx.lineWidth = 2;
  for (const seg of linesData.segments) {
    ctx.beginPath();
    ctx.moveTo(seg.x1 * scaleX, seg.y1 * scaleY);
    ctx.lineTo(seg.x2 * scaleX, seg.y2 * scaleY);
    ctx.stroke();
  }
}

async function refreshLines() {
  const params = new URLSearchParams({ max_width: "640" });
  for (const { input, val, param } of Object.values(houghControls)) {
    val.textContent = input.value;
    params.set(param, input.value);
  }

  const res = await fetch(`/api/lines/detect?${params.toString()}`);
  linesData = await res.json();
  drawLines();
  linesReadout.textContent =
    `segments detected: ${linesData.segments.length} (from ${linesData.lines.length} Hough line(s))`;
}
for (const { input } of Object.values(houghControls)) {
  input.addEventListener("input", refreshLines);
}

linesImage.addEventListener("load", drawLines);
window.addEventListener("resize", () => {
  if (linesData) drawLines();
});

// ---------------------------------------------------------------------
// Boot
// ---------------------------------------------------------------------

refreshCorners();
refreshLines();
