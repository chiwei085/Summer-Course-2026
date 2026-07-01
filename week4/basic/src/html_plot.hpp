#pragma once

#include <algorithm>
#include <fstream>
#include <iomanip>
#include <limits>
#include <span>
#include <string>
#include <string_view>

#include "control.hpp"

namespace week4::plot
{

struct Bounds
{
    double min_x{std::numeric_limits<double>::infinity()};
    double max_x{-std::numeric_limits<double>::infinity()};
    double min_y{std::numeric_limits<double>::infinity()};
    double max_y{-std::numeric_limits<double>::infinity()};
    double min_z{std::numeric_limits<double>::infinity()};
    double max_z{-std::numeric_limits<double>::infinity()};
};

inline void include_point(Bounds& bounds, const control::Vector3& point) {
    bounds.min_x = std::min(bounds.min_x, point.x());
    bounds.max_x = std::max(bounds.max_x, point.x());
    bounds.min_y = std::min(bounds.min_y, point.y());
    bounds.max_y = std::max(bounds.max_y, point.y());
    bounds.min_z = std::min(bounds.min_z, point.z());
    bounds.max_z = std::max(bounds.max_z, point.z());
}

inline Bounds compute_bounds(std::span<const control::TrajectorySample> samples,
                             std::span<const control::Waypoint> route) {
    Bounds bounds;
    for (const auto& sample : samples) {
        include_point(bounds, sample.position);
    }
    for (const auto& waypoint : route) {
        include_point(bounds, waypoint.world_T_goal.translation());
    }
    return bounds;
}

inline std::string js_string(std::string_view text) {
    std::string escaped;
    escaped.reserve(text.size() + 2);
    escaped.push_back('"');
    for (const char c : text) {
        switch (c) {
            case '\\':
                escaped += "\\\\";
                break;
            case '"':
                escaped += "\\\"";
                break;
            case '\n':
                escaped += "\\n";
                break;
            default:
                escaped.push_back(c);
                break;
        }
    }
    escaped.push_back('"');
    return escaped;
}

// Streams a JS object literal `{k1:v1,k2:v2,...}`, tracking commas so
// call sites don't have to hand-manage separator/brace bookkeeping.
class JsObjectWriter
{
   public:
    explicit JsObjectWriter(std::ofstream& out) : out_(out) { out_ << "{"; }
    ~JsObjectWriter() { out_ << "}"; }

    template <class T>
    JsObjectWriter& field(std::string_view name, const T& value) {
        if (!first_) {
            out_ << ",";
        }
        out_ << name << ":" << value;
        first_ = false;
        return *this;
    }

