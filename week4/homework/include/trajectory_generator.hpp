#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <format>
#include <span>
#include <stdexcept>
#include <string>
#include <vector>

#include "px4_messages.hpp"

namespace week4::homework::trajectory {

struct TrajectoryConfig {
    double setpoint_rate_hz{50.0};
    double default_cruise_speed_mps{1.2};
    double max_velocity_mps{1.8};
    double max_acceleration_mps2{2.2};
    double max_jerk_mps3{8.0};
    double max_yawspeed_radps{1.0};
    double max_yawaccel_radps2{1.6};
    double min_segment_duration_s{1.0};
};

struct SegmentReport {
    int index{0};
    std::string name;
    double duration_s{0.0};
    double distance_m{0.0};
    double yaw_delta_rad{0.0};
    double cruise_speed_mps{0.0};
    int sample_count{0};
};

struct PlannedTrajectory {
    std::vector<px4::NavigatorSetpoint> navigator_setpoints;
    std::vector<px4::TrajectorySetpoint> setpoints;
    std::vector<SegmentReport> segments;
    double dt{0.02};
};

inline double smoothstep5(double u) {
    return u * u * u * (10.0 + u * (-15.0 + 6.0 * u));
}

inline double smoothstep5_d1(double u) { return 30.0 * u * u * (1.0 - u) * (1.0 - u); }

inline double smoothstep5_d2(double u) {
    return 60.0 * u * (1.0 - u) * (1.0 - 2.0 * u);
}

inline double smoothstep5_d3(double u) { return 60.0 - 360.0 * u + 360.0 * u * u; }

inline double duration_for_limits(double distance, double yaw_delta,
                                  double requested_speed,
                                  const TrajectoryConfig &config) {
    // TODO: return the shortest duration (never below
    // min_segment_duration_s) that keeps a smoothstep5 profile for this
    // segment's translation and yaw within every limit in `config`,
    // honoring the requested cruise speed.
    //
    // Placeholder: a fixed duration, so long segments blow the limits.
    (void)distance;
    (void)yaw_delta;
    (void)requested_speed;
    return config.min_segment_duration_s;
}

inline px4::Vector3 item_position_vector(const px4::RawMissionItem &item) {
    return {item.x, item.y, item.z};
}

inline double heading_to_target(const px4::Vector3 &from, const px4::Vector3 &to,
                                double fallback_yaw) {
    const px4::Vector3 delta = to - from;
    if (delta.head<2>().norm() < 1.0e-6) {
        return fallback_yaw;
    }
    return std::atan2(delta.y(), delta.x());
}

inline std::vector<px4::NavigatorSetpoint>
build_navigator_setpoints(std::span<const px4::RawMissionItem> raw_items,
                          const TrajectoryConfig &config) {
    std::vector<px4::NavigatorSetpoint> result;
    result.reserve(raw_items.size());

    px4::Vector3 current_position = px4::Vector3::Zero();
    double current_yaw = 0.0;
    double current_speed = config.default_cruise_speed_mps;

    for (const auto &item : raw_items) {
        if (px4::is_set(item.cruise_speed_mps)) {
            current_speed = std::min(item.cruise_speed_mps, config.max_velocity_mps);
        }

        if (item.command == px4::MissionCommand::change_speed) {
            continue;
        }

        px4::NavigatorSetpoint setpoint;
        setpoint.seq = item.seq;
        setpoint.command_name = std::string{px4::command_name(item.command)};
        setpoint.acceptance_radius_m =
            px4::is_set(item.acceptance_radius_m) ? item.acceptance_radius_m : 0.3;
        setpoint.hold_s = px4::is_set(item.hold_s) ? item.hold_s : 0.0;
        setpoint.cruise_speed_mps = current_speed;
        setpoint.landing = item.command == px4::MissionCommand::land;

        if (item.command == px4::MissionCommand::loiter_time) {
            setpoint.position_ned = current_position;
        } else if (item.frame == px4::MissionFrame::body_offset_ned) {
            setpoint.position_ned = px4::body_offset_to_local(
                current_position, current_yaw, item_position_vector(item));
        } else {
            setpoint.position_ned = item_position_vector(item);
        }

        if (item.command == px4::MissionCommand::roi_waypoint ||
            item.command == px4::MissionCommand::loiter_time) {
            const px4::Vector3 roi{item.roi_x, item.roi_y, item.roi_z};
            setpoint.yaw_rad = px4::yaw_to_roi(setpoint.position_ned, roi);
            setpoint.roi_controlled_yaw = true;
        } else if (px4::is_set(item.yaw_deg)) {
            setpoint.yaw_rad = px4::degrees_to_radians(item.yaw_deg);
        } else {
            setpoint.yaw_rad = current_yaw;
        }
        setpoint.yaw_rad = px4::unwrap_near(current_yaw, setpoint.yaw_rad);

        current_position = setpoint.position_ned;
        current_yaw = setpoint.yaw_rad;
        result.push_back(setpoint);
    }

    if (result.size() < 2) {
        throw std::runtime_error{"navigator produced fewer than two setpoints"};
    }
    return result;
}

inline void append_motion_segment(PlannedTrajectory &planned,
                                  const px4::NavigatorSetpoint &from,
                                  const px4::NavigatorSetpoint &to, int segment_index,
                                  std::uint64_t &timestamp_us,
                                  const TrajectoryConfig &config) {
    const px4::Vector3 delta = to.position_ned - from.position_ned;
    const double distance = delta.norm();
    const double yaw0 = from.yaw_rad;
    const double segment_heading = px4::unwrap_near(
        yaw0, heading_to_target(from.position_ned, to.position_ned, from.yaw_rad));
    const double yaw1 = px4::unwrap_near(yaw0, to.yaw_rad);
    const double yaw_delta = yaw1 - yaw0;
    const double raw_duration =
        duration_for_limits(distance, yaw_delta, to.cruise_speed_mps, config);
    const int steps =
        std::max(1, static_cast<int>(std::ceil(raw_duration / planned.dt)));
    const double duration = steps * planned.dt;

    SegmentReport report{
        .index = segment_index,
        .name = std::format("{} -> {}", from.command_name, to.command_name),
        .duration_s = duration,
        .distance_m = distance,
        .yaw_delta_rad = yaw_delta,
        .cruise_speed_mps = to.cruise_speed_mps,
        .sample_count = steps,
    };

    for (int i = 1; i <= steps; ++i) {
        [[maybe_unused]] const double u =
            static_cast<double>(i) / static_cast<double>(steps);

        px4::TrajectorySetpoint sample;
        sample.timestamp = timestamp_us;
        // TODO: fill position, velocity, acceleration, jerk, yaw, and
        // yawspeed from a smoothstep5 profile sampled at u.
        //
        // Placeholder: park at the segment start with zero derivatives.
        sample.position = from.position_ned;
        sample.velocity = px4::Vector3::Zero();
        sample.acceleration = px4::Vector3::Zero();
        sample.jerk = px4::Vector3::Zero();
        sample.yaw = yaw0;
        sample.yawspeed = 0.0;
        sample.target_yaw = segment_heading;
        sample.segment_index = segment_index;
        sample.segment_name = report.name;
        planned.setpoints.push_back(std::move(sample));
        timestamp_us += static_cast<std::uint64_t>(planned.dt * 1.0e6);
    }

    planned.segments.push_back(std::move(report));
}

inline void append_hold_segment(PlannedTrajectory &planned,
                                const px4::NavigatorSetpoint &setpoint,
                                int segment_index, std::uint64_t &timestamp_us) {
    if (setpoint.hold_s <= 0.0) {
        return;
    }
    const int steps =
        std::max(1, static_cast<int>(std::ceil(setpoint.hold_s / planned.dt)));
    const double duration = steps * planned.dt;
    SegmentReport report{
        .index = segment_index,
        .name = std::format("{} hold", setpoint.command_name),
        .duration_s = duration,
        .distance_m = 0.0,
        .yaw_delta_rad = 0.0,
        .cruise_speed_mps = 0.0,
        .sample_count = steps,
    };

    for (int i = 0; i < steps; ++i) {
        px4::TrajectorySetpoint sample;
        sample.timestamp = timestamp_us;
        sample.position = setpoint.position_ned;
        sample.velocity = px4::Vector3::Zero();
        sample.acceleration = px4::Vector3::Zero();
        sample.jerk = px4::Vector3::Zero();
        sample.yaw = setpoint.yaw_rad;
        sample.target_yaw = setpoint.yaw_rad;
        sample.yawspeed = 0.0;
        sample.segment_index = segment_index;
        sample.segment_name = report.name;
        planned.setpoints.push_back(std::move(sample));
        timestamp_us += static_cast<std::uint64_t>(planned.dt * 1.0e6);
    }
    planned.segments.push_back(std::move(report));
}

inline PlannedTrajectory
build_trajectory(std::span<const px4::RawMissionItem> raw_items,
                 const TrajectoryConfig &config = {}) {
    PlannedTrajectory planned;
    planned.dt = 1.0 / config.setpoint_rate_hz;
    planned.navigator_setpoints = build_navigator_setpoints(raw_items, config);
    for (std::size_t i = 1; i < planned.navigator_setpoints.size(); ++i) {
        auto &current = planned.navigator_setpoints[i];
        const auto &previous = planned.navigator_setpoints[i - 1];
        current.yaw_rad = px4::unwrap_near(previous.yaw_rad, current.yaw_rad);
    }

    std::uint64_t timestamp_us = 0;
    const auto &first = planned.navigator_setpoints.front();
    px4::TrajectorySetpoint initial;
    initial.timestamp = timestamp_us;
    initial.position =
        px4::Vector3{first.position_ned.x(), first.position_ned.y(), 0.0};
    initial.velocity = px4::Vector3::Zero();
    initial.acceleration = px4::Vector3::Zero();
    initial.jerk = px4::Vector3::Zero();
    initial.yaw = first.yaw_rad;
    initial.target_yaw = first.yaw_rad;
    initial.yawspeed = 0.0;
    initial.segment_index = 0;
    initial.segment_name = "initial ground state";
    planned.setpoints.push_back(initial);
    timestamp_us += static_cast<std::uint64_t>(planned.dt * 1.0e6);

    px4::NavigatorSetpoint previous = first;
    previous.position_ned = initial.position;
    previous.command_name = "GROUND";
    int segment_index = 0;
    for (const auto &target : planned.navigator_setpoints) {
        append_motion_segment(planned, previous, target, ++segment_index, timestamp_us,
                              config);
        if (target.hold_s > 0.0) {
            append_hold_segment(planned, target, ++segment_index, timestamp_us);
        }
        previous = target;
    }
    return planned;
}

} // namespace week4::homework::trajectory
