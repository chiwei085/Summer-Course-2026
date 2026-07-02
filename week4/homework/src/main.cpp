#include <cstdlib>
#include <exception>
#include <format>
#include <span>
#include <string_view>

#include "diagnostics.hpp"
#include "html_plot.hpp"
#include "mission_io.hpp"
#include "offboard_sim.hpp"
#include "trajectory_generator.hpp"

namespace {

void write_to(std::FILE *stream, std::string_view message) {
    std::fwrite(message.data(), sizeof(char), message.size(), stream);
}

void print_segments(
    std::span<const week4::homework::trajectory::SegmentReport> segments) {
    write_to(stdout, "trajectory segments:\n");
    for (const auto &segment : segments) {
        write_to(
            stdout,
            std::format("  {:2d} {:34s} {:5.2f} s, distance {:5.2f} m, samples {}\n",
                        segment.index, segment.name, segment.duration_s,
                        segment.distance_m, segment.sample_count));
    }
}

void print_diagnostics(const week4::homework::diagnostics::DiagnosticReport &report) {
    write_to(stdout, "\ndiagnostics:\n");
    for (const auto &check : report.checks) {
        write_to(stdout, std::format("  {}: {} ({})\n", check.name,
                                     check.passed ? "yes" : "no", check.detail));
    }
    write_to(stdout,
             std::format(
                 "\nsummary:\n"
                 "  RMS position error: {:.4f} m\n"
                 "  RMS yaw error:      {:.4f} rad\n"
                 "  max setpoint vel:   {:.4f} m/s\n"
                 "  max setpoint acc:   {:.4f} m/s^2\n"
                 "  max setpoint jerk:  {:.4f} m/s^3\n"
                 "  max vehicle speed:  {:.4f} m/s\n"
                 "  max tilt proxy:     {:.4f} rad\n"
                 "  result:             {}\n\n"
                 "trajectory written to trajectory.html\n",
                 report.rms_position_error_m, report.rms_yaw_error_rad,
                 report.max_setpoint_speed_mps, report.max_setpoint_acceleration_mps2,
                 report.max_setpoint_jerk_mps3, report.max_vehicle_speed_mps,
                 report.max_tilt_proxy_rad, report.passed ? "passed" : "failed"));
}

} // namespace

int main() {
    using namespace week4::homework;

    try {
        write_to(stdout, "PX4-style raw mission to TrajectorySetpoint pipeline\n\n");

        const auto raw_items =
            mission::read_raw_mission_csv("data/inspection_mission_raw.csv");
        write_to(stdout,
                 std::format("loaded {} raw mission items\n", raw_items.size()));

        const trajectory::TrajectoryConfig trajectory_config{};
        const auto planned = trajectory::build_trajectory(raw_items, trajectory_config);
        write_to(stdout,
                 std::format(
                     "generated {} navigator setpoints and {} trajectory setpoints\n\n",
                     planned.navigator_setpoints.size(), planned.setpoints.size()));
        print_segments(planned.segments);

        const offboard::TrackerConfig tracker_config{};
        const auto simulation = offboard::simulate_tracking(planned, tracker_config);
        const auto report = diagnostics::evaluate(planned, simulation);

        plot::write_html_animation("trajectory.html", planned, simulation, report);
        print_diagnostics(report);
        return report.passed ? EXIT_SUCCESS : EXIT_FAILURE;
    } catch (const std::exception &error) {
        write_to(stderr, std::format("error: {}\n", error.what()));
        return EXIT_FAILURE;
    }
}