   private:
    std::ofstream& out_;
    bool first_{true};
};

inline void write_samples(std::ofstream& html,
                          std::span<const control::TrajectorySample> samples) {
    html << std::setprecision(8) << "const samples = [\n";
    for (const auto& sample : samples) {
        html << "  ";
        JsObjectWriter(html)
            .field("t", sample.time)
            .field("x", sample.position.x())
            .field("y", sample.position.y())
            .field("z", sample.position.z())
            .field("gx", sample.goal.x())
            .field("gy", sample.goal.y())
            .field("gz", sample.goal.z())
            .field("ex", sample.error.tangent[0])
            .field("ey", sample.error.tangent[1])
            .field("ez", sample.error.tangent[2])
            .field("wx", sample.error.tangent[3])
            .field("wy", sample.error.tangent[4])
            .field("wz", sample.error.tangent[5])
            .field("et", sample.error.translation_norm)
            .field("er", sample.error.rotation_norm);
        html << ",\n";
    }
    html << "];\n";
}

inline void write_waypoints(std::ofstream& html,
                            std::span<const control::Waypoint> route) {
    html << std::setprecision(8) << "const waypoints = [\n";
    for (const auto& waypoint : route) {
        const auto position = waypoint.world_T_goal.translation();
        html << "  ";
        JsObjectWriter(html)
            .field("name", js_string(waypoint.name))
            .field("x", position.x())
            .field("y", position.y())
            .field("z", position.z());
        html << ",\n";
    }
    html << "];\n";
}

inline void write_html_animation(const std::string& path,
                                 std::span<const control::TrajectorySample> samples,
                                 std::span<const control::Waypoint> route,
                                 const control::ErrorSummary& closure,
                                 const control::ControllerConfig& config) {
    if (samples.empty()) {
        return;
    }

    const Bounds bounds = compute_bounds(samples, route);
    std::ofstream html{path};
    html << std::fixed << std::setprecision(4)
         << "<!doctype html>\n<html lang=\"en\">\n<head>\n"
         << "<meta charset=\"utf-8\">\n"
         << "<meta name=\"viewport\" content=\"width=device-width, "
            "initial-scale=1\">\n"
         << "<title>SE(3) Closed-Loop Trajectory</title>\n"
         << "<style>\n"
         << "body{margin:0;background:#f7f7f2;color:#1f2937;font-family:system-"
            "ui,sans-serif;}\n"
         << "main{max-width:980px;margin:0 auto;padding:24px;}\n"
         << "canvas{width:100%;background:#fff;border:1px solid #d4d4cc;}\n"
         << "#scene{aspect-ratio:16/10;}\n"
         << "#errorChart{aspect-ratio:8/3;}\n"
         << "figure{margin:0 0 18px 0;}\n"
         << "figcaption{text-align:center;margin-top:8px;color:#4b5563;"
            "font-size:0.95rem;line-height:1.35;}\n"
         << ".bar{display:flex;gap:12px;align-items:center;flex-wrap:wrap;"
            "margin:14px 0;}\n"
         << "button{padding:7px 12px;border:1px solid "
            "#9ca3af;background:#fff;cursor:pointer;}\n"
         << "input{width:min(520px,100%);}code{font-family:ui-monospace,"
            "monospace;}.math{font-family:Cambria Math,STIX Two Math,Times New "
            "Roman,serif;font-style:italic;white-space:nowrap;}\n"
         << "</style>\n</head>\n<body>\n<main>\n"
         << "<h1>SE(3) closed-loop trajectory</h1>\n"
         << "<p>closure: <code>" << closure.translation_norm
         << " m</code>, <code>" << closure.rotation_norm << " rad</code></p>\n"
         << "<figure>\n"
         << "<canvas id=\"scene\" width=\"960\" height=\"600\"></canvas>\n"
         << "<figcaption>Fig. 1. Top-down XY trajectory with waypoint "
            "translation-tolerance circles. The moving black marker is the "
            "current vehicle position.</figcaption>\n"
         << "</figure>\n"
         << "<div class=\"bar\"><button id=\"toggle\">Pause</button>"
         << "<input id=\"scrub\" type=\"range\" min=\"0\" value=\"0\">"
         << "<span id=\"readout\"></span></div>\n"
         << "<p>Top-down XY view. Point color shows altitude: blue is low, red "
            "is high.</p>\n"
         << "<figure>\n"
         << "<canvas id=\"errorChart\" width=\"960\" height=\"360\"></canvas>\n"
         << "<figcaption>Fig. 2. Body-frame SE(3) log error for waypoint-by-"
            "waypoint pose regulation. Each vertical jump occurs when the "
            "controller reaches one discrete waypoint and switches the target "
            "pose, so the error is recomputed as <span class=\"math\">log("
            "T<sub>body</sub><sup>-1</sup>T<sub>goal</sub>)</span> for the "
            "next waypoint.</figcaption>\n"
         << "</figure>\n"
         << "<script>\n";

    write_samples(html, samples);
    write_waypoints(html, route);

    html << std::setprecision(8) << "const bounds = ";
    JsObjectWriter(html)
        .field("minX", bounds.min_x)
        .field("maxX", bounds.max_x)
        .field("minY", bounds.min_y)
        .field("maxY", bounds.max_y)
        .field("minZ", bounds.min_z)
        .field("maxZ", bounds.max_z);
    html << ";\n" << std::setprecision(8) << "const tolerances = ";
    JsObjectWriter(html)
        .field("t", config.translation_tolerance)
        .field("r", config.rotation_tolerance);
    html << ";\n"
         << R"JS(
const canvas = document.querySelector("#scene");
const ctx = canvas.getContext("2d");
const errorCanvas = document.querySelector("#errorChart");
const errorCtx = errorCanvas.getContext("2d");
const scrub = document.querySelector("#scrub");
const toggle = document.querySelector("#toggle");
const readout = document.querySelector("#readout");
const sceneSize = {width: 960, height: 600};
const chartSize = {width: 960, height: 360};
const pixelRatio = Math.max(1, Math.min(2, window.devicePixelRatio || 1));

function configureCanvas(element, context, size) {
  element.width = Math.round(size.width * pixelRatio);
  element.height = Math.round(size.height * pixelRatio);
  context.setTransform(pixelRatio, 0, 0, pixelRatio, 0, 0);
}

configureCanvas(canvas, ctx, sceneSize);
configureCanvas(errorCanvas, errorCtx, chartSize);
scrub.max = Math.max(0, samples.length - 1);
let frame = 0;
let playing = true;

function plotTransform() {
  const margin = 62;
  const spanX = Math.max(1e-9, bounds.maxX - bounds.minX);
  const spanY = Math.max(1e-9, bounds.maxY - bounds.minY);
  const scale = Math.min((sceneSize.width - 2 * margin) / spanX,
                         (sceneSize.height - 2 * margin) / spanY);
  const plotW = spanX * scale;
  const plotH = spanY * scale;
  const ox = (sceneSize.width - plotW) * 0.5;
  const oy = (sceneSize.height - plotH) * 0.5;
  return {scale, ox, oy};
}

const xyPlot = plotTransform();

function project(p) {
  return {x: xyPlot.ox + (p.x - bounds.minX) * xyPlot.scale,
          y: sceneSize.height - xyPlot.oy - (p.y - bounds.minY) * xyPlot.scale};
}

function altitudeColor(z) {
  const r = Math.max(0, Math.min(1, (z - bounds.minZ) /
                                     Math.max(1e-9, bounds.maxZ - bounds.minZ)));
  return `rgb(${55 + 170 * r},${120 - 35 * r},${210 - 140 * r})`;
}

// Positions/colors only depend on the static sample data, so project them
// once instead of recomputing project()'s scale/margin math for every
// point on every animation frame.
const projected = samples.map(project);
const colors = samples.map((s) => altitudeColor(s.z));
const waypointPoints = waypoints.map(project);
const dotStride = Math.max(1, Math.floor(samples.length / 150));

function waypointIndexForGoal(sample) {
  for (let i = 1; i < waypoints.length; ++i) {
    const w = waypoints[i];
    if (Math.hypot(sample.gx - w.x, sample.gy - w.y, sample.gz - w.z) < 1e-9) {
      return i;
    }
  }
  return -1;
}

const sampleGoalIndexes = samples.map(waypointIndexForGoal);
const reachedFrames = Array(waypoints.length).fill(null);
samples.forEach((sample, i) => {
  const waypointIndex = sampleGoalIndexes[i];
  if (waypointIndex > 0 && reachedFrames[waypointIndex] === null &&
      sample.et < tolerances.t && sample.er < tolerances.r) {
    reachedFrames[waypointIndex] = i;
  }
});

// The trail is drawn on an offscreen layer that is only extended by one
// segment per tick during normal playback, instead of redrawing the
// whole trail from scratch every frame (which was O(frame) per frame).
const trail = document.createElement("canvas");
trail.width = Math.round(sceneSize.width * pixelRatio);
trail.height = Math.round(sceneSize.height * pixelRatio);
const trailCtx = trail.getContext("2d");
trailCtx.setTransform(pixelRatio, 0, 0, pixelRatio, 0, 0);
let trailFrame = -1;

function drawTrailDot(i) {
  trailCtx.fillStyle = colors[i];
  trailCtx.beginPath();
  trailCtx.arc(projected[i].x, projected[i].y, 3, 0, Math.PI * 2);
  trailCtx.fill();
}

function rebuildTrail(upTo) {
  trailCtx.clearRect(0, 0, sceneSize.width, sceneSize.height);
  trailCtx.strokeStyle = "#1f2937";
  trailCtx.lineWidth = 3;
  trailCtx.beginPath();
  for (let i = 0; i <= upTo; ++i) {
    if (i === 0) trailCtx.moveTo(projected[i].x, projected[i].y);
    else trailCtx.lineTo(projected[i].x, projected[i].y);
  }
  trailCtx.stroke();
  for (let i = 0; i <= upTo; i += dotStride) drawTrailDot(i);
}

function extendTrail(from, to) {
  trailCtx.strokeStyle = "#1f2937";
  trailCtx.lineWidth = 3;
  trailCtx.beginPath();
  trailCtx.moveTo(projected[from].x, projected[from].y);
  trailCtx.lineTo(projected[to].x, projected[to].y);
  trailCtx.stroke();
  if (to % dotStride === 0) drawTrailDot(to);
}

function updateTrail() {
  if (frame === trailFrame) return;
  if (frame === trailFrame + 1) extendTrail(trailFrame, frame);
  else rebuildTrail(frame);
  trailFrame = frame;
}

// SE(3) log-error chart. The controller acts on this six-dimensional
// tangent vector: rho is translation in the body frame, phi is the
// rotation vector. Draw it once to an offscreen layer and only redraw the
// moving time cursor during animation.
const chart = document.createElement("canvas");
chart.width = Math.round(chartSize.width * pixelRatio);
chart.height = Math.round(chartSize.height * pixelRatio);
const chartCtx = chart.getContext("2d");
chartCtx.setTransform(pixelRatio, 0, 0, pixelRatio, 0, 0);
const chartMargin = {left: 54, right: 16, top: 24, bottom: 24};
const panelGap = 28;
const panelHeight = (chartSize.height - chartMargin.top - chartMargin.bottom -
                     panelGap) * 0.5;
const totalTime = Math.max(1e-9, samples[samples.length - 1].t);
const translationKeys = ["ex", "ey", "ez"];
const rotationKeys = ["wx", "wy", "wz"];
const se3Colors = {
  ex: "#2563eb", ey: "#16a34a", ez: "#dc2626",
  wx: "#7c3aed", wy: "#ea580c", wz: "#0891b2"
};
const waypointSwitches = [];
for (let i = 1; i < samples.length; ++i) {
  const prev = samples[i - 1];
  const now = samples[i];
  if (Math.hypot(now.gx - prev.gx, now.gy - prev.gy, now.gz - prev.gz) > 1e-9) {
    waypointSwitches.push({index: i, t: now.t});
  }
}

function maxAbs(keys) {
  return Math.max(1e-6, ...samples.flatMap((s) => keys.map((key) => Math.abs(s[key]))));
}

const translationYMax = maxAbs(translationKeys) * 1.1;
const rotationYMax = maxAbs(rotationKeys) * 1.1;

function panelBounds(panel) {
  const top = chartMargin.top + panel * (panelHeight + panelGap);
  return {
    top,
    bottom: top + panelHeight,
    center: top + panelHeight * 0.5,
    yMax: panel === 0 ? translationYMax : rotationYMax
  };
}

function chartX(t) {
  const scaleX = (chartSize.width - chartMargin.left - chartMargin.right) / totalTime;
  return chartMargin.left + t * scaleX;
}

function projectChart(t, value, panel) {
  const bounds = panelBounds(panel);
  return {
    x: chartX(t),
    y: bounds.center - value / bounds.yMax * (panelHeight * 0.5)
  };
}

function drawPanel(panel, title, unit, keys) {
  const bounds = panelBounds(panel);
  chartCtx.strokeStyle = "#d4d4cc";
  chartCtx.lineWidth = 1;
  chartCtx.beginPath();
  chartCtx.moveTo(chartMargin.left, bounds.top);
  chartCtx.lineTo(chartMargin.left, bounds.bottom);
  chartCtx.lineTo(chartSize.width - chartMargin.right, bounds.bottom);
  chartCtx.stroke();

  chartCtx.strokeStyle = "#9ca3af";
  chartCtx.setLineDash([4, 4]);
  chartCtx.beginPath();
  chartCtx.moveTo(chartMargin.left, bounds.center);
  chartCtx.lineTo(chartSize.width - chartMargin.right, bounds.center);
  chartCtx.stroke();
  chartCtx.setLineDash([]);

  waypointSwitches.forEach((mark) => {
    const x = chartX(mark.t);
    chartCtx.strokeStyle = "#e5e7eb";
    chartCtx.beginPath();
    chartCtx.moveTo(x, bounds.top);
    chartCtx.lineTo(x, bounds.bottom);
    chartCtx.stroke();
  });

  keys.forEach((key) => drawSe3Curve(key, se3Colors[key], panel));

  chartCtx.font = "13px system-ui, sans-serif";
  chartCtx.fillStyle = "#1f2937";
  chartCtx.fillText(title, 10, bounds.top + 14);
  chartCtx.fillStyle = "#6b7280";
  chartCtx.fillText(`+${bounds.yMax.toFixed(2)} ${unit}`, chartMargin.left + 4, bounds.top + 12);
  chartCtx.fillText(`-${bounds.yMax.toFixed(2)} ${unit}`, chartMargin.left + 4, bounds.bottom - 4);
}

function drawSe3Curve(key, color, panel) {
  chartCtx.strokeStyle = color;
  chartCtx.lineWidth = 2;
  chartCtx.beginPath();
  samples.forEach((s, i) => {
    const p = projectChart(s.t, s[key], panel);
    if (i === 0) chartCtx.moveTo(p.x, p.y);
    else chartCtx.lineTo(p.x, p.y);
  });
  chartCtx.stroke();
}

chartCtx.font = "13px system-ui, sans-serif";
drawPanel(0, "rho", "m", translationKeys);
drawPanel(1, "phi", "rad", rotationKeys);
[
  ["rho x", "ex"], ["rho y", "ey"], ["rho z", "ez"],
  ["phi x", "wx"], ["phi y", "wy"], ["phi z", "wz"]
].forEach(([label, key], i) => {
  const x = chartSize.width - 348 + i * 56;
  chartCtx.fillStyle = se3Colors[key];
  chartCtx.fillText(label, x, 14);
});

function draw() {
  updateTrail();

  ctx.clearRect(0, 0, sceneSize.width, sceneSize.height);
  ctx.drawImage(trail, 0, 0, sceneSize.width, sceneSize.height);

  const activeWaypoint = sampleGoalIndexes[frame];
  const toleranceRadius = tolerances.t * xyPlot.scale;
  waypoints.forEach((w, i) => {
    if (i === 0) return;
    const reached = reachedFrames[i] !== null && frame >= reachedFrames[i];
    const active = i === activeWaypoint;
    if (!reached && !active) return;

    const p = waypointPoints[i];
    ctx.fillStyle = reached ? "rgba(22,163,74,0.06)" : "rgba(185,28,28,0.04)";
    ctx.strokeStyle = reached ? "rgba(22,163,74,0.55)" : "rgba(185,28,28,0.45)";
    ctx.lineWidth = reached ? 2 : 1.5;
    ctx.beginPath();
    ctx.arc(p.x, p.y, toleranceRadius, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();
  });

  const placedLabels = [];
  const labelOffsets = [
    {x: 12, y: -8}, {x: 12, y: 24}, {x: -126, y: -8},
    {x: -126, y: 24}, {x: 18, y: -32}, {x: 18, y: 44}
  ];
  ctx.font = "15px system-ui, sans-serif";
  waypoints.forEach((w, i) => {
    const p = waypointPoints[i];
    const label = `${i}: ${w.name}`;
    ctx.fillStyle = "#fff";
    ctx.strokeStyle = "#b91c1c";
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.arc(p.x, p.y, 7, 0, Math.PI * 2);
    ctx.fill();
    ctx.stroke();

    const metrics = ctx.measureText(label);
    const width = metrics.width;
    const height = 17;
    const offset = labelOffsets.find((candidate) => {
      const box = {
        x: p.x + candidate.x,
        y: p.y + candidate.y - height,
        w: width,
        h: height + 4
      };
      return !placedLabels.some((other) =>
        box.x < other.x + other.w && box.x + box.w > other.x &&
        box.y < other.y + other.h && box.y + box.h > other.y);
    }) ?? labelOffsets.at(-1);
    const box = {
      x: p.x + offset.x,
      y: p.y + offset.y - height,
      w: width,
      h: height + 4
    };
    placedLabels.push(box);

    ctx.fillStyle = "#1f2937";
    ctx.fillText(label, p.x + offset.x, p.y + offset.y);
  });

  const now = samples[frame];
  const p = projected[frame];
  ctx.fillStyle = "#111827";
  ctx.beginPath();
  ctx.arc(p.x, p.y, 8, 0, Math.PI * 2);
  ctx.fill();

  scrub.value = frame;
  readout.textContent =
    `t=${now.t.toFixed(2)}s  z=${now.z.toFixed(2)}m  ` +
    `error=${now.et.toFixed(3)}m/${now.er.toFixed(3)}rad`;

  errorCtx.clearRect(0, 0, chartSize.width, chartSize.height);
  errorCtx.drawImage(chart, 0, 0, chartSize.width, chartSize.height);
  const cursorX = chartX(now.t);
  errorCtx.strokeStyle = "#111827";
  errorCtx.lineWidth = 1;
  errorCtx.beginPath();
  errorCtx.moveTo(cursorX, chartMargin.top);
  errorCtx.lineTo(cursorX, chartSize.height - chartMargin.bottom);
  errorCtx.stroke();
}

function tick() {
  if (playing) frame = (frame + 1) % samples.length;
  draw();
  requestAnimationFrame(tick);
}

toggle.addEventListener("click", () => {
  playing = !playing;
  toggle.textContent = playing ? "Pause" : "Play";
});
scrub.addEventListener("input", () => {
  frame = Number(scrub.value);
  playing = false;
  toggle.textContent = "Play";
  draw();
});

tick();
)JS"
         << "</script>\n</main>\n</body>\n</html>\n";
}

}  // namespace week4::plot
