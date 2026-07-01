#pragma once

#include <algorithm>
#include <fstream>
#include <iomanip>
#include <limits>
#include <span>
#include <string>
#include <string_view>

#include "arm_model.hpp"

namespace week4::advanced::plot
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

inline void include_point(Bounds& bounds, const arm::Vector3& point) {
    bounds.min_x = std::min(bounds.min_x, point.x());
    bounds.max_x = std::max(bounds.max_x, point.x());
    bounds.min_y = std::min(bounds.min_y, point.y());
    bounds.max_y = std::max(bounds.max_y, point.y());
    bounds.min_z = std::min(bounds.min_z, point.z());
    bounds.max_z = std::max(bounds.max_z, point.z());
}

inline Bounds compute_bounds(std::span<const arm::TrajectorySample> samples,
                             std::span<const arm::Stage> stages) {
    Bounds bounds;
    include_point(bounds, {0.0, 0.0, 0.0});
    for (const auto& sample : samples) {
        for (const auto& link : sample.visual_links) {
            include_point(bounds, link.start);
            include_point(bounds, link.end);
        }
        for (const auto& frame : sample.joint_frames) {
            include_point(bounds, frame.pose.translation());
        }
        include_point(bounds, sample.cube_pose.translation());
        include_point(bounds, sample.tool_pose.translation());
        include_point(bounds, sample.source_pad);
        include_point(bounds, sample.destination_pad);
    }
    for (const auto& stage : stages) {
        include_point(bounds, stage.world_T_target.translation());
    }
    bounds.min_x -= 0.18;
    bounds.max_x += 0.18;
    bounds.min_y -= 0.18;
    bounds.max_y += 0.18;
    bounds.min_z = std::min(bounds.min_z, -0.02);
    bounds.max_z += 0.18;
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

class JsObjectWriter
{
public:
    explicit JsObjectWriter(std::ofstream& out) : out_(out) { out_ << "{"; }
    ~JsObjectWriter() { out_ << "}"; }

    template <class T>
    JsObjectWriter& field(std::string_view name, const T& value) {
        key(name);
        out_ << value;
        return *this;
    }

    // For composite values (nested arrays/objects) that are themselves built
    // by writing directly to the stream via a JsObjectWriter/JsArrayWriter.
    template <class Fn>
    JsObjectWriter& field_fn(std::string_view name, Fn&& fn) {
        key(name);
        fn(out_);
        return *this;
    }

private:
    void key(std::string_view name) {
        if (!first_) {
            out_ << ",";
        }
        out_ << name << ":";
        first_ = false;
    }

    std::ofstream& out_;
    bool first_{true};
};

class JsArrayWriter
{
public:
    explicit JsArrayWriter(std::ofstream& out) : out_(out) { out_ << "["; }
    ~JsArrayWriter() { out_ << "]"; }

    template <class T>
    JsArrayWriter& item(const T& value) {
        separator();
        out_ << value;
        return *this;
    }

    template <class Fn>
    JsArrayWriter& item_fn(Fn&& fn) {
        separator();
        fn(out_);
        return *this;
    }

private:
    void separator() {
        if (!first_) {
            out_ << ",";
        }
        first_ = false;
    }

    std::ofstream& out_;
    bool first_{true};
};

inline void write_vector(std::ofstream& html, const arm::Vector3& point) {
    JsArrayWriter{html}.item(point.x()).item(point.y()).item(point.z());
}

inline std::string_view role_string(arm::JointRole role) {
    switch (role) {
        case arm::JointRole::base:
            return "base";
        case arm::JointRole::shoulder:
            return "shoulder";
        case arm::JointRole::elbow:
            return "elbow";
        case arm::JointRole::wrist1:
            return "wrist1";
        case arm::JointRole::wrist2:
            return "wrist2";
        case arm::JointRole::wrist3:
            return "wrist3";
        case arm::JointRole::flange:
            return "flange";
        case arm::JointRole::tool:
            return "tool";
    }
    return "joint";
}

inline std::string_view role_string(arm::LinkRole role) {
    switch (role) {
        case arm::LinkRole::pedestal:
            return "pedestal";
        case arm::LinkRole::upper_arm:
            return "upper_arm";
        case arm::LinkRole::forearm:
            return "forearm";
        case arm::LinkRole::wrist_stack:
            return "wrist_stack";
        case arm::LinkRole::flange:
            return "flange";
        case arm::LinkRole::gripper_palm:
            return "gripper_palm";
    }
    return "link";
}

inline void write_pose(std::ofstream& html, const arm::Pose& pose) {
    const Eigen::Matrix3d rotation = pose.so3().matrix();
    JsObjectWriter{html}
        .field_fn("p",
                  [&](std::ofstream& out) { write_vector(out, pose.translation()); })
        .field_fn("x",
                  [&](std::ofstream& out) {
                      write_vector(out, arm::Vector3(rotation.col(0)));
                  })
        .field_fn("y",
                  [&](std::ofstream& out) {
                      write_vector(out, arm::Vector3(rotation.col(1)));
                  })
        .field_fn("z", [&](std::ofstream& out) {
            write_vector(out, arm::Vector3(rotation.col(2)));
        });
}

inline void write_frame(std::ofstream& html, const arm::JointFrame& frame) {
    JsObjectWriter{html}
        .field("role", js_string(role_string(frame.role)))
        .field_fn("pose", [&](std::ofstream& out) {
            write_pose(out, frame.pose);
        });
}

inline void write_link(std::ofstream& html, const arm::VisualLink& link) {
    JsObjectWriter{html}
        .field("role", js_string(role_string(link.role)))
        .field_fn("a", [&](std::ofstream& out) { write_vector(out, link.start); })
        .field_fn("b", [&](std::ofstream& out) { write_vector(out, link.end); })
        .field("r", link.radius);
}

inline void write_gripper(std::ofstream& html,
                          const arm::GripperGeometry& gripper) {
    JsObjectWriter{html}
        .field("palm", gripper.palm_length)
        .field("finger", gripper.finger_length)
        .field("offset", gripper.finger_offset)
        .field("open", gripper.open_jaw_width)
        .field("closed", gripper.closed_jaw_width);
}

inline void write_sample(std::ofstream& html,
                         const arm::TrajectorySample& sample) {
    JsObjectWriter{html}
        .field("t", sample.time)
        .field("stage", sample.stage_index)
        .field("name", js_string(sample.stage_name))
        .field("closed", sample.gripper_closed ? "true" : "false")
        .field("limit", sample.joint_limit_warning ? "true" : "false")
        .field("singular", sample.singularity_warning ? "true" : "false")
        .field_fn("frames",
                  [&](std::ofstream& out) {
                      JsArrayWriter frames{out};
                      for (const auto& frame : sample.joint_frames) {
                          frames.item_fn([&](std::ofstream& o) {
                              write_frame(o, frame);
                          });
                      }
                  })
        .field_fn("links",
                  [&](std::ofstream& out) {
                      JsArrayWriter links{out};
                      for (const auto& link : sample.visual_links) {
                          links.item_fn([&](std::ofstream& o) {
                              write_link(o, link);
                          });
                      }
                  })
        .field_fn("tool",
                  [&](std::ofstream& out) { write_pose(out, sample.tool_pose); })
        .field_fn("cube",
                  [&](std::ofstream& out) { write_pose(out, sample.cube_pose); })
        .field_fn("grip",
                  [&](std::ofstream& out) {
                      write_gripper(out, sample.gripper_geometry);
                  })
        .field_fn("target",
                  [&](std::ofstream& out) { write_vector(out, sample.target); })
        .field_fn("source",
                  [&](std::ofstream& out) { write_vector(out, sample.source_pad); })
        .field_fn("dest",
                  [&](std::ofstream& out) {
                      write_vector(out, sample.destination_pad);
                  })
        .field_fn("q",
                  [&](std::ofstream& out) {
                      JsArrayWriter joints{out};
                      for (int i = 0; i < sample.joints.size(); ++i) {
                          joints.item(sample.joints[i]);
                      }
                  })
        .field("et", sample.error.translation_norm)
        .field("er", sample.error.rotation_norm);
}

inline void write_samples(std::ofstream& html,
                          std::span<const arm::TrajectorySample> samples) {
    html << std::setprecision(8) << "const samples = [\n";
    for (const auto& sample : samples) {
        html << "  ";
        write_sample(html, sample);
        html << ",\n";
    }
    html << "];\n";
}

inline void write_stages(std::ofstream& html,
                         std::span<const arm::Stage> stages) {
    html << std::setprecision(8) << "const stages = [\n";
    for (const auto& stage : stages) {
        html << "  ";
        JsObjectWriter{html}.field("name", js_string(stage.name)).field_fn(
            "target", [&](std::ofstream& out) {
                write_vector(out, stage.world_T_target.translation());
            });
        html << ",\n";
    }
    html << "];\n";
}

inline void write_html_animation(const std::string& path,
                                 std::span<const arm::TrajectorySample> samples,
                                 std::span<const arm::Stage> stages,
                                 const arm::ControllerConfig& config,
                                 const Bounds& bounds) {
    if (samples.empty()) {
        return;
    }

    std::ofstream html{path};
    html << std::fixed << std::setprecision(4)
         << "<!doctype html>\n<html lang=\"en\">\n<head>\n"
         << "<meta charset=\"utf-8\">\n"
         << "<meta name=\"viewport\" content=\"width=device-width, "
            "initial-scale=1\">\n"
         << "<title>UR5-Style Robot Arm Pick-and-Place</title>\n"
         << "<style>\n"
         << "body{margin:0;background:#f4f6f5;color:#1f2937;font-family:system-"
            "ui,sans-serif;}\n"
         << "main{max-width:1040px;margin:0 auto;padding:24px;}\n"
         << "canvas{width:100%;background:#fff;border:1px solid #cbd5d1;}\n"
         << "#scene{aspect-ratio:16/9;}#snapshots{aspect-ratio:25/7;}"
            "#errorChart{aspect-ratio:8/3;}\n"
         << "figure{margin:0 0 18px 0;}h1{font-size:1.8rem;margin:0 0 8px;}\n"
         << "figcaption{text-align:center;margin-top:8px;color:#4b5563;"
            "font-size:0.95rem;line-height:1.35;}\n"
         << ".bar{display:flex;gap:12px;align-items:center;flex-wrap:wrap;"
            "margin:14px 0;}button{padding:7px 12px;border:1px solid "
            "#8b9993;background:#fff;cursor:pointer;}input{width:min(560px,"
            "100%);}code{font-family:ui-monospace,monospace;}\n"
         << "</style>\n</head>\n<body>\n<main>\n"
         << "<h1>UR5-style robot arm cube pick-and-place</h1>\n"
         << "<p>translation tolerance <code>" << config.translation_tolerance
         << " m</code>, rotation tolerance <code>" << config.rotation_tolerance
         << " rad</code></p>\n"
         << "<figure><canvas id=\"scene\" width=\"1000\" "
            "height=\"560\"></canvas>"
            "<figcaption>Fig. 1. Orthographic URDF-style primitive rendering "
            "of fixed link visuals, wrist stack, rigid gripper, table pads, "
            "cube, and target marker.</figcaption></figure>\n"
         << "<div class=\"bar\"><button id=\"toggle\">Pause</button>"
            "<input id=\"scrub\" type=\"range\" min=\"0\" value=\"0\">"
            "<span id=\"readout\"></span></div>\n"
         << "<figure><canvas id=\"snapshots\" width=\"1000\" "
            "height=\"280\"></canvas><figcaption>Fig. 2. Stage snapshots for "
            "home, pre-grasp, grasp, lift, transfer, place, release, and "
            "retreat. Use this strip for topology "
            "review.</figcaption></figure>\n"
         << "<figure><canvas id=\"errorChart\" width=\"1000\" "
            "height=\"360\"></canvas><figcaption>Fig. 3. SE(3) pose error "
            "during each pick-and-place stage.</figcaption></figure>\n"
         << "<script>\n";

    write_samples(html, samples);
    write_stages(html, stages);

    html << std::setprecision(8) << "const bounds = ";
    JsObjectWriter(html)
        .field("minX", bounds.min_x)
        .field("maxX", bounds.max_x)
        .field("minY", bounds.min_y)
        .field("maxY", bounds.max_y)
        .field("minZ", bounds.min_z)
        .field("maxZ", bounds.max_z);
    html << ";\n"
         << R"JS(
const canvas = document.querySelector("#scene");
const ctx = canvas.getContext("2d");
const snapshotCanvas = document.querySelector("#snapshots");
const snapshotCtx = snapshotCanvas.getContext("2d");
const errorCanvas = document.querySelector("#errorChart");
const errorCtx = errorCanvas.getContext("2d");
const scrub = document.querySelector("#scrub");
const toggle = document.querySelector("#toggle");
const readout = document.querySelector("#readout");
const sceneSize = {width: 1000, height: 560};
const snapshotSize = {width: 1000, height: 280};
const chartSize = {width: 1000, height: 360};
const pixelRatio = Math.max(1, Math.min(2, window.devicePixelRatio || 1));

function configureCanvas(element, context, size) {
  element.width = Math.round(size.width * pixelRatio);
  element.height = Math.round(size.height * pixelRatio);
  context.setTransform(pixelRatio, 0, 0, pixelRatio, 0, 0);
}

configureCanvas(canvas, ctx, sceneSize);
configureCanvas(snapshotCanvas, snapshotCtx, snapshotSize);
configureCanvas(errorCanvas, errorCtx, chartSize);
scrub.max = Math.max(0, samples.length - 1);
let frame = 0;
let playing = true;

function add(a, b) {
  return [a[0] + b[0], a[1] + b[1], a[2] + b[2]];
}

function sub(a, b) {
  return [a[0] - b[0], a[1] - b[1], a[2] - b[2]];
}

function scale(v, s) {
  return [v[0] * s, v[1] * s, v[2] * s];
}

function dot(a, b) {
  return a[0] * b[0] + a[1] * b[1] + a[2] * b[2];
}

function cross(a, b) {
  return [
    a[1] * b[2] - a[2] * b[1],
    a[2] * b[0] - a[0] * b[2],
    a[0] * b[1] - a[1] * b[0],
  ];
}

function norm(v) {
  return Math.hypot(v[0], v[1], v[2]);
}

function normalize(v) {
  const n = Math.max(1e-9, norm(v));
  return scale(v, 1 / n);
}

function pointOnPose(pose, x, y, z) {
  return add(pose.p, add(scale(pose.x, x), add(scale(pose.y, y), scale(pose.z, z))));
}

function cubeColor(sample) {
  return sample.closed ? "#b45309" : "#d97706";
}

function frameByRole(sample, role) {
  return sample.frames.find((frame) => frame.role === role);
}

const camera = (() => {
  const forward = normalize([0.78, -0.62, 0.55]);
  const right = normalize(cross([0, 0, 1], forward));
  const up = normalize(cross(forward, right));
  return {forward, right, up};
})();

function sceneCenter() {
  return [
    (bounds.minX + bounds.maxX) * 0.5,
    (bounds.minY + bounds.maxY) * 0.5,
    (bounds.minZ + bounds.maxZ) * 0.5,
  ];
}

function projectedExtents() {
  const center = sceneCenter();
  const corners = [];
  for (const x of [bounds.minX, bounds.maxX]) {
    for (const y of [bounds.minY, bounds.maxY]) {
      for (const z of [bounds.minZ, bounds.maxZ]) corners.push([x, y, z]);
    }
  }
  let minX = Infinity, maxX = -Infinity, minY = Infinity, maxY = -Infinity;
  corners.forEach((p) => {
    const d = sub(p, center);
    const x = dot(d, camera.right);
    const y = dot(d, camera.up);
    minX = Math.min(minX, x); maxX = Math.max(maxX, x);
    minY = Math.min(minY, y); maxY = Math.max(maxY, y);
  });
  return {center, minX, maxX, minY, maxY};
}

const viewExtents = projectedExtents();

function projectorFor(viewport, margin = 50) {
  const spanX = Math.max(1e-9, viewExtents.maxX - viewExtents.minX);
  const spanY = Math.max(1e-9, viewExtents.maxY - viewExtents.minY);
  const scalePx = Math.min((viewport.width - 2 * margin) / spanX,
                           (viewport.height - 2 * margin) / spanY);
  const ox = viewport.x + (viewport.width - spanX * scalePx) * 0.5;
  const oy = viewport.y + (viewport.height - spanY * scalePx) * 0.5;
  return {
    scale: scalePx,
    point(p) {
      const d = sub(p, viewExtents.center);
      const x = dot(d, camera.right);
      const y = dot(d, camera.up);
      const z = dot(d, camera.forward);
      return {x: ox + (x - viewExtents.minX) * scalePx,
              y: viewport.y + viewport.height - (oy - viewport.y) - (y - viewExtents.minY) * scalePx,
              z};
    },
  };
}

function shade(color, amount) {
  const n = Number.parseInt(color.slice(1), 16);
  const r = Math.max(0, Math.min(255, ((n >> 16) & 255) + amount));
  const g = Math.max(0, Math.min(255, ((n >> 8) & 255) + amount));
  const b = Math.max(0, Math.min(255, (n & 255) + amount));
  return `rgb(${r},${g},${b})`;
}

function drawPoly(context, points, fill, stroke = "#334155") {
  context.beginPath();
  points.forEach((p, i) => {
    if (i === 0) context.moveTo(p.x, p.y);
    else context.lineTo(p.x, p.y);
  });
  context.closePath();
  context.fillStyle = fill;
  context.fill();
  context.strokeStyle = stroke;
  context.lineWidth = 1;
  context.stroke();
}

function makeBox(center, axes, size, color, name) {
  const hx = size[0] * 0.5, hy = size[1] * 0.5, hz = size[2] * 0.5;
  const corners = [
    [-hx,-hy,-hz],[ hx,-hy,-hz],[ hx, hy,-hz],[-hx, hy,-hz],
    [-hx,-hy, hz],[ hx,-hy, hz],[ hx, hy, hz],[-hx, hy, hz],
  ].map((p) => add(center, add(scale(axes[0], p[0]), add(scale(axes[1], p[1]), scale(axes[2], p[2])))));
  return {kind: "box", corners, color, name,
          depth: corners.reduce((s, p) => s + dot(p, camera.forward), 0) / corners.length};
}

function makeCapsule(a, b, radius, color, name) {
  return {kind: "capsule", a, b, radius, color, name,
          depth: (dot(a, camera.forward) + dot(b, camera.forward)) * 0.5};
}

function makeSphere(center, radius, color, name) {
  return {kind: "sphere", center, radius, color, name,
          depth: dot(center, camera.forward)};
}

function poseAxes(pose) {
  return [pose.x, pose.y, pose.z];
}

function gripperBoxes(sample) {
  const g = sample.grip;
  const jaw = sample.closed ? g.closed : g.open;
  const axes = poseAxes(sample.tool);
  const palm = makeBox(pointOnPose(sample.tool, 0, g.offset, g.palm * 0.5), axes,
                       [jaw + 0.035, 0.030, g.palm], "#2563eb", "tool0 palm");
  const left = makeBox(pointOnPose(sample.tool, jaw * 0.5, g.offset, g.palm + g.finger * 0.5),
                       axes, [0.018, 0.024, g.finger], sample.closed ? "#7c2d12" : "#2563eb", "left finger");
  const right = makeBox(pointOnPose(sample.tool, -jaw * 0.5, g.offset, g.palm + g.finger * 0.5),
                        axes, [0.018, 0.024, g.finger], sample.closed ? "#7c2d12" : "#2563eb", "right finger");
  return [palm, left, right];
}

function robotPrimitives(sample) {
  const base = frameByRole(sample, "base").pose;
  const shoulder = frameByRole(sample, "shoulder").pose;
  const elbow = frameByRole(sample, "elbow").pose;
  const wrist1 = frameByRole(sample, "wrist1").pose;
  const wrist2 = frameByRole(sample, "wrist2").pose;
  const wrist3 = frameByRole(sample, "wrist3").pose;
  const flange = frameByRole(sample, "flange").pose;
  const warn = sample.limit || sample.singular;
  const armColor = warn ? "#991b1b" : "#1f2937";
  return [
    makeCapsule([0, 0, 0], shoulder.p, 0.055, "#475569", "base_link"),
    makeSphere(shoulder.p, 0.060, "#475569", "shoulder_link"),
    makeCapsule(shoulder.p, elbow.p, 0.034, armColor, "upper_arm_link"),
    makeSphere(elbow.p, 0.038, "#e2e8f0", "elbow joint"),
    makeCapsule(elbow.p, wrist1.p, 0.030, warn ? "#991b1b" : "#334155", "forearm_link"),
    makeSphere(wrist1.p, 0.030, "#cbd5e1", "wrist_1_link"),
    makeCapsule(wrist1.p, wrist2.p, 0.022, "#64748b", "wrist_1_to_2"),
    makeSphere(wrist2.p, 0.027, "#94a3b8", "wrist_2_link"),
    makeCapsule(wrist2.p, wrist3.p, 0.020, "#64748b", "wrist_2_to_3"),
    makeSphere(wrist3.p, 0.025, "#cbd5e1", "wrist_3_link"),
    makeCapsule(wrist3.p, flange.p, 0.018, "#64748b", "flange"),
    makeSphere(flange.p, 0.020, "#e2e8f0", "flange disk"),
    ...gripperBoxes(sample),
  ];
}

function cubePrimitive(sample) {
  return makeBox(sample.cube.p, [[1,0,0], [0,1,0], [0,0,1]],
                 [0.08, 0.08, 0.08], cubeColor(sample), "cube");
}

function drawPrimitive(context, primitive, projector, alpha = 1) {
  context.save();
  context.globalAlpha = alpha;
  if (primitive.kind === "capsule") {
    const a = projector.point(primitive.a);
    const b = projector.point(primitive.b);
    context.lineCap = "round";
    context.strokeStyle = primitive.color;
    context.lineWidth = Math.max(3, primitive.radius * projector.scale * 2);
    context.beginPath();
    context.moveTo(a.x, a.y);
    context.lineTo(b.x, b.y);
    context.stroke();
  } else if (primitive.kind === "sphere") {
    const c = projector.point(primitive.center);
    const r = Math.max(3, primitive.radius * projector.scale);
    context.fillStyle = primitive.color;
    context.strokeStyle = "#334155";
    context.lineWidth = 1;
    context.beginPath();
    context.ellipse(c.x, c.y, r * 1.15, r * 0.85, 0, 0, Math.PI * 2);
    context.fill();
    context.stroke();
  } else if (primitive.kind === "box") {
    const p = primitive.corners.map((corner) => projector.point(corner));
    const faces = [
      [0,1,2,3], [4,5,6,7], [0,1,5,4],
      [1,2,6,5], [2,3,7,6], [3,0,4,7],
    ].map((face, i) => ({
      face,
      depth: face.reduce((s, idx) => s + p[idx].z, 0) / 4,
      color: shade(primitive.color, i === 1 ? 22 : (i % 2 === 0 ? -8 : 8)),
    })).sort((a, b) => a.depth - b.depth);
    faces.forEach((face) => drawPoly(context, face.face.map((idx) => p[idx]), face.color));
  }
  context.restore();
}

function drawGround(context, sample, projector, viewport, showLabels) {
  context.strokeStyle = "#d7ded9";
  context.lineWidth = 1;
  for (let x = Math.floor(bounds.minX * 5) / 5; x <= bounds.maxX; x += 0.2) {
    const a = projector.point([x, bounds.minY, 0]);
    const b = projector.point([x, bounds.maxY, 0]);
    context.beginPath(); context.moveTo(a.x, a.y); context.lineTo(b.x, b.y); context.stroke();
  }
  for (let y = Math.floor(bounds.minY * 5) / 5; y <= bounds.maxY; y += 0.2) {
    const a = projector.point([bounds.minX, y, 0]);
    const b = projector.point([bounds.maxX, y, 0]);
    context.beginPath(); context.moveTo(a.x, a.y); context.lineTo(b.x, b.y); context.stroke();
  }
  function pad(center, label, color) {
    const half = 0.105;
    const pts = [
      projector.point([center[0]-half, center[1]-half, 0]),
      projector.point([center[0]+half, center[1]-half, 0]),
      projector.point([center[0]+half, center[1]+half, 0]),
      projector.point([center[0]-half, center[1]+half, 0]),
    ];
    drawPoly(context, pts, color, "#475569");
    if (showLabels) {
      const p = projector.point(center);
      context.fillStyle = "#334155";
      context.font = "13px system-ui, sans-serif";
      context.fillText(label, p.x - 32, p.y + 24);
    }
  }
  pad(sample.source, "source", "#dbeafe");
  pad(sample.dest, "destination", "#dcfce7");
}

function drawRobotScene(context, sample, viewport, options = {}) {
  const projector = projectorFor(viewport, options.margin ?? 50);
  context.save();
  context.beginPath();
  context.rect(viewport.x, viewport.y, viewport.width, viewport.height);
  context.clip();
  context.fillStyle = options.background ?? "#eef2f0";
  context.fillRect(viewport.x, viewport.y, viewport.width, viewport.height);
  drawGround(context, sample, projector, viewport, options.labels ?? true);
  const primitives = [...robotPrimitives(sample), cubePrimitive(sample)]
      .sort((a, b) => a.depth - b.depth);
  primitives.forEach((primitive) => drawPrimitive(context, primitive, projector, options.alpha ?? 1));
  const target = projector.point(sample.target);
  context.strokeStyle = "rgba(220,38,38,0.45)";
  context.lineWidth = 1.5;
  context.beginPath();
  context.arc(target.x, target.y, 7, 0, Math.PI * 2);
  context.moveTo(target.x - 10, target.y);
  context.lineTo(target.x + 10, target.y);
  context.moveTo(target.x, target.y - 10);
  context.lineTo(target.x, target.y + 10);
  context.stroke();
  if (options.overlay !== false) {
    context.fillStyle = "#111827";
    context.font = "16px system-ui, sans-serif";
    context.fillText(`stage ${sample.stage}: ${sample.name}`, viewport.x + 24, viewport.y + 34);
    context.fillText(`t = ${sample.t.toFixed(2)} s`, viewport.x + 24, viewport.y + 58);
    context.fillText(`gripper: ${sample.closed ? "closed" : "open"}${sample.limit ? " | joint limit" : ""}${sample.singular ? " | singular" : ""}`, viewport.x + 24, viewport.y + 82);
  }
  context.restore();
}

function drawScene(index) {
  const sample = samples[index];
  ctx.clearRect(0, 0, sceneSize.width, sceneSize.height);
  drawRobotScene(ctx, sample, {x: 0, y: 0, width: sceneSize.width, height: sceneSize.height});
  readout.textContent =
      `${sample.name} | ${sample.t.toFixed(2)} s | ` +
      `e_t=${sample.et.toFixed(4)} m, e_r=${sample.er.toFixed(4)} rad`;
}

function stageRepresentativeIndices() {
  return stages.map((stage, stageIndex) => {
    let best = samples.findIndex((sample) => sample.stage === stageIndex && sample.name === stage.name);
    for (let i = samples.length - 1; i >= 0; --i) {
      if (samples[i].stage === stageIndex) {
        best = i;
        break;
      }
    }
    return Math.max(0, best);
  });
}

function drawSnapshots() {
  snapshotCtx.clearRect(0, 0, snapshotSize.width, snapshotSize.height);
  snapshotCtx.fillStyle = "#fff";
  snapshotCtx.fillRect(0, 0, snapshotSize.width, snapshotSize.height);
  const indices = stageRepresentativeIndices();
  const tileW = snapshotSize.width / indices.length;
  indices.forEach((sampleIndex, i) => {
    const sample = samples[sampleIndex];
    const viewport = {x: i * tileW, y: 0, width: tileW, height: snapshotSize.height};
    snapshotCtx.strokeStyle = "#e5e7eb";
    snapshotCtx.strokeRect(viewport.x + 0.5, 0.5, tileW - 1, snapshotSize.height - 1);
    drawRobotScene(snapshotCtx, sample, {x: viewport.x, y: 0, width: tileW, height: snapshotSize.height - 26},
                   {labels: false, overlay: false, background: "#fff", margin: 16});
    snapshotCtx.fillStyle = "#111827";
    snapshotCtx.font = "12px system-ui, sans-serif";
    snapshotCtx.fillText(sample.name, viewport.x + 8, snapshotSize.height - 14);
  });
}

function drawErrorChart(index) {
  errorCtx.clearRect(0, 0, chartSize.width, chartSize.height);
  errorCtx.fillStyle = "#fff";
  errorCtx.fillRect(0, 0, chartSize.width, chartSize.height);
  const margin = {l: 58, r: 24, t: 24, b: 44};
  const plotW = chartSize.width - margin.l - margin.r;
  const plotH = chartSize.height - margin.t - margin.b;
  const maxErr = Math.max(0.04, ...samples.map((s) => Math.max(s.et, s.er)));
  const xAt = (i) => margin.l + (i / Math.max(1, samples.length - 1)) * plotW;
  const yAt = (v) => margin.t + plotH - (v / maxErr) * plotH;

  errorCtx.strokeStyle = "#d1d5db";
  errorCtx.lineWidth = 1;
  errorCtx.strokeRect(margin.l, margin.t, plotW, plotH);

  function line(key, color) {
    errorCtx.strokeStyle = color;
    errorCtx.lineWidth = 2;
    errorCtx.beginPath();
    samples.forEach((sample, i) => {
      const x = xAt(i);
      const y = yAt(sample[key]);
      if (i === 0) errorCtx.moveTo(x, y);
      else errorCtx.lineTo(x, y);
    });
    errorCtx.stroke();
  }
  line("et", "#2563eb");
  line("er", "#dc2626");

  const cursorX = xAt(index);
  errorCtx.strokeStyle = "#111827";
  errorCtx.beginPath();
  errorCtx.moveTo(cursorX, margin.t);
  errorCtx.lineTo(cursorX, margin.t + plotH);
  errorCtx.stroke();

  errorCtx.fillStyle = "#111827";
  errorCtx.font = "14px system-ui, sans-serif";
  errorCtx.fillText("translation", margin.l, chartSize.height - 18);
  errorCtx.fillStyle = "#2563eb";
  errorCtx.fillRect(margin.l + 82, chartSize.height - 29, 24, 4);
  errorCtx.fillStyle = "#111827";
  errorCtx.fillText("rotation", margin.l + 128, chartSize.height - 18);
  errorCtx.fillStyle = "#dc2626";
  errorCtx.fillRect(margin.l + 188, chartSize.height - 29, 24, 4);
}

function draw() {
  frame = Math.max(0, Math.min(samples.length - 1, frame));
  scrub.value = frame;
  drawScene(frame);
  drawErrorChart(frame);
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

function tick() {
  if (playing) {
    frame = (frame + 1) % samples.length;
    draw();
  }
  requestAnimationFrame(tick);
}

draw();
drawSnapshots();
requestAnimationFrame(tick);
)JS";

    html << "</script>\n</main>\n</body>\n</html>\n";
}

}  // namespace week4::advanced::plot
