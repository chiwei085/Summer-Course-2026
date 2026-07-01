#pragma once

#include <Eigen/Core>
#include <Eigen/Geometry>
#include <sophus/se3.hpp>
#include <sophus/so3.hpp>

#include <array>
#include <cmath>
#include <concepts>
#include <numbers>
#include <string_view>

namespace week4::advanced::arm
{

using Pose = Sophus::SE3d;
using Vector3 = Eigen::Vector3d;
using Vector6 = Sophus::SE3d::Tangent;
using JointVector = Eigen::Matrix<double, 6, 1>;
using Jacobian = Eigen::Matrix<double, 6, 6>;

constexpr int kJointCount = 6;
constexpr int kJointFrameCount = kJointCount + 2;
constexpr int kVisualLinkCount = 7;
constexpr double kCubeHalfExtent = 0.04;

enum class JointRole
{
    base,
    shoulder,
    elbow,
    wrist1,
    wrist2,
    wrist3,
    flange,
    tool,
};

enum class LinkRole
{
    pedestal,
    upper_arm,
    forearm,
    wrist_stack,
    flange,
    gripper_palm,
};

struct JointFrame
{
    JointRole role{JointRole::base};
    Pose pose{};
};

struct VisualLink
{
    LinkRole role{LinkRole::upper_arm};
    Vector3 start{Vector3::Zero()};
    Vector3 end{Vector3::Zero()};
    double radius{0.025};
};

struct GripperGeometry
{
    double palm_length{0.050};
    double finger_length{0.065};
    double finger_offset{0.025};
    double open_jaw_width{0.085};
    double closed_jaw_width{0.055};
};

inline constexpr std::array<JointRole, kJointFrameCount> kJointRoles{{
    JointRole::base,
    JointRole::shoulder,
    JointRole::elbow,
    JointRole::wrist1,
    JointRole::wrist2,
    JointRole::wrist3,
    JointRole::flange,
    JointRole::tool,
}};

struct JointLimit
{
    double lower{0.0};
    double upper{0.0};
};

struct RobotModel
{
    std::array<double, kJointCount> a{{
        0.0,
        -0.320,
        -0.235,
        0.0,
        0.0,
        0.0,
    }};
    std::array<double, kJointCount> d{{
        0.089,
        0.0,
        0.0,
        0.078,
        0.068,
        0.058,
    }};
    std::array<double, kJointCount> alpha{{
        std::numbers::pi / 2.0,
        0.0,
        0.0,
        std::numbers::pi / 2.0,
        -std::numbers::pi / 2.0,
        0.0,
    }};
    std::array<double, kJointCount> theta_offset{{
        0.0,
        -std::numbers::pi / 2.0,
        0.0,
        -std::numbers::pi / 2.0,
        0.0,
        0.0,
    }};
    std::array<JointLimit, kJointCount> limits{{
        {-2.0 * std::numbers::pi, 2.0 * std::numbers::pi},
        {-2.0 * std::numbers::pi, 2.0 * std::numbers::pi},
        {-2.0 * std::numbers::pi, 2.0 * std::numbers::pi},
        {-2.0 * std::numbers::pi, 2.0 * std::numbers::pi},
        {-2.0 * std::numbers::pi, 2.0 * std::numbers::pi},
        {-2.0 * std::numbers::pi, 2.0 * std::numbers::pi},
    }};
    double max_joint_speed{1.35};
    Pose world_T_base{Eigen::Quaterniond::Identity(), Vector3{0.0, 0.0, 0.0}};
    Pose flange_T_tool{Eigen::Quaterniond::Identity(),
                       Vector3{0.0, 0.0, 0.060}};
    GripperGeometry gripper{};
};

struct Kinematics
{
    Pose world_T_flange{};
    Pose world_T_tool{};
    std::array<JointFrame, kJointFrameCount> joint_frames{};
    std::array<VisualLink, kVisualLinkCount> visual_links{};
    std::array<Vector3, kJointCount> joint_origins{};
    std::array<Vector3, kJointCount> joint_axes{};
};

struct Stage
{
    std::string_view name;
    Pose world_T_target{};
    JointVector posture_hint{JointVector::Zero()};
    double translation_tolerance{0.0};
    bool closes_gripper{false};
    bool releases_cube{false};
};

struct ControllerConfig
{
    double dt{0.025};
    double damping{0.10};
    double kp_translation{1.25};
    double kp_rotation{1.05};
    double posture_gain{0.06};
    double translation_tolerance{0.040};
    double rotation_tolerance{0.040};
    int max_steps_per_stage{1200};

