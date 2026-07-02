#pragma once

#include <algorithm>
#include <fstream>
#include <iomanip>
#include <limits>
#include <span>
#include <string>
#include <string_view>

#include "diagnostics.hpp"

namespace week4::homework::plot {

struct Bounds {
    double min_x{std::numeric_limits<double>::infinity()};
    double max_x{-std::numeric_limits<double>::infinity()};
    double min_y{std::numeric_limits<double>::infinity()};
    double max_y{-std::numeric_limits<double>::infinity()};
};

inline void include_point(Bounds &bounds, const px4::Vector3 &point) {
    bounds.min_x = std::min(bounds.min_x, point.x());
    bounds.max_x = std::max(bounds.max_x, point.x());
    bounds.min_y = std::min(bounds.min_y, point.y());
    bounds.max_y = std::max(bounds.max_y, point.y());
}

inline Bounds compute_bounds(std::span<const px4::NavigatorSetpoint> waypoints,
                             std::span<const offboard::SimulationSample> samples) {
    Bounds bounds;
    for (const auto &waypoint : waypoints) {
        include_point(bounds, waypoint.position_ned);
    }
    for (const auto &sample : samples) {
        include_point(bounds, sample.setpoint.position);
        include_point(bounds, sample.vehicle.local_position.position);
    }
    const double pad = 0.6;
    bounds.min_x -= pad;
    bounds.max_x += pad;
    bounds.min_y -= pad;
    bounds.max_y += pad;
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

class JsObjectWriter {
  public:
    explicit JsObjectWriter(std::ofstream &out) : out_(out) { out_ << "{"; }
    ~JsObjectWriter() { out_ << "}"; }

    template <class T> JsObjectWriter &field(std::string_view name, const T &value) {
        if (!first_) {
            out_ << ",";
        }
        out_ << name << ":" << value;
        first_ = false;
        return *this;
    }

  private:
    std::ofstream &out_;
    bool first_{true};
};

inline void write_waypoint_markers(std::ofstream &html,
                                   std::span<const px4::NavigatorSetpoint> waypoints) {
    html << "const waypoints = [\n";
    int waypoint_index = 0;
    bool has_previous_marker = false;
    px4::Vector3 previous_marker = px4::Vector3::Zero();
    for (const auto &waypoint : waypoints) {
        const bool duplicate_hold =
            waypoint.command_name == "LOITER_TIME" && has_previous_marker &&
            (waypoint.position_ned - previous_marker).norm() < 1.0e-6;
        if (duplicate_hold) {
            continue;
        }
        html << "  ";
        JsObjectWriter(html)
            .field("wp", waypoint_index)
            .field("seq", waypoint.seq)
            .field("cmd", js_string(waypoint.command_name))
            .field("x", waypoint.position_ned.x())
            .field("y", waypoint.position_ned.y())
            .field("z", waypoint.position_ned.z());
        html << ",\n";
        previous_marker = waypoint.position_ned;
        has_previous_marker = true;
        ++waypoint_index;
    }
    html << "];\n";
}

inline void write_samples(std::ofstream &html,
                          std::span<const offboard::SimulationSample> samples) {
    html << std::setprecision(8) << "const samples = [\n";
    for (const auto &sample : samples) {
        const auto &sp = sample.setpoint;
        const auto &pos = sample.vehicle.local_position.position;
        const auto &vel = sample.vehicle.local_position.velocity;
        html << "  ";
        JsObjectWriter(html)
            .field("t", sample.time_s)
            .field("sx", sp.position.x())
            .field("sy", sp.position.y())
            .field("sz", sp.position.z())
            .field("x", pos.x())
            .field("y", pos.y())
            .field("z", pos.z())
            .field("yaw", sample.vehicle.attitude.yaw)
            .field("spYaw", sp.yaw)
            .field("targetYaw", sp.target_yaw)
            .field("speed", vel.norm())
            .field("spSpeed", sp.velocity.norm())
            .field("acc", sp.acceleration.norm())
            .field("jerk", sp.jerk.norm())
            .field("posErr", sample.error.position_norm)
            .field("yawErr", std::abs(sample.error.yaw_rad))
            .field("tilt", sample.tilt_proxy_rad)
            .field("segment", js_string(sp.segment_name));
        html << ",\n";
    }
    html << "];\n";
}

inline void write_checks(std::ofstream &html,
                         const diagnostics::DiagnosticReport &report) {
    html << "const checks = [\n";
    for (const auto &check : report.checks) {
        html << "  ";
        JsObjectWriter(html)
            .field("name", js_string(check.name))
            .field("passed", check.passed ? "true" : "false")
            .field("detail", js_string(check.detail));
        html << ",\n";
    }
    html << "];\n";
}

inline void write_segments(std::ofstream &html,
                           std::span<const trajectory::SegmentReport> segments) {
    html << "const segments = [\n";
    for (const auto &segment : segments) {
        html << "  ";
        JsObjectWriter(html)
            .field("index", segment.index)
            .field("name", js_string(segment.name))
            .field("duration", segment.duration_s)
            .field("distance", segment.distance_m)
            .field("samples", segment.sample_count);
        html << ",\n";
    }
    html << "];\n";
}

inline void write_html_animation(const std::string &path,
                                 const trajectory::PlannedTrajectory &planned,
                                 const offboard::SimulationResult &simulation,
                                 const diagnostics::DiagnosticReport &report) {
    if (simulation.samples.empty()) {
        return;
    }

    const Bounds bounds =
        compute_bounds(planned.navigator_setpoints, simulation.samples);
    std::ofstream html{path};
    html << std::fixed << std::setprecision(4)
         << "<!doctype html>\n<html lang=\"en\">\n<head>\n"
         << "<meta charset=\"utf-8\">\n"
         << "<meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n"
         << "<title>PX4-Style TrajectorySetpoint Pipeline</title>\n"
         << "<style>\n"
         << "body{margin:0;background:#f6f7f9;color:#17202a;font-family:system-ui,sans-"
            "serif;}\n"
         << "main{max-width:1120px;margin:0 auto;padding:24px;}\n"
         << "canvas{width:100%;background:#fff;border:1px solid "
            "#cfd6df;display:block;}\n"
         << "#scene{aspect-ratio:16/9;}#chart{aspect-ratio:16/4;}\n"
         << "button{padding:7px 12px;border:1px solid #9aa4b2;background:#fff;cursor:"
            "pointer;}\n"
         << ".bar{display:flex;gap:10px;align-items:center;flex-wrap:wrap;margin:12px "
            "0;}input{width:min(560px,100%);}\n"
         << "code{font-family:ui-monospace,monospace;}.muted{color:#52606d;}\n"
         << ".telemetry{display:grid;grid-template-columns:repeat(auto-fit,minmax("
            "140px,1"
            "fr));gap:8px;margin:12px 0;}\n"
         << ".stat{padding:8px 10px;background:#fff;border:1px solid "
            "#e2e6eb;border-radius:6px;}\n"
         << ".stat .label{font-size:11px;color:#6b7280;text-transform:uppercase;letter-"
            "spacing:.03em;}\n"
         << ".stat .value{font-size:18px;font-variant-numeric:tabular-nums;}\n"
         << ".diag{margin:16px 0;}\n"
         << ".diag-summary{display:flex;align-items:center;gap:10px;padding:10px "
            "12px;border-radius:6px;background:#fff;border:1px solid "
            "#e2e6eb;}\n"
         << ".diag-summary.pass{border-left:4px solid "
            "#15803d;}.diag-summary.fail{border-left:4px solid #b91c1c;}\n"
         << ".diag-list{margin-top:8px;flex-direction:column;gap:6px;}\n"
         << ".diag-list:not([hidden]){display:flex;}\n"
         << ".diag-item{padding:8px "
            "10px;border-radius:4px;background:#fff;border-left:4px solid "
            "#e2e6eb;font-size:14px;}\n"
         << ".diag-item.fail{border-left-color:#b91c1c;}.diag-item.pass{border-left-"
            "color:#15803d;color:#52606d;}\n"
         << "</style>\n</head>\n<body><main>\n"
         << "<h1>PX4-style TrajectorySetpoint pipeline</h1>\n"
         << "<p class=\"muted\">LOCAL_NED view: x is north, y is east, z is down. "
            "Altitude is rendered as -z.</p>\n"
         << "<canvas id=\"scene\" width=\"1120\" height=\"630\"></canvas>\n"
         << "<div class=\"bar\"><button id=\"toggle\">Pause</button>"
         << "<input id=\"scrub\" type=\"range\" min=\"0\" value=\"0\">"
         << "<span id=\"readout\"></span></div>\n"
         << "<div id=\"telemetry\" class=\"telemetry\"></div>\n"
         << "<canvas id=\"chart\" width=\"1120\" height=\"280\"></canvas>\n"
         << "<div class=\"diag\">\n"
         << "<div id=\"diagSummary\" class=\"diag-summary\"></div>\n"
         << "<div id=\"diagList\" class=\"diag-list\" hidden></div>\n"
         << "</div>\n"
         << "<script>\n";

    write_waypoint_markers(html, planned.navigator_setpoints);
    write_samples(html, simulation.samples);
    write_segments(html, planned.segments);
    write_checks(html, report);
    html << "const bounds = ";
    JsObjectWriter(html)
        .field("minX", bounds.min_x)
        .field("maxX", bounds.max_x)
        .field("minY", bounds.min_y)
        .field("maxY", bounds.max_y);
    html << ";\n"
         << R"JS(
const scene = document.querySelector("#scene");
const ctx = scene.getContext("2d");
const chart = document.querySelector("#chart");
const cctx = chart.getContext("2d");
const scrub = document.querySelector("#scrub");
const toggle = document.querySelector("#toggle");
const readout = document.querySelector("#readout");
const telemetryEl = document.querySelector("#telemetry");
const diagSummaryEl = document.querySelector("#diagSummary");
const diagListEl = document.querySelector("#diagList");
const size = {w:1120,h:630};
const chartSize = {w:1120,h:280};
const dpr = Math.max(1, Math.min(2, window.devicePixelRatio || 1));
function setup(canvas, context, s) {
  canvas.width = Math.round(s.w * dpr);
  canvas.height = Math.round(s.h * dpr);
  context.setTransform(dpr, 0, 0, dpr, 0, 0);
}
setup(scene, ctx, size);
setup(chart, cctx, chartSize);
scrub.max = Math.max(0, samples.length - 1);
let frame = 0;
let playing = true;

function project(p) {
  const margin = 56;
  const spanX = Math.max(1e-6, bounds.maxX - bounds.minX);
  const spanY = Math.max(1e-6, bounds.maxY - bounds.minY);
  const scale = Math.min((size.w - 2 * margin) / spanY,
                         (size.h - 2 * margin) / spanX);
  const ox = (size.w - spanY * scale) * 0.5;
  const oy = (size.h - spanX * scale) * 0.5;
  return {x: ox + (p.y - bounds.minY) * scale,
          y: size.h - oy - (p.x - bounds.minX) * scale};
}
function altitudeColor(z) {
  const alt = -z;
  const r = Math.max(0, Math.min(1, alt / 3.2));
  return `rgb(${40 + 170 * r},${95 + 60 * (1-r)},${190 - 110 * r})`;
}
function drawPath(points, sx, sy, color, width) {
  ctx.beginPath();
  let started = false;
  for (const p of points) {
    const q = project({x:p[sx], y:p[sy]});
    if (!started) { ctx.moveTo(q.x, q.y); started = true; }
    else { ctx.lineTo(q.x, q.y); }
  }
  ctx.strokeStyle = color;
  ctx.lineWidth = width;
  ctx.stroke();
}
function drawWaypointPolyline() {
  ctx.save();
  ctx.setLineDash([8, 6]);
  ctx.beginPath();
  waypoints.forEach((item, idx) => {
    const p = project(item);
    if (idx === 0) ctx.moveTo(p.x, p.y);
    else ctx.lineTo(p.x, p.y);
  });
  ctx.strokeStyle = "#f59e0b";
  ctx.lineWidth = 2;
  ctx.stroke();
  ctx.restore();
}
function samePoint(a, b) {
  return Math.hypot(a.x - b.x, a.y - b.y) < 1e-6;
}
function drawSetpointCursor(p) {
  ctx.save();
  ctx.strokeStyle = "#2563eb";
  ctx.lineWidth = 2;
  ctx.setLineDash([3, 3]);
  ctx.beginPath(); ctx.arc(p.x, p.y, 12, 0, Math.PI * 2); ctx.stroke();
  ctx.setLineDash([]);
  ctx.beginPath();
  ctx.moveTo(p.x - 16, p.y); ctx.lineTo(p.x - 6, p.y);
  ctx.moveTo(p.x + 6, p.y); ctx.lineTo(p.x + 16, p.y);
  ctx.moveTo(p.x, p.y - 16); ctx.lineTo(p.x, p.y - 6);
  ctx.moveTo(p.x, p.y + 6); ctx.lineTo(p.x, p.y + 16);
  ctx.stroke();
  ctx.restore();
}
function drawActualVehicle(p, yaw, z) {
  const nose = {x: p.x + Math.sin(yaw) * 16, y: p.y - Math.cos(yaw) * 16};
  const left = {x: p.x + Math.sin(yaw + 2.45) * 10, y: p.y - Math.cos(yaw + 2.45) * 10};
  const right = {x: p.x + Math.sin(yaw - 2.45) * 10, y: p.y - Math.cos(yaw - 2.45) * 10};
  ctx.save();
  ctx.fillStyle = altitudeColor(z);
  ctx.strokeStyle = "#111827";
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.moveTo(nose.x, nose.y);
  ctx.lineTo(left.x, left.y);
  ctx.lineTo(right.x, right.y);
  ctx.closePath();
  ctx.fill();
  ctx.stroke();
  ctx.restore();
}
function drawScene(i) {
  const s = samples[i];
  ctx.clearRect(0, 0, size.w, size.h);
  ctx.fillStyle = "#ffffff";
  ctx.fillRect(0, 0, size.w, size.h);
  ctx.strokeStyle = "#e5e7eb";
  ctx.lineWidth = 1;
  for (let n = Math.ceil(bounds.minX); n <= bounds.maxX; ++n) {
    const a = project({x:n,y:bounds.minY});
    const b = project({x:n,y:bounds.maxY});
    ctx.beginPath(); ctx.moveTo(a.x,a.y); ctx.lineTo(b.x,b.y); ctx.stroke();
  }
  for (let e = Math.ceil(bounds.minY); e <= bounds.maxY; ++e) {
    const a = project({x:bounds.minX,y:e});
    const b = project({x:bounds.maxX,y:e});
    ctx.beginPath(); ctx.moveTo(a.x,a.y); ctx.lineTo(b.x,b.y); ctx.stroke();
  }
  drawWaypointPolyline();
  drawPath(samples.slice(0, i + 1), "sx", "sy", "#2563eb", 2);
  drawPath(samples.slice(0, i + 1), "x", "y", "#111827", 3);
  const firstWaypoint = waypoints[0];
  for (const item of waypoints) {
    const p = project(item);
    ctx.fillStyle = item.cmd === "LAND" ? "#b91c1c" : "#f59e0b";
    ctx.beginPath(); ctx.arc(p.x, p.y, 6, 0, Math.PI * 2); ctx.fill();
    const closesLoop = item.wp !== 0 && samePoint(item, firstWaypoint);
    if (closesLoop) continue;
    ctx.fillStyle = "#374151";
    ctx.font = "12px system-ui";
    ctx.fillText(`W${item.wp} ${item.cmd}`, p.x + 8, p.y - 8);
  }
  const sp = project({x:s.sx, y:s.sy});
  const p = project({x:s.x, y:s.y});
  drawSetpointCursor(sp);
  drawActualVehicle(p, s.targetYaw, s.z);
}
function drawChart(i) {
  cctx.clearRect(0, 0, chartSize.w, chartSize.h);
  cctx.fillStyle = "#fff";
  cctx.fillRect(0, 0, chartSize.w, chartSize.h);
  const margin = {l:64,r:18,t:26,b:34};
  const maxT = samples[samples.length - 1].t;
  const maxY = Math.max(0.05, ...samples.map(s => s.posErr)) * 1.1;
  function X(t){ return margin.l + t / maxT * (chartSize.w - margin.l - margin.r); }
  function Y(v){ return chartSize.h - margin.b - v / maxY * (chartSize.h - margin.t - margin.b); }
  cctx.strokeStyle = "#e5e7eb";
  cctx.fillStyle = "#6b7280";
  cctx.font = "11px system-ui";
  cctx.textAlign = "right";
  for (let k = 0; k <= 4; ++k) {
    const y = margin.t + k * (chartSize.h - margin.t - margin.b) / 4;
    cctx.beginPath(); cctx.moveTo(margin.l,y); cctx.lineTo(chartSize.w-margin.r,y); cctx.stroke();
    const value = maxY * (1 - k / 4);
    cctx.fillText(`${value.toFixed(2)}m`, margin.l - 8, y + 4);
  }
  cctx.textAlign = "left";
  cctx.beginPath();
  samples.forEach((s, idx) => {
    const x = X(s.t), y = Y(s.posErr);
    if (idx === 0) cctx.moveTo(x,y); else cctx.lineTo(x,y);
  });
  cctx.strokeStyle = "#dc2626"; cctx.lineWidth = 2; cctx.stroke();
  cctx.strokeStyle = "#111827";
  cctx.beginPath(); cctx.moveTo(X(samples[i].t), margin.t); cctx.lineTo(X(samples[i].t), chartSize.h - margin.b); cctx.stroke();
  cctx.fillStyle = "#111827";
  cctx.font = "13px system-ui";
  cctx.fillText("position tracking error over time", margin.l, 16);
  cctx.textAlign = "right";
  cctx.fillText(`${maxT.toFixed(1)}s`, chartSize.w - margin.r, chartSize.h - 10);
  cctx.textAlign = "left";
  cctx.fillText("0s", margin.l, chartSize.h - 10);
}
function statTile(label, value) {
  const div = document.createElement("div");
  div.className = "stat";
  div.innerHTML = `<div class="label">${label}</div><div class="value">${value}</div>`;
  return div;
}
function renderTelemetry(s) {
  telemetryEl.replaceChildren(
    statTile("segment", s.segment),
    statTile("pos error", `${s.posErr.toFixed(3)} m`),
    statTile("yaw error", `${s.yawErr.toFixed(3)} rad`),
    statTile("speed", `${s.speed.toFixed(2)} m/s`),
    statTile("accel", `${s.acc.toFixed(2)} m/s²`),
    statTile("jerk", `${s.jerk.toFixed(2)} m/s³`),
  );
}
function render() {
  frame = Math.max(0, Math.min(samples.length - 1, frame));
  scrub.value = frame;
  const s = samples[frame];
  readout.textContent = `t=${s.t.toFixed(2)}s`;
  renderTelemetry(s);
  drawScene(frame);
  drawChart(frame);
}
toggle.addEventListener("click", () => {
  playing = !playing;
  toggle.textContent = playing ? "Pause" : "Play";
});
scrub.addEventListener("input", () => { frame = Number(scrub.value); playing = false; toggle.textContent = "Play"; render(); });

const failedChecks = checks.filter(c => !c.passed);
diagSummaryEl.className = `diag-summary ${failedChecks.length === 0 ? "pass" : "fail"}`;
const summaryText = failedChecks.length === 0
  ? `All ${checks.length} diagnostic checks passed`
  : `${failedChecks.length} of ${checks.length} diagnostic checks failed`;
const summaryLabel = document.createElement("span");
summaryLabel.textContent = summaryText;
const detailsToggle = document.createElement("button");
detailsToggle.textContent = "Show details";
detailsToggle.addEventListener("click", () => {
  diagListEl.hidden = !diagListEl.hidden;
  detailsToggle.textContent = diagListEl.hidden ? "Show details" : "Hide details";
});
diagSummaryEl.append(summaryLabel, detailsToggle);
for (const check of checks) {
  const div = document.createElement("div");
  div.className = `diag-item ${check.passed ? "pass" : "fail"}`;
  div.textContent = `${check.passed ? "PASS" : "FAIL"} — ${check.name}: ${check.detail}`;
  diagListEl.appendChild(div);
}

function tick() {
  if (playing) frame = (frame + 1) % samples.length;
  render();
  requestAnimationFrame(tick);
}
tick();
)JS"
         << "</script>\n</main></body>\n</html>\n";
}

} // namespace week4::homework::plot
