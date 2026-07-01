#pragma once

#include <Eigen/SVD>

#include <algorithm>
#include <array>
#include <limits>

#include "arm_model.hpp"

namespace week4::advanced::arm
{

inline Kinematics forward_kinematics(const RobotModel& model,
                                     const JointVector& q) {
    Kinematics result;
    Pose world_T_joint = model.world_T_base;
    std::array<Pose, kJointCount + 1> dh_frames{};
    dh_frames[0] = world_T_joint;

    for (int joint = 0; joint < kJointCount; ++joint) {
        result.joint_origins[joint] = world_T_joint.translation();
        result.joint_axes[joint] = world_T_joint.so3().matrix().col(2);
        world_T_joint *= make_dh_transform(q[joint] + model.theta_offset[joint],
                                           model.d[joint], model.a[joint],
                                           model.alpha[joint]);
        dh_frames[joint + 1] = world_T_joint;
    }

    result.world_T_flange = world_T_joint;
    result.world_T_tool = world_T_joint * model.flange_T_tool;

    const Vector3 base = origin_of(dh_frames[0]);
    const Vector3 shoulder = origin_of(dh_frames[1]);
    const Vector3 elbow = origin_of(dh_frames[2]);
    const Vector3 wrist1 = origin_of(dh_frames[3]);
    const Vector3 wrist2 = origin_of(dh_frames[4]);
    const Vector3 wrist3 = origin_of(dh_frames[5]);
    const Vector3 flange = origin_of(result.world_T_flange);
    const Vector3 tool = origin_of(result.world_T_tool);

    result.joint_frames = {{
        {.role = JointRole::base, .pose = dh_frames[0]},
        {.role = JointRole::shoulder, .pose = dh_frames[1]},
        {.role = JointRole::elbow, .pose = dh_frames[2]},
        {.role = JointRole::wrist1, .pose = dh_frames[3]},
        {.role = JointRole::wrist2, .pose = dh_frames[4]},
        {.role = JointRole::wrist3, .pose = dh_frames[5]},
        {.role = JointRole::flange, .pose = result.world_T_flange},
        {.role = JointRole::tool, .pose = result.world_T_tool},
    }};
    result.visual_links = {{
        {.role = LinkRole::pedestal,
         .start = base,
         .end = shoulder,
         .radius = 0.055},
        {.role = LinkRole::upper_arm,
         .start = shoulder,
         .end = elbow,
         .radius = 0.035},
        {.role = LinkRole::forearm,
         .start = elbow,
         .end = wrist1,
         .radius = 0.032},
        {.role = LinkRole::wrist_stack,
         .start = wrist1,
         .end = wrist2,
         .radius = 0.027},
        {.role = LinkRole::wrist_stack,
         .start = wrist2,
         .end = wrist3,
         .radius = 0.024},
        {.role = LinkRole::flange,
         .start = wrist3,
         .end = flange,
         .radius = 0.024},
        {.role = LinkRole::gripper_palm,
         .start = flange,
         .end = tool,
         .radius = 0.018},
    }};
    return result;
}

inline ErrorSummary pose_error(const Pose& world_T_tool,
                               const Pose& world_T_target) {
    const Vector3 translation =
        world_T_target.translation() - world_T_tool.translation();
    const Sophus::SO3d world_R_error =
        world_T_target.so3() * world_T_tool.so3().inverse();
    Vector6 tangent = Vector6::Zero();
    tangent.head<3>() = translation;
    tangent.tail<3>() = world_R_error.log();
    return {
        .tangent = tangent,
        .translation_norm = translation.norm(),
        .rotation_norm = tangent.tail<3>().norm(),
    };
}

inline bool reached_target(const Stage& stage, const ErrorSummary& error,
                           const ControllerConfig& config) {
    const double translation_tolerance = stage.translation_tolerance > 0.0
                                             ? stage.translation_tolerance
                                             : config.translation_tolerance;
    return error.translation_norm < translation_tolerance &&
           error.rotation_norm < config.rotation_tolerance;
}

inline Jacobian spatial_jacobian(const Kinematics& kinematics) {
    Jacobian jacobian = Jacobian::Zero();
    const Vector3 tool = kinematics.world_T_tool.translation();
    for (int joint = 0; joint < kJointCount; ++joint) {
        const Vector3 axis = kinematics.joint_axes[joint].normalized();
        jacobian.block<3, 1>(0, joint) =
            axis.cross(tool - kinematics.joint_origins[joint]);
        jacobian.block<3, 1>(3, joint) = axis;
    }
    return jacobian;
}

inline double jacobian_condition_number(const Kinematics& kinematics) {
    const Jacobian jacobian = spatial_jacobian(kinematics);
    const Eigen::JacobiSVD<Jacobian> svd{jacobian};
    const auto singular_values = svd.singularValues();
    const double largest = singular_values.maxCoeff();
    const double smallest = singular_values.minCoeff();
    if (smallest < 1.0e-9) {
        return std::numeric_limits<double>::infinity();
    }
    return largest / smallest;
}

inline bool near_singularity(const Kinematics& kinematics) {
    return jacobian_condition_number(kinematics) > 250.0;
}

// Margin is a fraction of each joint's full range rather than a fixed
// radian value: with the wide (near-continuous) UR-style limits used here, a
// fixed margin of a few hundredths of a radian would sit far too close to the
// hard stop to ever fire during normal operation.
constexpr double kLimitMarginFraction = 0.08;

inline bool near_joint_limit(const RobotModel& model, const JointVector& q) {
    for (int i = 0; i < kJointCount; ++i) {
        const double range = model.limits[i].upper - model.limits[i].lower;
        const double margin = kLimitMarginFraction * range;
        if (q[i] < model.limits[i].lower + margin ||
            q[i] > model.limits[i].upper - margin) {
            return true;
        }
    }
    return false;
}

inline void clamp_to_joint_limits(const RobotModel& model, JointVector& q) {
    for (int i = 0; i < kJointCount; ++i) {
        q[i] = std::clamp(q[i], model.limits[i].lower, model.limits[i].upper);
    }
}

inline void clamp_joint_speed(const RobotModel& model, JointVector& velocity) {
    for (int i = 0; i < velocity.size(); ++i) {
        velocity[i] = std::clamp(velocity[i], -model.max_joint_speed,
                                 model.max_joint_speed);
    }
}

inline JointVector normalized_joint_delta(JointVector delta) {
    for (int i = 0; i < delta.size(); ++i) {
        while (delta[i] > std::numbers::pi) {
            delta[i] -= 2.0 * std::numbers::pi;
        }
        while (delta[i] < -std::numbers::pi) {
            delta[i] += 2.0 * std::numbers::pi;
        }
    }
    return delta;
}

// Gradient of a parabolic confining potential centered at each joint's
// mid-range: ~zero away from the limits, growing as q approaches either
// bound. Used as a soft, continuously-acting alternative to relying on
// clamp_to_joint_limits() alone, which only reacts after a step has already
// pushed a joint past its bound.
inline double joint_limit_gradient(const JointLimit& limit, double q) {
    const double half_range = 0.5 * (limit.upper - limit.lower);
    const double mid = 0.5 * (limit.upper + limit.lower);
    return -(q - mid) / (half_range * half_range);
}

inline JointVector joint_limit_avoidance(const RobotModel& model,
                                         const JointVector& q) {
    JointVector avoidance;
    for (int i = 0; i < kJointCount; ++i) {
        avoidance[i] = joint_limit_gradient(model.limits[i], q[i]);
    }
    return avoidance;
}

// Damped-least-squares damping that grows once manipulability (the Jacobian's
// smallest singular value) drops below singular_floor, and stays at the
// caller's base damping otherwise. This trades tracking accuracy for
// stability only near singularities instead of everywhere.
inline double adaptive_damping(const Jacobian& jacobian, double base_damping,
                               double singular_floor) {
    if (singular_floor <= 0.0) {
        return base_damping;
    }
    const Eigen::JacobiSVD<Jacobian> svd{jacobian};
    const double sigma_min = svd.singularValues().minCoeff();
    if (sigma_min >= singular_floor) {
        return base_damping;
    }
    const double deficit = (singular_floor - sigma_min) / singular_floor;
    return base_damping * (1.0 + 4.0 * deficit * deficit);
}

inline JointVector ik_velocity(const RobotModel& model,
                               const Kinematics& kinematics,
                               const ErrorSummary& error, const Stage& stage,
                               const JointVector& q,
                               const ControllerConfig& config,
                               JointVector& previous_velocity) {
    const Jacobian jacobian = spatial_jacobian(kinematics);
    const double damping =
        adaptive_damping(jacobian, config.damping, config.singular_floor);
    const Eigen::Matrix<double, 6, 6> regularizer =
        (damping * damping) * Eigen::Matrix<double, 6, 6>::Identity();

    Vector6 command = Vector6::Zero();
    command.head<3>() = config.kp_translation * error.tangent.head<3>();
    command.tail<3>() = config.kp_rotation * error.tangent.tail<3>();

    const JointVector posture =
        config.posture_gain * normalized_joint_delta(stage.posture_hint - q);
    const JointVector limit_avoidance =
        config.limit_avoidance_gain * joint_limit_avoidance(model, q);
    const JointVector secondary = posture + limit_avoidance;

    // velocity = J^T (J J^T + damping^2 I)^-1 (command - J secondary) +
    // secondary, i.e. the damped-least-squares command plus a nullspace-ish
    // secondary objective (posture hint + joint-limit avoidance), solved
    // directly instead of forming the explicit 6x6 pseudo-inverse.
    const auto damped_jjt =
        (jacobian * jacobian.transpose() + regularizer).ldlt();
    const Vector6 residual = command - jacobian * secondary;
    JointVector velocity =
        jacobian.transpose() * damped_jjt.solve(residual) + secondary;
    clamp_joint_speed(model, velocity);

    // Rate-limit against the previous step's command so a stage's target
    // jump ramps in over the acceleration limit instead of appearing as an
    // instantaneous velocity step at the stage boundary.
    const double max_delta = config.max_joint_acceleration * config.dt;
    JointVector delta = velocity - previous_velocity;
    for (int i = 0; i < delta.size(); ++i) {
        delta[i] = std::clamp(delta[i], -max_delta, max_delta);
    }
    velocity = previous_velocity + delta;
    previous_velocity = velocity;
    return velocity;
}

}  // namespace week4::advanced::arm
