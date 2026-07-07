#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>

#include "px4_messages.hpp"
#include "trajectory_generator.hpp"

namespace week4::homework::offboard {

struct TrackerConfig {
    double position_gain{7.0};
    double velocity_gain{4.2};
    double yaw_gain{7.0};
    double yawspeed_gain{3.5};
    double max_vehicle_speed_mps{3.0};
    double max_vehicle_acceleration_mps2{5.5};
    double max_yawaccel_radps2{4.0};
    double offboard_loss_timeout_s{0.5};
};

struct TrackingError {
    px4::Vector3 position{px4::Vector3::Zero()};
    px4::Vector3 velocity{px4::Vector3::Zero()};
    double position_norm{0.0};
    double yaw_rad{0.0};
};

struct SimulationSample {
    double time_s{0.0};
    px4::TrajectorySetpoint setpoint{};
    px4::OffboardControlMode offboard_control_mode{};
    px4::VehicleState vehicle{};
    TrackingError error{};
    double commanded_accel_norm{0.0};
    double tilt_proxy_rad{0.0};
};

struct SimulationResult {
    std::vector<SimulationSample> samples;
    bool offboard_timeout{false};
    double final_position_error_m{0.0};
    double final_yaw_error_rad{0.0};
};

inline void clamp_norm(px4::Vector3 &value, double max_norm) {
    const double norm = value.norm();
    if (norm > max_norm) {
        value *= max_norm / norm;
    }
}

inline double clamp_abs(double value, double max_abs) {
    return std::clamp(value, -max_abs, max_abs);
}

inline TrackingError make_error(const px4::VehicleState &vehicle,
                                const px4::TrajectorySetpoint &setpoint) {
    TrackingError error;
    error.position = setpoint.position - vehicle.local_position.position;
    error.velocity = setpoint.velocity - vehicle.local_position.velocity;
    error.position_norm = error.position.norm();
    error.yaw_rad = px4::wrap_pi(setpoint.yaw - vehicle.attitude.yaw);
    return error;
}

inline SimulationResult simulate_tracking(const trajectory::PlannedTrajectory &planned,
                                          const TrackerConfig &config = {}) {
    SimulationResult result;
    if (planned.setpoints.empty()) {
        return result;
    }
    result.samples.reserve(planned.setpoints.size());

    px4::VehicleState vehicle;
    vehicle.local_position.timestamp = planned.setpoints.front().timestamp;
    vehicle.local_position.position = planned.setpoints.front().position;
    vehicle.local_position.velocity = px4::Vector3::Zero();
    vehicle.local_position.acceleration = px4::Vector3::Zero();
    vehicle.attitude.timestamp = planned.setpoints.front().timestamp;
    vehicle.attitude.yaw = planned.setpoints.front().yaw;
    vehicle.attitude.yawspeed = 0.0;

    std::uint64_t previous_heartbeat = planned.setpoints.front().timestamp;

    for (std::size_t i = 0; i < planned.setpoints.size(); ++i) {
        const auto &setpoint = planned.setpoints[i];
        px4::OffboardControlMode mode;
        mode.timestamp = setpoint.timestamp;
        mode.position = px4::vector_is_finite(setpoint.position);
        mode.velocity = px4::vector_is_finite(setpoint.velocity);
        mode.acceleration = px4::vector_is_finite(setpoint.acceleration);

        const double heartbeat_gap_s =
            static_cast<double>(mode.timestamp - previous_heartbeat) * 1.0e-6;
        if (heartbeat_gap_s > config.offboard_loss_timeout_s) {
            result.offboard_timeout = true;
            vehicle.failsafe = true;
        }
        previous_heartbeat = mode.timestamp;

        const TrackingError error = make_error(vehicle, setpoint);

        // TODO: the tracking law. Compute the acceleration command that
        // tracks `setpoint`, and the yaw acceleration command that tracks
        // its yaw, respecting the limits in `config` (whose gains are tuned
        // for a correct implementation).
        //
        // Placeholder: no control, so the vehicle never moves.
        px4::Vector3 accel_command = px4::Vector3::Zero();
        const double yawaccel_command = 0.0;

        const double time_s = static_cast<double>(setpoint.timestamp) * 1.0e-6;
        result.samples.push_back({
            .time_s = time_s,
            .setpoint = setpoint,
            .offboard_control_mode = mode,
            .vehicle = vehicle,
            .error = error,
            .commanded_accel_norm = accel_command.norm(),
            .tilt_proxy_rad = std::atan2(accel_command.head<2>().norm(), px4::kGravity),
        });

        if (i + 1 < planned.setpoints.size()) {
            const double dt = static_cast<double>(planned.setpoints[i + 1].timestamp -
                                                  setpoint.timestamp) *
                              1.0e-6;
            vehicle.local_position.acceleration = accel_command;
            vehicle.local_position.velocity += accel_command * dt;
            clamp_norm(vehicle.local_position.velocity, config.max_vehicle_speed_mps);
            vehicle.local_position.position +=
                vehicle.local_position.velocity * dt + 0.5 * accel_command * dt * dt;
            vehicle.local_position.timestamp = planned.setpoints[i + 1].timestamp;

            vehicle.attitude.yawspeed += yawaccel_command * dt;
            vehicle.attitude.yawspeed = clamp_abs(vehicle.attitude.yawspeed, 1.5);
            vehicle.attitude.yaw =
                px4::wrap_pi(vehicle.attitude.yaw + vehicle.attitude.yawspeed * dt +
                             0.5 * yawaccel_command * dt * dt);
            vehicle.attitude.timestamp = planned.setpoints[i + 1].timestamp;
        }
    }

    const auto final_error = make_error(vehicle, planned.setpoints.back());
    result.final_position_error_m = final_error.position_norm;
    result.final_yaw_error_rad = std::abs(final_error.yaw_rad);
    return result;
}

} // namespace week4::homework::offboard
