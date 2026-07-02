#pragma once

#include <Eigen/Core>

#include <cmath>
#include <cstdint>
#include <limits>
#include <numbers>
#include <string>
#include <string_view>

namespace week4::homework::px4 {

using Vector3 = Eigen::Vector3d;

inline constexpr double kNaN = std::numeric_limits<double>::quiet_NaN();
inline constexpr double kGravity = 9.80665;

enum class MissionCommand {
    takeoff,
    waypoint,
    roi_waypoint,
    change_speed,
    loiter_time,
    land,
};

enum class MissionFrame {
    local_ned,
    body_offset_ned,
};

struct RawMissionItem {
    int seq{0};
    std::uint64_t timestamp_us{0};
    MissionCommand command{MissionCommand::waypoint};
    MissionFrame frame{MissionFrame::local_ned};
    double x{kNaN};
    double y{kNaN};
    double z{kNaN};
    double yaw_deg{kNaN};
    double acceptance_radius_m{kNaN};
    double hold_s{0.0};
    double cruise_speed_mps{kNaN};
    double loiter_radius_m{kNaN};
    double roi_x{kNaN};
    double roi_y{kNaN};
    double roi_z{kNaN};
};

struct NavigatorSetpoint {
    int seq{0};
    std::string command_name;
    Vector3 position_ned{Vector3::Zero()};
    double yaw_rad{0.0};
    double acceptance_radius_m{0.3};
    double hold_s{0.0};
    double cruise_speed_mps{1.0};
    bool landing{false};
    bool roi_controlled_yaw{false};
};

struct TrajectorySetpoint {
    std::uint64_t timestamp{0};
    Vector3 position{Vector3::Constant(kNaN)};
    Vector3 velocity{Vector3::Constant(kNaN)};
    Vector3 acceleration{Vector3::Constant(kNaN)};
    Vector3 jerk{Vector3::Constant(kNaN)};
    double yaw{kNaN};
    double target_yaw{kNaN};
    double yawspeed{kNaN};
    int segment_index{0};
    std::string segment_name;
};

struct OffboardControlMode {
    std::uint64_t timestamp{0};
    bool position{true};
    bool velocity{true};
    bool acceleration{true};
    bool attitude{false};
    bool body_rate{false};
    bool thrust_and_torque{false};
    bool direct_actuator{false};
};

struct VehicleLocalPosition {
    std::uint64_t timestamp{0};
    Vector3 position{Vector3::Zero()};
    Vector3 velocity{Vector3::Zero()};
    Vector3 acceleration{Vector3::Zero()};
};

struct VehicleAttitude {
    std::uint64_t timestamp{0};
    double yaw{0.0};
    double yawspeed{0.0};
};

struct VehicleState {
    VehicleLocalPosition local_position{};
    VehicleAttitude attitude{};
    bool failsafe{false};
};

inline bool is_set(double value) { return std::isfinite(value); }

inline bool vector_is_finite(const Vector3 &value) { return value.allFinite(); }

inline double degrees_to_radians(double degrees) {
    return degrees * std::numbers::pi / 180.0;
}

inline double radians_to_degrees(double radians) {
    return radians * 180.0 / std::numbers::pi;
}

inline double wrap_pi(double angle) {
    while (angle > std::numbers::pi) {
        angle -= 2.0 * std::numbers::pi;
    }
    while (angle < -std::numbers::pi) {
        angle += 2.0 * std::numbers::pi;
    }
    return angle;
}

inline double unwrap_near(double reference, double value) {
    return reference + wrap_pi(value - reference);
}

inline std::string_view command_name(MissionCommand command) {
    switch (command) {
    case MissionCommand::takeoff:
        return "TAKEOFF";
    case MissionCommand::waypoint:
        return "WAYPOINT";
    case MissionCommand::roi_waypoint:
        return "ROI_WAYPOINT";
    case MissionCommand::change_speed:
        return "CHANGE_SPEED";
    case MissionCommand::loiter_time:
        return "LOITER_TIME";
    case MissionCommand::land:
        return "LAND";
    }
    return "UNKNOWN";
}

inline std::string_view frame_name(MissionFrame frame) {
    switch (frame) {
    case MissionFrame::local_ned:
        return "LOCAL_NED";
    case MissionFrame::body_offset_ned:
        return "BODY_OFFSET_NED";
    }
    return "UNKNOWN";
}

inline double yaw_to_roi(const Vector3 &position, const Vector3 &roi) {
    const Vector3 delta = roi - position;
    return std::atan2(delta.y(), delta.x());
}

inline Vector3 body_offset_to_local(const Vector3 &origin, double yaw,
                                    const Vector3 &offset_body_ned) {
    const double c = std::cos(yaw);
    const double s = std::sin(yaw);
    return origin + Vector3{c * offset_body_ned.x() - s * offset_body_ned.y(),
                            s * offset_body_ned.x() + c * offset_body_ned.y(),
                            offset_body_ned.z()};
}

} // namespace week4::homework::px4
