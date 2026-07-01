#pragma once

#include <array>
#include <format>
#include <limits>
#include <optional>
#include <string>
#include <vector>

#include "kinematics_control.hpp"
#include "trajectory_diagnostics.hpp"

namespace week4::advanced::diagnostics
{

// Numeric/physical sanity checks: things that must hold regardless of how
// the trajectory is rendered (grasp consistency, joint-limit/singularity
// warnings, link geometry, arm proportions). See render_checks.hpp for the
// Fig. 1 projection-specific checks.
inline std::vector<Invariant> make_physical_checks(
    const week4::advanced::arm::Scene& scene,
    const week4::advanced::arm::TrajectorySample& first_sample,
    const SampleContext& first_ctx) {
    using namespace week4::advanced::arm;
    constexpr double kTolerance = kSanityTolerance;
    const auto no_detail_fn = [](const auto&) { return std::string{}; };

    std::vector<Invariant> checks;
    checks.reserve(20);

    checks.push_back(make_bool_invariant(
        "visual link lengths constant", first_ctx.link_lengths,
        [](const auto& baseline, const auto&, const SampleContext& ctx) {
            bool ok = true;
            for (std::size_t i = 0; i < baseline.size(); ++i) {
                ok &= std::abs(ctx.link_lengths[i] - baseline[i]) < kTolerance;
            }
            return ok;
        },
        no_detail_fn));

    checks.push_back(make_bool_invariant(
        "gripper palm/finger lengths constant", first_sample.gripper_geometry,
        [](const auto& baseline, const auto& sample, const auto&) {
            return std::abs(sample.gripper_geometry.palm_length -
                            baseline.palm_length) < kTolerance &&
                   std::abs(sample.gripper_geometry.finger_length -
                            baseline.finger_length) < kTolerance;
        },
        no_detail_fn));

    checks.push_back(make_bool_invariant(
        "cube remains on source pad before grasp", scene,
        [](const auto& scene, const auto& sample, const auto&) {
            if (sample.gripper_closed || sample.stage_name == "place" ||
                sample.stage_name == "release" ||
                sample.stage_name == "retreat") {
                return true;
            }
            return distance(sample.cube_pose.translation(), scene.source_cube) <
                   kTolerance;
        },
        no_detail_fn));

    struct GraspJumpState
    {
        Scene scene;
        bool was_closed{false};
    };
    checks.push_back(make_bool_invariant(
        "cube has no grasp jump", GraspJumpState{.scene = scene},
        [](GraspJumpState& state, const auto& sample, const auto&) {
            bool ok = true;
            if (sample.gripper_closed && !state.was_closed) {
                ok = distance(sample.cube_pose.translation(),
                              state.scene.source_cube) < 0.010;
            }
            state.was_closed = sample.gripper_closed;
            return ok;
        },
        no_detail_fn));

    struct GraspOffsetState
    {
        bool was_closed{false};
        Pose grasp_tool_T_cube{};
    };
    checks.push_back(make_bool_invariant(
        "cube follows fixed tool_T_cube while grasped", GraspOffsetState{},
        [](GraspOffsetState& state, const auto& sample, const auto&) {
            if (sample.gripper_closed && !state.was_closed) {
                state.grasp_tool_T_cube =
                    sample.tool_pose.inverse() * sample.cube_pose;
            }
            bool ok = true;
            if (sample.gripper_closed) {
                const Pose expected =
                    sample.tool_pose * state.grasp_tool_T_cube;
                ok = distance(expected.translation(),
                              sample.cube_pose.translation()) < kTolerance;
            }
            state.was_closed = sample.gripper_closed;
            return ok;
        },
        no_detail_fn));

    checks.push_back(make_bool_invariant(
        "cube remains on destination pad after release", scene,
        [](const auto& scene, const auto& sample, const auto&) {
            if (sample.gripper_closed || !(sample.stage_name == "release" ||
                                           sample.stage_name == "retreat")) {
                return true;
            }
            return distance(sample.cube_pose.translation(),
                            scene.destination_cube) < kTolerance;
        },
        no_detail_fn));

    checks.push_back(make_bool_invariant(
        "no joint-limit warnings", std::monostate{},
        [](auto&, const auto& sample, const auto&) {
            return !sample.joint_limit_warning;
        },
        no_detail_fn));

    checks.push_back(make_bool_invariant(
        "no Jacobian singularity warnings", std::monostate{},
        [](auto&, const auto& sample, const auto&) {
            return !sample.singularity_warning;
        },
        no_detail_fn));

    struct JointMotionState
    {
        double max_delta{0.0};
        double max_velocity{0.0};
        std::optional<JointVector> previous_joints;
        double previous_time{0.0};
    };
    checks.push_back(make_bool_invariant(
        "joint motion stays smooth", JointMotionState{},
        [](JointMotionState& state, const auto& sample, const auto&) {
            bool ok = true;
            if (state.previous_joints) {
                const JointVector delta =
                    week4::advanced::arm::normalized_joint_delta(
                        sample.joints - *state.previous_joints);
                const double delta_norm = delta.cwiseAbs().maxCoeff();
                const double dt =
                    std::max(1.0e-9, sample.time - state.previous_time);
                state.max_delta = std::max(state.max_delta, delta_norm);
                state.max_velocity =
                    std::max(state.max_velocity, delta_norm / dt);
                ok = delta_norm < 0.060;
            }
            state.previous_joints = sample.joints;
            state.previous_time = sample.time;
            return ok;
        },
        [](const JointMotionState& state) {
            return std::format(
                " (max delta {:.4f} rad, max speed {:.3f} rad/s)",
                state.max_delta, state.max_velocity);
        }));

    struct MinMaxState
    {
        double min{std::numeric_limits<double>::infinity()};
        double max{0.0};
    };
    checks.push_back(make_bool_invariant(
        "stage targets keep reachability margin", MinMaxState{},
        [](MinMaxState& state, const auto&, const SampleContext& ctx) {
            state.min = std::min(state.min, ctx.reach_margin);
            return ctx.reach_margin > 0.035;
        },
        [](const MinMaxState& state) {
            return std::format(" (min {:.3f} m)", state.min);
        }));

    checks.push_back(make_bool_invariant(
        "elbow bend stays visibly articulated", MinMaxState{},
        [](MinMaxState& state, const auto&, const SampleContext& ctx) {
            state.min = std::min(state.min, ctx.elbow_bend);
            state.max = std::max(state.max, ctx.elbow_bend);
            return ctx.elbow_bend > 35.0 && ctx.elbow_bend < 155.0;
        },
        [](const MinMaxState& state) {
            return std::format(" ({:.1f} to {:.1f} deg)", state.min, state.max);
        }));

    checks.push_back(make_bool_invariant(
        "upper/forearm proportions stay compact", std::monostate{},
        [](auto&, const auto&, const SampleContext& ctx) {
            return ctx.upper_length < 0.34 && ctx.forearm_length < 0.26 &&
                   ctx.upper_length / ctx.forearm_length < 1.45;
        },
        no_detail_fn));

    checks.push_back(make_bool_invariant(
        "base yaw axis stays vertical", std::monostate{},
        [](auto&, const auto&, const SampleContext& ctx) {
            return std::abs(ctx.base_rotation.col(2).dot(Vector3::UnitZ())) >
                   0.995;
        },
        no_detail_fn));

    checks.push_back(make_bool_invariant(
        "shoulder/elbow pitch axes stay parallel", std::monostate{},
        [](auto&, const auto&, const SampleContext& ctx) {
            return std::abs(ctx.shoulder_rotation.col(2).dot(
                       ctx.elbow_rotation.col(2))) > 0.980;
        },
        no_detail_fn));

    checks.push_back(make_bool_invariant(
        "wrist stack stays compact", MinMaxState{},
        [](MinMaxState& state, const auto&, const SampleContext& ctx) {
            state.max = std::max(state.max, ctx.wrist_span);
            return ctx.wrist_span < 0.155 &&
                   distance(ctx.wrist1, ctx.wrist2) < 0.090 &&
                   distance(ctx.wrist2, ctx.wrist3) < 0.090 &&
                   distance(ctx.wrist3, ctx.flange) < 0.070;
        },
        [](const MinMaxState& state) {
            return std::format(" (max {:.3f} m)", state.max);
        }));

    checks.push_back(make_bool_invariant(
        "wrist segment lengths match fixed model", std::monostate{},
        [](auto&, const auto&, const SampleContext& ctx) {
            return std::abs(distance(ctx.wrist1, ctx.wrist2) - 0.078) < 0.002 &&
                   std::abs(distance(ctx.wrist2, ctx.wrist3) - 0.068) < 0.002 &&
                   std::abs(distance(ctx.wrist3, ctx.flange) - 0.058) < 0.002;
        },
        no_detail_fn));

    checks.push_back(make_bool_invariant(
        "wrist axes keep expected 6R relation", std::monostate{},
        [](auto&, const auto&, const SampleContext& ctx) {
            return std::abs(ctx.wrist1_rotation.col(2).dot(
                       ctx.wrist2_rotation.col(2))) < 0.15 &&
                   std::abs(ctx.wrist2_rotation.col(2).dot(
                       ctx.wrist3_rotation.col(2))) < 0.15;
        },
        no_detail_fn));

    struct ToolAxisState
    {
        double max_step{0.0};
        std::optional<Vector3> previous_axis;
    };
    checks.push_back(make_bool_invariant(
        "wrist/tool orientation changes continuously", ToolAxisState{},
        [](ToolAxisState& state, const auto&, const SampleContext& ctx) {
            bool ok = true;
            if (state.previous_axis) {
                const double step =
                    angle_degrees(*state.previous_axis, ctx.tool_axis);
                state.max_step = std::max(state.max_step, step);
                ok = step < 4.0;
            }
            state.previous_axis = ctx.tool_axis;
            return ok;
        },
        [](const ToolAxisState& state) {
            return std::format(" (max {:.2f} deg/frame)", state.max_step);
        }));

    checks.push_back(make_bool_invariant(
        "closed gripper contains cube in tool frame", std::monostate{},
        [](auto&, const auto& sample, const auto&) {
            if (!sample.gripper_closed) {
                return true;
            }
            const Vector3 tool_p_cube =
                sample.tool_pose.inverse() * sample.cube_pose.translation();
            const auto& gripper = sample.gripper_geometry;
            return std::abs(tool_p_cube.x()) <
                       gripper.closed_jaw_width * 0.5 + kCubeHalfExtent &&
                   std::abs(tool_p_cube.y()) <
                       gripper.finger_offset + kCubeHalfExtent &&
                   tool_p_cube.z() > gripper.palm_length - kCubeHalfExtent &&
                   tool_p_cube.z() < gripper.palm_length +
                                         gripper.finger_length +
                                         kCubeHalfExtent;
        },
        no_detail_fn));

    checks.push_back(make_bool_invariant(
        "visual link role sequence is exact",
        std::array{LinkRole::pedestal, LinkRole::upper_arm, LinkRole::forearm,
                   LinkRole::wrist_stack, LinkRole::wrist_stack,
                   LinkRole::flange, LinkRole::gripper_palm},
        [](const auto& expected, const auto& sample, const auto&) {
            bool ok = true;
            for (std::size_t i = 0; i < expected.size(); ++i) {
                ok &= sample.visual_links[i].role == expected[i];
            }
            return ok;
        },
        no_detail_fn));

    return checks;
}

}  // namespace week4::advanced::diagnostics