    // Manipulability floor (smallest Jacobian singular value, m or rad per
    // joint-rad) below which the DLS damping ramps up; see adaptive_damping().
    double singular_floor{0.06};
    // Weight of the joint-limit avoidance term folded into the same
    // nullspace-ish secondary objective as the posture hint.
    double limit_avoidance_gain{0.35};
    // Per-step joint acceleration cap used to rate-limit the commanded
    // velocity, so a stage's target jump does not appear as a velocity step.
    double max_joint_acceleration{6.0};
};

struct ErrorSummary
{
    Vector6 tangent{Vector6::Zero()};
    double translation_norm{0.0};
    double rotation_norm{0.0};
};

struct Scene
{
    Vector3 source_cube{0.34, -0.16, kCubeHalfExtent};
    Vector3 destination_cube{0.31, 0.18, kCubeHalfExtent};
    double approach_clearance{0.12};
    double transfer_clearance{0.17};
};

struct CubeState
{
    Pose world_T_cube{Eigen::Quaterniond::Identity(), Vector3::Zero()};
    Pose tool_T_cube{Eigen::Quaterniond::Identity(), Vector3::Zero()};
    bool grasped{false};
};

struct TrajectorySample
{
    double time{0.0};
    int stage_index{0};
    std::string_view stage_name;
    JointVector joints{JointVector::Zero()};
    std::array<JointFrame, kJointFrameCount> joint_frames{};
    std::array<VisualLink, kVisualLinkCount> visual_links{};
    Pose tool_pose{};
    GripperGeometry gripper_geometry{};
    Pose cube_pose{};
    Vector3 target{Vector3::Zero()};
    Vector3 source_pad{Vector3::Zero()};
    Vector3 destination_pad{Vector3::Zero()};
    bool gripper_closed{false};
    bool joint_limit_warning{false};
    bool singularity_warning{false};
    ErrorSummary error{};
};

struct SimulationStats
{
    int stage_index{0};
    std::string_view stage_name;
    int steps{0};
    double elapsed_time{0.0};
    ErrorSummary final_error{};
    bool converged{false};
};

template <class Observer>
concept SampleObserver =
    requires(Observer observer, const TrajectorySample& sample) {
        { observer(sample) } -> std::same_as<void>;
    };

inline double degrees_to_radians(double degrees) {
    return degrees * std::numbers::pi / 180.0;
}

inline JointVector make_joints(double q0, double q1, double q2, double q3,
                               double q4, double q5) {
    JointVector joints;
    joints << degrees_to_radians(q0), degrees_to_radians(q1),
        degrees_to_radians(q2), degrees_to_radians(q3), degrees_to_radians(q4),
        degrees_to_radians(q5);
    return joints;
}

inline Pose make_translation(const Vector3& translation) {
    return Pose{Eigen::Quaterniond::Identity(), translation};
}

inline Pose make_dh_transform(double theta, double d, double a, double alpha) {
    const double ct = std::cos(theta);
    const double st = std::sin(theta);
    const double ca = std::cos(alpha);
    const double sa = std::sin(alpha);

    Eigen::Matrix3d rotation;
    rotation << ct, -st * ca, st * sa, st, ct * ca, -ct * sa, 0.0, sa, ca;
    const Vector3 translation{a * ct, a * st, d};
    return Pose{Eigen::Quaterniond{rotation}.normalized(), translation};
}

inline RobotModel make_robot_model() {
    return {};
}

inline Vector3 origin_of(const Pose& pose) {
    return pose.translation();
}

inline Vector3 translated_along(const Pose& pose, const Vector3& local) {
    return pose.translation() + pose.so3().matrix() * local;
}

}  // namespace week4::advanced::arm
