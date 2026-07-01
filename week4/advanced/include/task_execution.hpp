#pragma once

#include <span>
#include <vector>

#include "kinematics_control.hpp"

namespace week4::advanced::arm
{

inline Pose make_tool_pose(const Vector3& cube_center, double clearance,
                           const GripperGeometry& gripper) {
    Eigen::Matrix3d rotation;
    rotation.col(0) = Vector3::UnitX();
    rotation.col(1) = -Vector3::UnitY();
    rotation.col(2) = -Vector3::UnitZ();
    const Vector3 tool_position =
        cube_center +
        Vector3{0.0, 0.0,
                gripper.palm_length + gripper.finger_length * 0.5 + clearance};
    return Pose{Eigen::Quaterniond{rotation}.normalized(), tool_position};
}

inline Vector3 tool_local_cube_center(const Pose& world_T_tool,
                                      const Pose& world_T_cube) {
    return world_T_tool.inverse() * world_T_cube.translation();
}

inline bool cube_in_gripper_contact(const RobotModel& model,
                                    const Pose& world_T_tool,
                                    const Pose& world_T_cube,
                                    double tolerance) {
    const Vector3 tool_p_cube =
        tool_local_cube_center(world_T_tool, world_T_cube);
    const auto& gripper = model.gripper;
    return std::abs(tool_p_cube.x()) <=
               gripper.closed_jaw_width * 0.5 + kCubeHalfExtent + tolerance &&
           std::abs(tool_p_cube.y()) <=
               gripper.finger_offset + kCubeHalfExtent + tolerance &&
           tool_p_cube.z() >=
               gripper.palm_length - kCubeHalfExtent - tolerance &&
           tool_p_cube.z() <= gripper.palm_length + gripper.finger_length +
                                  kCubeHalfExtent + tolerance;
}

inline bool cube_at_place_contact(const Scene& scene, const Pose& world_T_cube,
                                  double tolerance) {
    return (world_T_cube.translation() - scene.destination_cube).norm() <=
           tolerance;
}

inline std::array<Stage, 8> make_task_stages(
    const Scene& scene = {}, const GripperGeometry& gripper = {}) {
    const JointVector home = make_joints(20, -80, 110, -120, -90, 20);
    const JointVector source_high = make_joints(-35, -75, 115, -130, -90, -35);
    const JointVector source_low = make_joints(-35, -92, 128, -126, -90, -35);
    const JointVector dest_high = make_joints(35, -75, 115, -130, -90, 35);
    const JointVector dest_low = make_joints(35, -92, 128, -126, -90, 35);

    return {{
        {.name = "home",
         .world_T_target = make_tool_pose({0.34, 0.00, kCubeHalfExtent},
                                          scene.transfer_clearance, gripper),
         .posture_hint = home},
        {.name = "pre-grasp",
         .world_T_target = make_tool_pose(scene.source_cube,
                                          scene.approach_clearance, gripper),
         .posture_hint = source_high},
        {.name = "grasp",
         .world_T_target = make_tool_pose(scene.source_cube, 0.0, gripper),
         .posture_hint = source_low,
         .translation_tolerance = 0.020,
         .closes_gripper = true},
        {.name = "lift",
         .world_T_target = make_tool_pose(scene.source_cube,
                                          scene.transfer_clearance, gripper),
         .posture_hint = source_high},
        {.name = "transfer",
         .world_T_target = make_tool_pose(scene.destination_cube,
                                          scene.transfer_clearance, gripper),
         .posture_hint = dest_high},
        {.name = "place",
         .world_T_target = make_tool_pose(scene.destination_cube, 0.0, gripper),
         .posture_hint = dest_low,
         .translation_tolerance = 0.020,
         .releases_cube = true},
        {.name = "release",
         .world_T_target = make_tool_pose(scene.destination_cube,
                                          scene.approach_clearance, gripper),
         .posture_hint = dest_high,
         .releases_cube = true},
        {.name = "retreat",
         .world_T_target = make_tool_pose({0.34, 0.00, kCubeHalfExtent},
                                          scene.transfer_clearance, gripper),
         .posture_hint = home,
         .releases_cube = true},
    }};
}

inline TrajectorySample make_sample(double time, int stage_index,
                                    const Stage& stage, const RobotModel& model,
                                    const Scene& scene, const JointVector& q,
                                    const CubeState& cube,
                                    const ErrorSummary& error) {
    const Kinematics kinematics = forward_kinematics(model, q);
    return {
        .time = time,
        .stage_index = stage_index,
        .stage_name = stage.name,
        .joints = q,
        .joint_frames = kinematics.joint_frames,
        .visual_links = kinematics.visual_links,
        .tool_pose = kinematics.world_T_tool,
        .gripper_geometry = model.gripper,
        .cube_pose = cube.world_T_cube,
        .target = stage.world_T_target.translation(),
        .source_pad = scene.source_cube,
        .destination_pad = scene.destination_cube,
        .gripper_closed = cube.grasped,
        .joint_limit_warning = near_joint_limit(model, q),
        .singularity_warning = near_singularity(kinematics),
        .error = error,
    };
}

template <SampleObserver Observer>
SimulationStats run_stage(JointVector& q, CubeState& cube,
                          const RobotModel& model, const Scene& scene,
                          const Stage& stage, int stage_index,
                          double& simulation_time,
                          const ControllerConfig& config, Observer&& observe) {
    // Reset each stage so the acceleration-rate-limiter in ik_velocity() ramps
    // up smoothly from rest instead of carrying over the previous stage's
    // exit velocity into an unrelated target.
    JointVector previous_velocity = JointVector::Zero();

    for (int step = 0; step < config.max_steps_per_stage; ++step) {
        const Kinematics kinematics = forward_kinematics(model, q);
        const auto error =
            pose_error(kinematics.world_T_tool, stage.world_T_target);

        if (cube.grasped) {
            cube.world_T_cube = kinematics.world_T_tool * cube.tool_T_cube;
        }
        observe(make_sample(simulation_time, stage_index, stage, model, scene,
                            q, cube, error));

        bool contact_ready = true;
        if (stage.closes_gripper) {
            contact_ready = cube_in_gripper_contact(
                model, kinematics.world_T_tool, cube.world_T_cube, 0.018);
        }
        if (stage.releases_cube) {
            contact_ready = cube.grasped ? cube_at_place_contact(
                                               scene, cube.world_T_cube, 0.025)
                                         : true;
        }

        if (reached_target(stage, error, config) && contact_ready) {
            if (stage.closes_gripper) {
                cube.grasped = true;
                cube.tool_T_cube =
                    kinematics.world_T_tool.inverse() * cube.world_T_cube;
            }
            if (stage.releases_cube) {
                cube.grasped = false;
                cube.world_T_cube = Pose{cube.world_T_cube.unit_quaternion(),
                                         scene.destination_cube};
            }
            observe(make_sample(simulation_time, stage_index, stage, model,
                                scene, q, cube, error));
            return {
                .stage_index = stage_index,
                .stage_name = stage.name,
                .steps = step,
                .elapsed_time = step * config.dt,
                .final_error = error,
                .converged = true,
            };
        }

        const JointVector velocity = ik_velocity(
            model, kinematics, error, stage, q, config, previous_velocity);
        q += velocity * config.dt;
        clamp_to_joint_limits(model, q);
        simulation_time += config.dt;
    }

    const auto error = pose_error(forward_kinematics(model, q).world_T_tool,
                                  stage.world_T_target);
    observe(make_sample(simulation_time, stage_index, stage, model, scene, q,
                        cube, error));
    return {
        .stage_index = stage_index,
        .stage_name = stage.name,
        .steps = config.max_steps_per_stage,
        .elapsed_time = config.max_steps_per_stage * config.dt,
        .final_error = error,
        .converged = false,
    };
}

template <SampleObserver Observer>
std::vector<SimulationStats> run_pick_and_place(JointVector& q, CubeState& cube,
                                                const RobotModel& model,
                                                const Scene& scene,
                                                std::span<const Stage> stages,
                                                const ControllerConfig& config,
                                                Observer&& observe,
                                                double& simulation_time) {
    std::vector<SimulationStats> all_stats;
    all_stats.reserve(stages.size());

    for (int stage_index = 0; stage_index < std::ssize(stages); ++stage_index) {
        auto stats = run_stage(q, cube, model, scene, stages[stage_index],
                               stage_index, simulation_time, config, observe);
        all_stats.push_back(stats);
        if (!stats.converged) {
            break;
        }
    }
    return all_stats;
}

}  // namespace week4::advanced::arm
