#pragma once

#include <Eigen/Core>
#include <Eigen/Geometry>
#include <sophus/se3.hpp>

#include <array>
#include <cmath>
#include <concepts>
#include <numbers>
#include <ranges>
#include <string_view>
#include <vector>

namespace week4::control
{

using Pose = Sophus::SE3d;
using Vector3 = Eigen::Vector3d;
using Vector6 = Sophus::SE3d::Tangent;

struct Waypoint
{
    std::string_view name;
    Pose world_T_goal;
};

struct ControllerConfig
{
    double dt{0.02};
    double kp_translation{1.4};
    double kp_rotation{1.8};
    double max_translation_speed{1.2};
    double max_rotation_speed{1.3};
    double translation_tolerance{0.035};
    double rotation_tolerance{0.035};
    int max_steps_per_waypoint{900};
};

struct ErrorSummary
{
    Vector6 tangent{Vector6::Zero()};
    double translation_norm{0.0};
    double rotation_norm{0.0};
};

struct TrajectorySample
{
    double time{0.0};
    Vector3 position{Vector3::Zero()};
    Vector3 goal{Vector3::Zero()};
    Eigen::Quaterniond orientation{Eigen::Quaterniond::Identity()};
    ErrorSummary error{};
};

struct SimulationStats
{
    int waypoint_index{0};
    int steps{0};
    double elapsed_time{0.0};
    ErrorSummary final_error{};
    bool converged{false};
};

template <class Observer>
concept SampleObserver = requires(Observer observer, const TrajectorySample& sample) {
    { observer(sample) } -> std::same_as<void>;
};

inline double degrees_to_radians(double degrees) {
    return degrees * std::numbers::pi / 180.0;
}

inline Pose make_pose(double x, double y, double z, double roll_deg,
                      double pitch_deg, double yaw_deg) {
    const Eigen::AngleAxisd roll{degrees_to_radians(roll_deg),
                                 Vector3::UnitX()};
    const Eigen::AngleAxisd pitch{degrees_to_radians(pitch_deg),
                                  Vector3::UnitY()};
    const Eigen::AngleAxisd yaw{degrees_to_radians(yaw_deg), Vector3::UnitZ()};
    const Eigen::Quaterniond world_R_goal{yaw * pitch * roll};
    return Pose{world_R_goal.normalized(), Vector3{x, y, z}};
}

inline std::array<Waypoint, 6> make_closed_route() {
    return {{
        {"takeoff", make_pose(0.0, 0.0, 1.0, 0.0, 0.0, 0.0)},
        {"east gate", make_pose(2.0, 0.0, 1.4, 4.0, -2.0, 25.0)},
        {"north corner", make_pose(2.0, 1.6, 1.8, 0.0, 8.0, 90.0)},
        {"west scan", make_pose(0.0, 1.6, 1.2, -6.0, 0.0, 175.0)},
        {"south return", make_pose(-0.4, 0.3, 1.5, 5.0, -5.0, -120.0)},
        {"landed loop", make_pose(0.0, 0.0, 1.0, 0.0, 0.0, 0.0)},
    }};
}

inline void clamp_norm(Vector3& value, double max_norm) {
    const double norm = value.norm();
    if (norm > max_norm) {
        value *= max_norm / norm;
    }
}

inline ErrorSummary pose_error(const Pose& world_T_body,
                               const Pose& world_T_goal) {
    const Pose body_T_goal = world_T_body.inverse() * world_T_goal;
    const Vector6 tangent = body_T_goal.log();
    return {
        .tangent = tangent,
        .translation_norm = tangent.head<3>().norm(),
        .rotation_norm = tangent.tail<3>().norm(),
    };
}

inline Vector6 control_twist(const ErrorSummary& error,
                             const ControllerConfig& config) {
    Vector3 translation = config.kp_translation * error.tangent.head<3>();
    Vector3 rotation = config.kp_rotation * error.tangent.tail<3>();
    clamp_norm(translation, config.max_translation_speed);
    clamp_norm(rotation, config.max_rotation_speed);

    Vector6 twist = Vector6::Zero();
    twist.head<3>() = translation;
    twist.tail<3>() = rotation;
    return twist;
}

inline bool reached_goal(const ErrorSummary& error,
                         const ControllerConfig& config) {
    return error.translation_norm < config.translation_tolerance &&
           error.rotation_norm < config.rotation_tolerance;
}

inline TrajectorySample make_sample(double time, const Pose& world_T_body,
                                    const Pose& world_T_goal,
                                    const ErrorSummary& error) {
    return {
        .time = time,
        .position = world_T_body.translation(),
        .goal = world_T_goal.translation(),
        .orientation = world_T_body.unit_quaternion(),
        .error = error,
    };
}

template <SampleObserver Observer>
SimulationStats fly_to_waypoint(Pose& world_T_body, const Waypoint& waypoint,
                                int waypoint_index, double& simulation_time,
                                const ControllerConfig& config,
                                Observer&& observe) {
    for (int step = 0; step < config.max_steps_per_waypoint; ++step) {
        const auto error = pose_error(world_T_body, waypoint.world_T_goal);
        observe(make_sample(simulation_time, world_T_body,
                            waypoint.world_T_goal, error));

        if (reached_goal(error, config)) {
            return {
                .waypoint_index = waypoint_index,
                .steps = step,
                .elapsed_time = step * config.dt,
                .final_error = error,
                .converged = true,
            };
        }

        const auto body_twist = control_twist(error, config);
        world_T_body = world_T_body * Pose::exp(body_twist * config.dt);
        simulation_time += config.dt;
    }

    const auto error = pose_error(world_T_body, waypoint.world_T_goal);
    observe(make_sample(simulation_time, world_T_body, waypoint.world_T_goal,
                        error));
    return {
        .waypoint_index = waypoint_index,
        .steps = config.max_steps_per_waypoint,
        .elapsed_time = config.max_steps_per_waypoint * config.dt,
        .final_error = error,
        .converged = false,
    };
}

template <std::ranges::forward_range Route, SampleObserver Observer>
    requires std::same_as<std::ranges::range_value_t<Route>, Waypoint>
std::vector<SimulationStats> fly_route(Pose& world_T_body, const Route& route,
                                       const ControllerConfig& config,
                                       Observer&& observe,
                                       double& simulation_time) {
    std::vector<SimulationStats> all_stats;
    all_stats.reserve(std::ranges::size(route) - 1);

    int waypoint_index = 1;
    for (const auto& waypoint : route | std::views::drop(1)) {
        auto stats = fly_to_waypoint(world_T_body, waypoint, waypoint_index,
                                     simulation_time, config, observe);
        all_stats.push_back(stats);
        if (!stats.converged) {
            break;
        }
        ++waypoint_index;
    }
    return all_stats;
}

}  // namespace week4::control
