#pragma once

#include <algorithm>
#include <array>
#include <cmath>
#include <functional>
#include <memory>
#include <numbers>
#include <string>
#include <string_view>
#include <utility>

#include "arm_model.hpp"
#include "html_plot.hpp"

namespace week4::advanced::diagnostics
{

constexpr double kSanityTolerance = 2.0e-4;

inline double distance(const week4::advanced::arm::Vector3& a,
                       const week4::advanced::arm::Vector3& b) {
    return (a - b).norm();
}

inline double angle_degrees(const week4::advanced::arm::Vector3& a,
                            const week4::advanced::arm::Vector3& b) {
    const double denominator = a.norm() * b.norm();
    if (denominator < 1.0e-9) {
        return 0.0;
    }
    const double cosine = std::clamp(a.dot(b) / denominator, -1.0, 1.0);
    return std::acos(cosine) * 180.0 / std::numbers::pi;
}

struct ScreenPoint
{
    double x{0.0};
    double y{0.0};
};

inline ScreenPoint project_fig1(const week4::advanced::plot::Bounds& bounds,
                                const week4::advanced::arm::Vector3& point) {
    constexpr double kWidth = 1000.0;
    constexpr double kHeight = 560.0;
    constexpr double kMargin = 56.0;
    const double iso_x = point.x() - 0.42 * point.y();
    const double iso_y = point.z() + 0.24 * point.y();
    const double min_iso_x = bounds.min_x - 0.42 * bounds.max_y;
    const double max_iso_x = bounds.max_x - 0.42 * bounds.min_y;
    const double min_iso_y = bounds.min_z + 0.24 * bounds.min_y;
    const double max_iso_y = bounds.max_z + 0.24 * bounds.max_y;
    const double span_x = std::max(1.0e-9, max_iso_x - min_iso_x);
    const double span_y = std::max(1.0e-9, max_iso_y - min_iso_y);
    const double scale = std::min((kWidth - 2.0 * kMargin) / span_x,
                                  (kHeight - 2.0 * kMargin) / span_y);
    const double plot_width = span_x * scale;
    const double plot_height = span_y * scale;
    const double origin_x = (kWidth - plot_width) * 0.5;
    const double origin_y = (kHeight - plot_height) * 0.5;
    return {
        .x = origin_x + (iso_x - min_iso_x) * scale,
        .y = kHeight - origin_y - (iso_y - min_iso_y) * scale,
    };
}

inline double screen_distance(const ScreenPoint& a, const ScreenPoint& b) {
    return std::hypot(a.x - b.x, a.y - b.y);
}

inline double screen_angle_degrees(const ScreenPoint& a, const ScreenPoint& b,
                                   const ScreenPoint& c) {
    const week4::advanced::arm::Vector3 ba{a.x - b.x, a.y - b.y, 0.0};
    const week4::advanced::arm::Vector3 bc{c.x - b.x, c.y - b.y, 0.0};
    return angle_degrees(ba, bc);
}

// Per-sample derived quantities shared by many invariants below, computed
// once per sample instead of being re-derived independently by each check.
struct SampleContext
{
    std::array<ScreenPoint, week4::advanced::arm::kJointFrameCount>
        fig1_frames{};
    std::array<double, week4::advanced::arm::kVisualLinkCount> link_lengths{};
    std::array<double, week4::advanced::arm::kVisualLinkCount>
        fig1_link_pixels{};
    week4::advanced::arm::Vector3 shoulder{};
    week4::advanced::arm::Vector3 elbow{};
    week4::advanced::arm::Vector3 wrist1{};
    week4::advanced::arm::Vector3 wrist2{};
    week4::advanced::arm::Vector3 wrist3{};
    week4::advanced::arm::Vector3 flange{};
    Eigen::Matrix3d base_rotation{};
    Eigen::Matrix3d shoulder_rotation{};
    Eigen::Matrix3d elbow_rotation{};
    Eigen::Matrix3d wrist1_rotation{};
    Eigen::Matrix3d wrist2_rotation{};
    Eigen::Matrix3d wrist3_rotation{};
    double elbow_bend{0.0};
    double upper_length{0.0};
    double forearm_length{0.0};
    double reach_margin{0.0};
    double wrist_span{0.0};
    week4::advanced::arm::Vector3 tool_axis{
        week4::advanced::arm::Vector3::Zero()};
    double projected_elbow{0.0};
    double gripper_finger_pixels{0.0};
    double closed_gripper_cube_pixels{0.0};
};

inline SampleContext build_context(
    const week4::advanced::plot::Bounds& render_bounds,
    const week4::advanced::arm::TrajectorySample& sample) {
    using namespace week4::advanced::arm;
    SampleContext ctx;
    for (std::size_t i = 0; i < sample.joint_frames.size(); ++i) {
        ctx.fig1_frames[i] = project_fig1(
            render_bounds, sample.joint_frames[i].pose.translation());
    }
    for (std::size_t i = 0; i < sample.visual_links.size(); ++i) {
        const auto& link = sample.visual_links[i];
        ctx.link_lengths[i] = distance(link.start, link.end);
        ctx.fig1_link_pixels[i] =
            screen_distance(project_fig1(render_bounds, link.start),
                            project_fig1(render_bounds, link.end));
    }
    ctx.shoulder = sample.joint_frames[1].pose.translation();
    ctx.elbow = sample.joint_frames[2].pose.translation();
    ctx.wrist1 = sample.joint_frames[3].pose.translation();
    ctx.wrist2 = sample.joint_frames[4].pose.translation();
    ctx.wrist3 = sample.joint_frames[5].pose.translation();
    ctx.flange = sample.joint_frames[6].pose.translation();
    ctx.base_rotation = sample.joint_frames[0].pose.so3().matrix();
    ctx.shoulder_rotation = sample.joint_frames[1].pose.so3().matrix();
    ctx.elbow_rotation = sample.joint_frames[2].pose.so3().matrix();
    ctx.wrist1_rotation = sample.joint_frames[3].pose.so3().matrix();
    ctx.wrist2_rotation = sample.joint_frames[4].pose.so3().matrix();
    ctx.wrist3_rotation = sample.joint_frames[5].pose.so3().matrix();
    ctx.elbow_bend =
        angle_degrees(ctx.shoulder - ctx.elbow, ctx.wrist1 - ctx.elbow);
    ctx.upper_length = distance(ctx.shoulder, ctx.elbow);
    ctx.forearm_length = distance(ctx.elbow, ctx.wrist1);
    const double reach_budget = ctx.upper_length + ctx.forearm_length + 0.078 +
                                0.068 + 0.058 + 0.060 +
                                sample.gripper_geometry.palm_length +
                                sample.gripper_geometry.finger_length;
    ctx.reach_margin = reach_budget - distance(ctx.shoulder, sample.target);
    ctx.wrist_span = distance(ctx.wrist1, ctx.flange);
    ctx.tool_axis = sample.tool_pose.so3().matrix().col(2).normalized();
    ctx.projected_elbow = screen_angle_degrees(
        ctx.fig1_frames[1], ctx.fig1_frames[2], ctx.fig1_frames[3]);

    const auto& gripper = sample.gripper_geometry;
    const double jaw = sample.gripper_closed ? gripper.closed_jaw_width
                                             : gripper.open_jaw_width;
    const Vector3 palm_end =
        sample.tool_pose * Vector3{0.0, 0.0, gripper.palm_length};
    const Vector3 left_tip =
        sample.tool_pose * Vector3{jaw * 0.5, gripper.finger_offset,
                                   gripper.palm_length + gripper.finger_length};
    const Vector3 right_tip =
        sample.tool_pose * Vector3{-jaw * 0.5, gripper.finger_offset,
                                   gripper.palm_length + gripper.finger_length};
    ctx.gripper_finger_pixels =
        std::min(screen_distance(project_fig1(render_bounds, palm_end),
                                 project_fig1(render_bounds, left_tip)),
                 screen_distance(project_fig1(render_bounds, palm_end),
                                 project_fig1(render_bounds, right_tip)));

    if (sample.gripper_closed) {
        ctx.closed_gripper_cube_pixels = screen_distance(
            project_fig1(render_bounds, sample.tool_pose.translation()),
            project_fig1(render_bounds, sample.cube_pose.translation()));
    }
    return ctx;
}

// A named check evaluated across the whole trajectory: `observe` folds one
// sample into the check's state, `finalize` turns that state into a
// pass/fail flag plus an optional printable detail. This is the shared
// mechanism every sanity check in physical_checks.hpp / render_checks.hpp is
// expressed through, rather than each one being a bespoke bool/threshold
// bolted onto main().
struct Invariant
{
    std::string_view name;
    std::function<void(const week4::advanced::arm::TrajectorySample&,
                       const SampleContext&)>
        observe;
    std::function<std::pair<bool, std::string>()> finalize;
};

template <class State, class Step, class Finish>
Invariant make_invariant(std::string_view name, State initial, Step step,
                         Finish finish) {
    auto state = std::make_shared<State>(std::move(initial));
    return Invariant{
        .name = name,
        .observe = [state, step](
                       const week4::advanced::arm::TrajectorySample& sample,
                       const SampleContext& ctx) { step(*state, sample, ctx); },
        .finalize = [state, finish]() -> std::pair<bool, std::string> {
            return finish(*state);
        },
    };
}

// An invariant whose state is just "stayed true across every sample", with
// an optional formatted detail computed from the final state.
template <class State, class Step, class Detail>
Invariant make_bool_invariant(std::string_view name, State initial, Step step,
                              Detail detail) {
    struct BoolState
    {
        bool ok{true};
        State data;
    };
    return make_invariant<BoolState>(
        name, BoolState{.ok = true, .data = std::move(initial)},
        [step](BoolState& state, const auto& sample, const auto& ctx) {
            state.ok &= step(state.data, sample, ctx);
        },
        [detail](const BoolState& state) {
            return std::pair<bool, std::string>{state.ok, detail(state.data)};
        });
}

}  // namespace week4::advanced::diagnostics
