#include <cstdio>
#include <cstdlib>
#include <format>
#include <string_view>
#include <vector>

#include "control.hpp"
#include "html_plot.hpp"

namespace
{

void write_stdout(std::string_view message) {
    std::fwrite(message.data(), sizeof(char), message.size(), stdout);
}

void write_stderr(std::string_view message) {
    std::fwrite(message.data(), sizeof(char), message.size(), stderr);
}

void print_stats(const week4::control::SimulationStats& stats,
                 std::string_view waypoint_name) {
    write_stdout(std::format(
        "waypoint {} [{}] {} in {} steps ({:.2f} s), translation error = "
        "{:.4f} m, rotation error = {:.4f} rad\n",
        stats.waypoint_index, waypoint_name,
        stats.converged ? "reached" : "not reached", stats.steps,
        stats.elapsed_time, stats.final_error.translation_norm,
        stats.final_error.rotation_norm));
}

void print_final_report(const week4::control::ErrorSummary& closure,
                        const week4::control::ControllerConfig& config) {
    const bool passed =
        closure.translation_norm < config.translation_tolerance &&
        closure.rotation_norm < config.rotation_tolerance;
    write_stdout(
        std::format("\nclosure error against start pose:\n"
                    "  translation = {:.5f} m\n"
                    "  rotation    = {:.5f} rad\n"
                    "  result      = {}\n\n"
                    "trajectory written to trajectory.html\n",
                    closure.translation_norm, closure.rotation_norm,
                    passed ? "closed loop" : "needs tuning"));
}

}  // namespace

int main() {
    using namespace week4::control;

    const ControllerConfig config{};
    const auto route = make_closed_route();
    Pose world_T_drone = route.front().world_T_goal;
    const Pose world_T_start = world_T_drone;

    std::vector<TrajectorySample> trajectory;
    const auto observe = [&](const TrajectorySample& sample) {
        trajectory.push_back(sample);
    };

    double simulation_time = 0.0;
    write_stdout("SE(3) closed-loop drone pose tracking with Sophus\n\n");

    const auto stats =
        fly_route(world_T_drone, route, config, observe, simulation_time);
    for (std::size_t i = 0; i < stats.size(); ++i) {
        print_stats(stats[i], route[i + 1].name);
        if (!stats[i].converged) {
            write_stderr(
                std::format("stopping because waypoint {} did not converge\n",
                            stats[i].waypoint_index));
            return EXIT_FAILURE;
        }
    }

    const auto closure = pose_error(world_T_drone, world_T_start);
    week4::plot::write_html_animation("trajectory.html", trajectory, route,
                                      closure, config);
    print_final_report(closure, config);
    return EXIT_SUCCESS;
}
