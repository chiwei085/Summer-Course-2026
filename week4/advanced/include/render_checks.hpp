#pragma once

#include <format>
#include <limits>
#include <optional>
#include <string>
#include <vector>

#include "trajectory_diagnostics.hpp"

namespace week4::advanced::diagnostics
{

// Fig. 1 (isometric HTML render) projection checks: these only guard the
// readability of trajectory.html, not the underlying kinematics/grasp
// correctness — see physical_checks.hpp for those.
inline std::vector<Invariant> make_render_checks() {
    using namespace week4::advanced::arm;

    std::vector<Invariant> checks;
    checks.reserve(7);

    checks.push_back(make_bool_invariant(
        "Fig. 1 projected joints stay on canvas", std::monostate{},
        [](auto&, const auto&, const SampleContext& ctx) {
            bool ok = true;
            for (const auto& point : ctx.fig1_frames) {
                ok &= point.x >= 8.0 && point.x <= 992.0 && point.y >= 8.0 &&
                      point.y <= 552.0;
            }
            return ok;
        },
        [](const auto&) { return std::string{}; }));

    struct MinMaxState
    {
        double min{std::numeric_limits<double>::infinity()};
        double max{0.0};
    };
    checks.push_back(make_bool_invariant(
        "Fig. 1 upper/forearm links remain readable", MinMaxState{},
        [](MinMaxState& state, const auto& sample, const SampleContext& ctx) {
            bool ok = true;
            for (std::size_t i = 0; i < sample.visual_links.size(); ++i) {
                const auto role = sample.visual_links[i].role;
                if (role == LinkRole::upper_arm || role == LinkRole::forearm) {
                    state.min = std::min(state.min, ctx.fig1_link_pixels[i]);
                    ok &= ctx.fig1_link_pixels[i] > 70.0;
                }
            }
            return ok;
        },
        [](const MinMaxState& state) {
            return std::format(" (min {:.1f} px)", state.min);
        }));

    checks.push_back(make_bool_invariant(
        "Fig. 1 wrist links remain visible", MinMaxState{},
        [](MinMaxState& state, const auto& sample, const SampleContext& ctx) {
            bool ok = true;
            for (std::size_t i = 0; i < sample.visual_links.size(); ++i) {
                const auto role = sample.visual_links[i].role;
                if (role == LinkRole::wrist_stack || role == LinkRole::flange) {
                    state.min = std::min(state.min, ctx.fig1_link_pixels[i]);
                    ok &= ctx.fig1_link_pixels[i] > 10.0;
                }
            }
            return ok;
        },
        [](const MinMaxState& state) {
            return std::format(" (min {:.1f} px)", state.min);
        }));

    checks.push_back(make_bool_invariant(
        "Fig. 1 fixed gripper remains visible", MinMaxState{},
        [](MinMaxState& state, const auto& sample, const SampleContext& ctx) {
            bool ok = true;
            for (std::size_t i = 0; i < sample.visual_links.size(); ++i) {
                if (sample.visual_links[i].role == LinkRole::gripper_palm) {
                    state.min = std::min(state.min, ctx.fig1_link_pixels[i]);
                    ok &= ctx.fig1_link_pixels[i] > 7.0;
                }
            }
            state.min = std::min(state.min, ctx.gripper_finger_pixels);
            ok &= ctx.gripper_finger_pixels > 8.0;
            return ok;
        },
        [](const MinMaxState& state) {
            return std::format(" (min {:.1f} px)", state.min);
        }));

    struct Fig1MotionState
    {
        double max_step{0.0};
        std::optional<std::array<ScreenPoint, kJointFrameCount>>
            previous_frames;
    };
    checks.push_back(make_bool_invariant(
        "Fig. 1 projected joint motion is continuous", Fig1MotionState{},
        [](Fig1MotionState& state, const auto&, const SampleContext& ctx) {
            bool ok = true;
            if (state.previous_frames) {
                for (std::size_t i = 0; i < ctx.fig1_frames.size(); ++i) {
                    const double step = screen_distance(
                        ctx.fig1_frames[i], (*state.previous_frames)[i]);
                    state.max_step = std::max(state.max_step, step);
                    ok &= step < 18.0;
                }
            }
            state.previous_frames = ctx.fig1_frames;
            return ok;
        },
        [](const Fig1MotionState& state) {
            return std::format(" (max {:.1f} px/frame)", state.max_step);
        }));

    checks.push_back(make_bool_invariant(
        "Fig. 1 projected elbow remains readable", MinMaxState{},
        [](MinMaxState& state, const auto&, const SampleContext& ctx) {
            state.min = std::min(state.min, ctx.projected_elbow);
            state.max = std::max(state.max, ctx.projected_elbow);
            return ctx.projected_elbow > 28.0 && ctx.projected_elbow < 158.0;
        },
        [](const MinMaxState& state) {
            return std::format(" ({:.1f} to {:.1f} deg)", state.min, state.max);
        }));

    checks.push_back(make_bool_invariant(
        "Fig. 1 closed gripper stays visually on cube", MinMaxState{},
        [](MinMaxState& state, const auto& sample, const SampleContext& ctx) {
            if (!sample.gripper_closed) {
                return true;
            }
            state.max = std::max(state.max, ctx.closed_gripper_cube_pixels);
            return ctx.closed_gripper_cube_pixels < 75.0;
        },
        [](const MinMaxState& state) {
            return std::format(" (max {:.1f} px)", state.max);
        }));

    return checks;
}

}  // namespace week4::advanced::diagnostics
