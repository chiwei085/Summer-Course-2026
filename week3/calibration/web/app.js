"use strict";

// ---------------------------------------------------------------------
// Cell 1: Calibration summary
// ---------------------------------------------------------------------

const summaryError = document.getElementById("summary-error");
const boardCorners = document.getElementById("board-corners");
const boardSquare = document.getElementById("board-square");
const boardIncluded = document.getElementById("board-included");
const intrinsicsMatrix = document.getElementById("intrinsics-matrix");
const paramFx = document.getElementById("param-fx");
const paramFy = document.getElementById("param-fy");
const paramCx = document.getElementById("param-cx");
const paramCy = document.getElementById("param-cy");
const paramSkew = document.getElementById("param-skew");
const paramRms = document.getElementById("param-rms");
const passFail = document.getElementById("pass-fail");

const kPinholeRmsPassThresholdPx = 3.0;

function fmt(value, digits = 4) {
  return typeof value === "number" ? value.toFixed(digits) : "–";
}

function renderSummary(summary) {
  boardCorners.textContent = `${summary.board.cols} x ${summary.board.rows}`;
  boardSquare.textContent = summary.board.square_size;
  const includedCount = summary.views.filter((v) => v.included).length;
  boardIncluded.textContent = `${includedCount} / ${summary.views.length} (min ${summary.min_included_views})`;

  if (!summary.ok) {
    summaryError.hidden = false;
    summaryError.textContent = `calibration failed: ${summary.error}`;
  } else {
    summaryError.hidden = true;
  }

  if (summary.ok) {
    const k = summary.intrinsics;
    intrinsicsMatrix.textContent =
      `[ ${fmt(k.fx)}  ${fmt(k.skew)}  ${fmt(k.cx)} ]\n` +
      `[ ${fmt(0, 4)}  ${fmt(k.fy)}  ${fmt(k.cy)} ]\n` +
      `[ ${fmt(0, 4)}  ${fmt(0, 4)}  ${fmt(1, 4)} ]`;
    paramFx.textContent = fmt(k.fx);
    paramFy.textContent = fmt(k.fy);
    paramCx.textContent = fmt(k.cx);
    paramCy.textContent = fmt(k.cy);
    paramSkew.textContent = fmt(k.skew);
    paramRms.textContent = `${fmt(summary.overall_rms_px)} px`;

    const passed = summary.overall_rms_px < kPinholeRmsPassThresholdPx;
    passFail.textContent = passed
      ? `✓ below the ${kPinholeRmsPassThresholdPx.toFixed(1)} px pinhole-only threshold`
      : `✗ above the ${kPinholeRmsPassThresholdPx.toFixed(1)} px pinhole-only threshold`;
    passFail.className = `pass-fail ${passed ? "pass" : "fail"}`;
  } else {
    intrinsicsMatrix.textContent = "–";
    for (const el of [paramFx, paramFy, paramCx, paramCy, paramSkew, paramRms]) {
      el.textContent = "–";
    }
    passFail.textContent = "";
    passFail.className = "pass-fail";
  }
}

// ---------------------------------------------------------------------
// Cell 3: Per-view table (rendered first so cell 2 can select a default row)
// ---------------------------------------------------------------------

const viewTableBody = document.getElementById("view-table-body");
let selectedView = null;

function renderViewTable(summary) {
  viewTableBody.innerHTML = "";
  for (const view of summary.views) {
    const row = document.createElement("tr");
    row.dataset.name = view.name;
    if (view.name === selectedView) row.classList.add("selected");
    if (!view.included) row.classList.add("excluded");

    const checkCell = document.createElement("td");
    checkCell.className = "col-check";
    const checkbox = document.createElement("input");
    checkbox.type = "checkbox";
    checkbox.checked = view.included;
    checkbox.addEventListener("click", (ev) => ev.stopPropagation());
    checkbox.addEventListener("change", () => toggleView(view.name, checkbox.checked, checkbox));
    checkCell.appendChild(checkbox);
    row.appendChild(checkCell);

    const nameCell = document.createElement("td");
    nameCell.textContent = view.name;
    row.appendChild(nameCell);

    const rmsCell = document.createElement("td");
    rmsCell.textContent = view.rms_px === null ? "–" : `${fmt(view.rms_px, 2)} px`;
    row.appendChild(rmsCell);

    const flagCell = document.createElement("td");
    if (view.suspicious) {
      const tag = document.createElement("span");
      tag.className = "suspicious-tag";
      tag.textContent = "← suspicious";
      flagCell.appendChild(tag);
    }
    row.appendChild(flagCell);

    row.addEventListener("click", () => selectView(view.name));
    viewTableBody.appendChild(row);
  }
}

async function toggleView(name, included, checkboxEl) {
  const res = await fetch(`/api/toggle?name=${encodeURIComponent(name)}&included=${included ? 1 : 0}`);
  if (!res.ok) {
    const message = await res.text();
    alert(message);
    checkboxEl.checked = !included; // revert the optimistic UI change
    return;
  }
  const summary = await res.json();
  renderSummary(summary);
  renderViewTable(summary);
  if (selectedView) await loadOverlay(selectedView);
}

