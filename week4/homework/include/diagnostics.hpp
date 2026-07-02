#pragma once

#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <format>
#include <ranges>
#include <string>
#include <vector>

#include "offboard_sim.hpp"
#include "px4_messages.hpp"
#include "trajectory_generator.hpp"

namespace week4::homework::diagnostics {

struct DiagnosticConfig {
    double expected_rate_hz{50.0};
    double final_position_tolerance_m{0.03};
    double final_yaw_tolerance_rad{0.05};
    double rms_position_tolerance_m{0.03};
    double rms_yaw_tolerance_rad{0.05};
    double max_velocity_mps{1.80};
    double max_acceleration_mps2{2.20};
    double max_jerk_mps3{8.00};
    double max_yawspeed_radps{1.05};
    double max_commanded_acceleration_mps2{3.0};
    double min_nonlanding_altitude_m{0.45};
    double max_tilt_proxy_rad{0.35};
    double north_min{-1.0};
    double north_max{16.0};
    double east_min{-1.0};
    double east_max{10.0};
};

struct DiagnosticCheck {
    std::string name;
    bool passed{false};
    std::string detail;
};

struct DiagnosticReport {
    std::vector<DiagnosticCheck> checks;
    double rms_position_error_m{0.0};
    double rms_yaw_error_rad{0.0};
    double max_setpoint_speed_mps{0.0};
    double max_setpoint_acceleration_mps2{0.0};
    double max_setpoint_jerk_mps3{0.0};
    double max_setpoint_yawspeed_radps{0.0};
    double max_commanded_acceleration_mps2{0.0};
    double max_vehicle_speed_mps{0.0};
    double max_tilt_proxy_rad{0.0};
    bool passed{false};
};

inline bool is_landing_segment(const std::string &name) {
    return name.find("LAND") != std::string::npos;
}

inline bool is_takeoff_segment(const std::string &name) {
    return name.find("TAKEOFF") != std::string::npos;
}

inline DiagnosticReport evaluate(const trajectory::PlannedTrajectory &planned,
                                 const offboard::SimulationResult &simulation,
                                 const DiagnosticConfig &config = {}) {
    DiagnosticReport report;
    const auto add_check = [&](std::string name, bool passed, std::string detail) {
        report.checks.push_back({std::move(name), passed, std::move(detail)});
    };

    const auto &setpoints = planned.setpoints;
    const auto &samples = simulation.samples;
    if (setpoints.empty() || samples.empty()) {
        add_check("trajectory contains samples", false, "empty trajectory");
        report.passed = false;
        return report;
    }

    bool monotonic = true;
    bool fixed_rate = true;
    bool setpoints_finite = true;
    const std::uint64_t expected_dt_us =
        static_cast<std::uint64_t>((1.0 / config.expected_rate_hz) * 1.0e6);
    for (std::size_t i = 0; i < setpoints.size(); ++i) {
        const auto &sp = setpoints[i];
        setpoints_finite &=
            px4::vector_is_finite(sp.position) && px4::vector_is_finite(sp.velocity) &&
            px4::vector_is_finite(sp.acceleration) && px4::vector_is_finite(sp.jerk) &&
            std::isfinite(sp.yaw) && std::isfinite(sp.yawspeed);
        if (i == 0) {
            continue;
        }
        const auto dt = sp.timestamp - setpoints[i - 1].timestamp;
        monotonic &= sp.timestamp > setpoints[i - 1].timestamp;
        fixed_rate &= std::llabs(static_cast<long long>(dt) -
                                 static_cast<long long>(expected_dt_us)) <= 1;
    }
    add_check("TrajectorySetpoint timestamps monotonic", monotonic,
              std::format("{} setpoints", setpoints.size()));
    add_check("TrajectorySetpoint stream rate fixed", fixed_rate,
              std::format("{:.1f} Hz", config.expected_rate_hz));
    add_check("TrajectorySetpoint values finite", setpoints_finite,
              setpoints_finite ? "no NaN/Inf" : "NaN or Inf detected");

    bool geofence_ok = true;
    bool altitude_ok = true;
    bool vehicle_state_finite = true;
    double sum_position_error2 = 0.0;
    double sum_yaw_error2 = 0.0;
    for (const auto &sample : samples) {
        const auto &sp = sample.setpoint;
        report.max_setpoint_speed_mps =
            std::max(report.max_setpoint_speed_mps, sp.velocity.norm());
        report.max_setpoint_acceleration_mps2 =
            std::max(report.max_setpoint_acceleration_mps2, sp.acceleration.norm());
        report.max_setpoint_jerk_mps3 =
            std::max(report.max_setpoint_jerk_mps3, sp.jerk.norm());
        report.max_setpoint_yawspeed_radps =
            std::max(report.max_setpoint_yawspeed_radps, std::abs(sp.yawspeed));
        report.max_commanded_acceleration_mps2 = std::max(
            report.max_commanded_acceleration_mps2, sample.commanded_accel_norm);
        report.max_vehicle_speed_mps =
            std::max(report.max_vehicle_speed_mps,
                     sample.vehicle.local_position.velocity.norm());
        report.max_tilt_proxy_rad =
            std::max(report.max_tilt_proxy_rad, sample.tilt_proxy_rad);

        const auto &position = sample.vehicle.local_position.position;
        vehicle_state_finite &=
            px4::vector_is_finite(sample.vehicle.local_position.position) &&
            px4::vector_is_finite(sample.vehicle.local_position.velocity) &&
            std::isfinite(sample.vehicle.attitude.yaw);
        geofence_ok &=
            position.x() >= config.north_min && position.x() <= config.north_max &&
            position.y() >= config.east_min && position.y() <= config.east_max;
        if (sample.time_s > 0.4 && !is_landing_segment(sp.segment_name) &&
            !is_takeoff_segment(sp.segment_name)) {
            altitude_ok &= -position.z() >= config.min_nonlanding_altitude_m;
        }
        sum_position_error2 += sample.error.position_norm * sample.error.position_norm;
        sum_yaw_error2 += sample.error.yaw_rad * sample.error.yaw_rad;
    }

    report.rms_position_error_m =
        std::sqrt(sum_position_error2 / static_cast<double>(samples.size()));
    report.rms_yaw_error_rad =
        std::sqrt(sum_yaw_error2 / static_cast<double>(samples.size()));

    add_check("setpoint velocity within PX4-style limit",
              report.max_setpoint_speed_mps <= config.max_velocity_mps,
              std::format("max {:.3f} m/s", report.max_setpoint_speed_mps));
    add_check("setpoint acceleration within PX4-style limit",
              report.max_setpoint_acceleration_mps2 <= config.max_acceleration_mps2,
              std::format("max {:.3f} m/s^2", report.max_setpoint_acceleration_mps2));
    add_check("setpoint jerk within PX4-style limit",
              report.max_setpoint_jerk_mps3 <= config.max_jerk_mps3,
              std::format("max {:.3f} m/s^3", report.max_setpoint_jerk_mps3));
    add_check("setpoint yawspeed within PX4-style limit",
              report.max_setpoint_yawspeed_radps <= config.max_yawspeed_radps,
              std::format("max {:.3f} rad/s", report.max_setpoint_yawspeed_radps));
    add_check("tracker commanded acceleration within limit",
              report.max_commanded_acceleration_mps2 <=
                  config.max_commanded_acceleration_mps2,
              std::format("max {:.3f} m/s^2", report.max_commanded_acceleration_mps2));
    add_check("RMS position tracking error",
              report.rms_position_error_m <= config.rms_position_tolerance_m,
              std::format("{:.4f} m", report.rms_position_error_m));
    add_check("RMS yaw tracking error",
              report.rms_yaw_error_rad <= config.rms_yaw_tolerance_rad,
              std::format("{:.4f} rad", report.rms_yaw_error_rad));
    add_check("final landing position error",
              simulation.final_position_error_m <= config.final_position_tolerance_m,
              std::format("{:.4f} m", simulation.final_position_error_m));
    add_check("final landing yaw error",
              simulation.final_yaw_error_rad <= config.final_yaw_tolerance_rad,
              std::format("{:.4f} rad", simulation.final_yaw_error_rad));
    add_check("no offboard heartbeat timeout", !simulation.offboard_timeout,
              simulation.offboard_timeout ? "timeout observed" : "continuous");
    add_check("vehicle state values finite", vehicle_state_finite,
              vehicle_state_finite ? "no NaN/Inf" : "NaN or Inf detected");
    add_check("no geofence violation", geofence_ok,
              std::format("N [{:.1f},{:.1f}], E [{:.1f},{:.1f}]", config.north_min,
                          config.north_max, config.east_min, config.east_max));
    add_check("no altitude-floor violation before LAND", altitude_ok,
              std::format("floor {:.2f} m", config.min_nonlanding_altitude_m));
    add_check("tilt proxy remains feasible",
              report.max_tilt_proxy_rad <= config.max_tilt_proxy_rad,
              std::format("max {:.3f} rad", report.max_tilt_proxy_rad));

    report.passed = std::ranges::all_of(report.checks,
                                        [](const auto &check) { return check.passed; });
    return report;
}

} // namespace week4::homework::diagnostics
