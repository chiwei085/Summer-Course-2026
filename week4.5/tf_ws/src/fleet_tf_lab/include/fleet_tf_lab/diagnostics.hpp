#pragma once

#include <rclcpp/time.hpp>
#include <tf2_ros/buffer.h>

#include <chrono>
#include <cstdint>

#include "fleet_tf_lab/clearance_cache.hpp"

namespace fleet_tf_lab
{

// Ground-truth telemetry, not part of the AMR system under test. This plays
// the role that an external tracking rig (a motion-capture cell, a surveyed
// reference camera) plays on a real fleet: something to compare the robot's
// own beliefs against.
//
// Four independent verdicts:
//   STAGE1  state-pipeline freshness : does odom -> base_link keep updating?
//   STAGE2  localization accuracy    : does the robot's believed pose in map
//                                      match where it truly was *at the same
//                                      instant*? (belief at time T is graded
//                                      against truth at time T, so staleness
//                                      alone doesn't fail this stage --
//                                      wrongness does.)
//   STAGE3  dock perception          : does the believed dock-marker pose in
//                                      map match the surveyed dock pose?
//   STAGE4  safety telemetry         : does the lidar clearance writer get
//                                      its updates committed?
class Diagnostics
{
public:
    Diagnostics(tf2_ros::Buffer& tf_buffer, ClearanceCache& clearance_cache,
                const rclcpp::Time& start_time,
                double expected_clearance_writes_min);

    // Call periodically (roughly every 100-300 ms) from the node. Prints one
    // [DIAG] line and updates the running worst-case statistics used for the
    // final verdict.
    void sample();

    // Call once after the run finishes. Prints [SUMMARY] and [STAGE1..4]
    // lines and returns true only if every stage passed.
    bool printFinalReport();

private:
    tf2_ros::Buffer& tf_buffer_;
    ClearanceCache& clearance_cache_;
    rclcpp::Time start_time_;
    double expected_clearance_writes_min_;

    bool have_prior_odom_stamp_ = false;
    rclcpp::Time prior_odom_stamp_;
    std::chrono::steady_clock::time_point prior_odom_change_wall_time_;

    double odom_gap_ms_max_ = 0.0;
    double pose_err_m_max_ = -1.0;
    double pose_err_deg_max_ = 0.0;
    double dock_err_m_max_ = -1.0;
    double dock_err_deg_max_ = 0.0;
    std::uint64_t clearance_writes_baseline_ = 0;
};

}  // namespace fleet_tf_lab