// ---------------------------------------------------------------------
// Cell 2: Reprojection overlay
// ---------------------------------------------------------------------

const overlayTitle = document.getElementById("overlay-title");
const overlayRms = document.getElementById("overlay-rms");
const overlayRefinedNote = document.getElementById("overlay-refined-note");
const overlayImage = document.getElementById("overlay-image");
const overlayCanvas = document.getElementById("overlay-canvas");
const overlayWrap = document.getElementById("overlay-wrap");
const cornerReadout = document.getElementById("corner-readout");

let lastViewData = null;

function selectView(name) {
  selectedView = name;
  for (const row of viewTableBody.children) {
    row.classList.toggle("selected", row.dataset.name === name);
  }
  loadOverlay(name);
}

async function loadOverlay(name) {
  const res = await fetch(`/api/view?name=${encodeURIComponent(name)}`);
  const data = await res.json();
  if (!data.ok) {
    overlayTitle.textContent = `${name} — unavailable`;
    overlayRms.textContent = "";
    overlayRefinedNote.textContent = data.error || "";
    lastViewData = null;
    drawOverlay();
    return;
  }

  lastViewData = data;
  overlayTitle.textContent = data.name;
  overlayRms.textContent = `RMS = ${data.rms_px.toFixed(3)} px`;
  overlayRefinedNote.textContent = data.pose_is_refined
    ? ""
    : "excluded from calibration — pose shown is a closed-form estimate against the current intrinsics, not jointly refined";

  if (overlayImage.src.indexOf(data.image_url) === -1) {
    await new Promise((resolve) => {
      overlayImage.onload = resolve;
      overlayImage.src = data.image_url;
    });
  }
  drawOverlay();
}

function resizeCanvasToImage() {
  const rect = overlayImage.getBoundingClientRect();
  overlayCanvas.width = rect.width;
  overlayCanvas.height = rect.height;
  overlayCanvas.style.width = `${rect.width}px`;
  overlayCanvas.style.height = `${rect.height}px`;
}

function drawOverlay() {
  resizeCanvasToImage();
  const ctx = overlayCanvas.getContext("2d");
  ctx.clearRect(0, 0, overlayCanvas.width, overlayCanvas.height);
  if (!lastViewData) return;

  const scaleX = overlayCanvas.width / lastViewData.image_width;
  const scaleY = overlayCanvas.height / lastViewData.image_height;

  for (const corner of lastViewData.corners) {
    const ox = corner.observed.x * scaleX;
    const oy = corner.observed.y * scaleY;
    const rx = corner.reprojected.x * scaleX;
    const ry = corner.reprojected.y * scaleY;

    ctx.strokeStyle = "#ffd166";
    ctx.lineWidth = 1;
    ctx.beginPath();
    ctx.moveTo(ox, oy);
    ctx.lineTo(rx, ry);
    ctx.stroke();

    ctx.fillStyle = "#3ddc70";
    ctx.beginPath();
    ctx.arc(ox, oy, 4, 0, Math.PI * 2);
    ctx.fill();

    ctx.fillStyle = "#ff5d5d";
    ctx.beginPath();
    ctx.arc(rx, ry, 4, 0, Math.PI * 2);
    ctx.fill();
  }
}

overlayCanvas.addEventListener("mousemove", (ev) => {
  if (!lastViewData) return;
  const rect = overlayCanvas.getBoundingClientRect();
  const mx = ev.clientX - rect.left;
  const my = ev.clientY - rect.top;
  const scaleX = overlayCanvas.width / lastViewData.image_width;
  const scaleY = overlayCanvas.height / lastViewData.image_height;

  let closest = null;
  let closestDist = Infinity;
  for (const corner of lastViewData.corners) {
    const ox = corner.observed.x * scaleX;
    const oy = corner.observed.y * scaleY;
    const dist = Math.hypot(mx - ox, my - oy);
    if (dist < closestDist) {
      closestDist = dist;
      closest = corner;
    }
  }
  if (closest && closestDist < 10) {
    cornerReadout.textContent =
      `corner (row=${closest.row}, col=${closest.col})  observed=(${closest.observed.x.toFixed(1)}, ${closest.observed.y.toFixed(1)})  ` +
      `reprojected=(${closest.reprojected.x.toFixed(1)}, ${closest.reprojected.y.toFixed(1)})  error=${closest.error_px.toFixed(3)} px`;
  } else {
    cornerReadout.textContent = "hover a corner marker to inspect it";
  }
});
overlayCanvas.addEventListener("mouseleave", () => {
  cornerReadout.textContent = "hover a corner marker to inspect it";
});

window.addEventListener("resize", () => {
  if (lastViewData) drawOverlay();
});

// ---------------------------------------------------------------------
// Boot
// ---------------------------------------------------------------------

async function boot() {
  const res = await fetch("/api/summary");
  const summary = await res.json();
  renderSummary(summary);
  renderViewTable(summary);
  if (summary.views.length > 0) selectView(summary.views[0].name);
}

boot();
