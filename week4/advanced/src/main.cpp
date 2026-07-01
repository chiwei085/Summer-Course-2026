#include <cstdio>
#include <cstdlib>
#include <format>
#include <span>
#include <string_view>
#include <vector>

#include "html_plot.hpp"
#include "physical_checks.hpp"
#include "render_checks.hpp"
#include "task_execution.hpp"
#include "trajectory_diagnostics.hpp"

namespace
{

void write_stdout(std::string_view message) {
    std::fwrite(message.data(), sizeof(char), message.size(), stdout);
}

void write_stderr(std::string_view message) {
    std::fwrite(message.data(), sizeof(char), message.size(), stderr);
}

void print_stats(const week4::advanced::arm::SimulationStats& stats) {
    write_stdout(std::format(
        "stage {} [{}] {} in {} steps ({:.2f} s), translation error = "
        "{:.4f} m, rotation error = {:.4f} rad\n",
        stats.stage_index, stats.stage_name,
        stats.converged ? "reached" : "not reached", stats.steps,
        stats.elapsed_time, stats.final_error.translation_norm,
        stats.final_error.rotation_norm));
}

void print_final_report(const week4::advanced::arm::CubeState& cube,
                        bool passed) {
    const auto position = cube.world_T_cube.translation();
    write_stdout(
        std::format("\nrobot arm pick-and-place result: {}\n"
                    "final cube position: ({:.3f}, {:.3f}, {:.3f}) m\n\n"
                    "trajectory written to trajectory.html\n",
                    passed ? "complete" : "needs tuning", position.x(),
                    position.y(), position.z()));
}

bool print_visual_checks(
    std::span<const week4::advanced::arm::TrajectorySample> trajectory,
    const week4::advanced::arm::Scene& scene,
    const week4::advanced::plot::Bounds& render_bounds) {
    using namespace week4::advanced::diagnostics;
    if (trajectory.empty()) {
        return false;
    }

    const SampleContext first_ctx =
        build_context(render_bounds, trajectory.front());
    std::vector<Invariant> checks =
        make_physical_checks(scene, trajectory.front(), first_ctx);
    std::vector<Invariant> render_checks = make_render_checks();
    checks.insert(checks.end(), render_checks.begin(), render_checks.end());

    for (const auto& sample : trajectory) {
        const SampleContext ctx = build_context(render_bounds, sample);
        for (auto& check : checks) {
            check.observe(sample, ctx);
        }
    }

    write_stdout("\nvisual/numeric sanity checks:\n");
    bool all_ok = true;
    for (auto& check : checks) {
        const auto [ok, suffix] = check.finalize();
        write_stdout(
            std::format("  {}: {}{}\n", check.name, ok ? "yes" : "no", suffix));
        all_ok &= ok;
    }
    return all_ok;
}

}  // namespace

int main() {
    using namespace week4::advanced::arm;

    const RobotModel robot = make_robot_model();
    const Scene scene{};
    const ControllerConfig config{};
    const auto stages = make_task_stages(scene, robot.gripper);
    JointVector joints = stages.front().posture_hint;
    CubeState cube{.world_T_cube =
                       Pose{Eigen::Quaterniond::Identity(), scene.source_cube}};

    write_stdout("SE(3) robot arm cube pick-and-place with Sophus\n\n");

    // stages.front() ("home") is a rough elbow-up joint-space guess, not a
    // pre-solved pose: it is ~180 deg off in tool orientation from its own
    // target, same as every other stage's posture_hint. Every later stage
    // hides that behind a transition from the previous stage's already
    // correctly-oriented end pose; stage 0 has nothing to hide behind, so
    // solving it here, unobserved, keeps the recorded/rendered trajectory
    // starting from an arm that is already docked at home instead of opening
    // with an unexplained ~180 deg wrist flip.
    double warmup_time = 0.0;
    const auto warmup_stats =
        run_stage(joints, cube, robot, scene, stages.front(), 0, warmup_time,
                  config, [](const TrajectorySample&) {});
    if (!warmup_stats.converged) {
        write_stderr("warning: failed to settle into the home configuration\n");
    }

    std::vector<TrajectorySample> trajectory;
    const auto observe = [&](const TrajectorySample& sample) {
        trajectory.push_back(sample);
    };

    const std::span<const Stage> task_stages{stages.data() + 1,
                                             stages.size() - 1};
    double simulation_time = 0.0;
    const auto stats = run_pick_and_place(joints, cube, robot, scene,
                                          task_stages, config, observe,
                                          simulation_time);
    bool passed = warmup_stats.converged && stats.size() == task_stages.size();
    for (const auto& stage_stats : stats) {
        print_stats(stage_stats);
        if (!stage_stats.converged) {
            passed = false;
            write_stderr(
                std::format("stopping because stage {} [{}] did not converge\n",
                            stage_stats.stage_index, stage_stats.stage_name));
            break;
        }
    }

    const auto bounds =
        week4::advanced::plot::compute_bounds(trajectory, task_stages);
    week4::advanced::plot::write_html_animation("trajectory.html", trajectory,
                                                task_stages, config, bounds);
    passed = print_visual_checks(trajectory, scene, bounds) && passed;
    print_final_report(cube, passed);
    return passed ? EXIT_SUCCESS : EXIT_FAILURE;
}
