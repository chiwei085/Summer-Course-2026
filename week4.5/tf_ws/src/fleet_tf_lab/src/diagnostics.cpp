#include "fleet_tf_lab/diagnostics.hpp"

#include <tf2/LinearMath/Transform.h>
#include <tf2/exceptions.h>
#include <tf2_geometry_msgs/tf2_geometry_msgs.hpp>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <numbers>

#include "fleet_tf_lab/robot_geometry.hpp"
#include "fleet_tf_lab/world_model.hpp"

namespace fleet_tf_lab
{

namespace
{

constexpr double kOdomGapToleranceMs = 250.0;
constexpr double kPoseToleranceMeters = 0.08;
constexpr double kPoseToleranceDegrees = 10.0;
constexpr double kDockToleranceMeters = 0.15;
constexpr double kDockToleranceDegrees = 10.0;

// Ignore the very beginning of the run, before the localization and
// detection pipelines have produced their first outputs.
constexpr double kGradingWarmupSeconds = 1.0;

tf2::Transform toTf2(const geometry_msgs::msg::TransformStamped& msg) {
    tf2::Transform out;
    tf2::fromMsg(msg.transform, out);
    return out;
}

double rotationErrorDegrees(const tf2::Quaternion& a,
                            const tf2::Quaternion& b) {
    const double dot = std::abs(a.dot(b));
    const double clamped = std::min(1.0, std::max(-1.0, dot));
    return 2.0 * std::acos(clamped) * 180.0 / std::numbers::pi;
}

}  // namespace

Diagnostics::Diagnostics(tf2_ros::Buffer& tf_buffer,
                         ClearanceCache& clearance_cache,
                         const rclcpp::Time& start_time,
                         double expected_clearance_writes_min)
    : tf_buffer_(tf_buffer),
      clearance_cache_(clearance_cache),
      start_time_(start_time),
      expected_clearance_writes_min_(expected_clearance_writes_min),
      prior_odom_stamp_(0, 0, RCL_ROS_TIME),
      prior_odom_change_wall_time_(std::chrono::steady_clock::now()) {
    clearance_writes_baseline_ = clearance_cache_.writesCommitted();
}

void Diagnostics::sample() {
    const auto wall_now = std::chrono::steady_clock::now();

    // --- Stage 1: is odom -> base_link actually being kept fresh? ---
    double odom_gap_ms = 0.0;
    try {
        const auto odom_tf = tf_buffer_.lookupTransform(
            std::string(geometry::kOdomFrame),
            std::string(geometry::kBaseLinkFrame), tf2::TimePointZero);
        const rclcpp::Time stamp(odom_tf.header.stamp, RCL_ROS_TIME);
        if (!have_prior_odom_stamp_ || stamp != prior_odom_stamp_) {
            prior_odom_stamp_ = stamp;
            prior_odom_change_wall_time_ = wall_now;
            have_prior_odom_stamp_ = true;
        }
        else {
            odom_gap_ms = std::chrono::duration_cast<
                              std::chrono::duration<double, std::milli>>(
                              wall_now - prior_odom_change_wall_time_)
                              .count();
            odom_gap_ms_max_ = std::max(odom_gap_ms_max_, odom_gap_ms);
        }
    }
    catch (const tf2::TransformException&) {
        // Not yet available at startup.
    }

    // --- Stage 2: does the believed pose match the truth AT THE SAME
    // INSTANT? The TimePointZero lookup resolves to the latest instant the
    // whole map -> base_link chain is defined at; the returned stamp tells
    // us which instant that was, and the belief is graded against the truth
    // for that same instant. A belief that is merely *behind* therefore
    // still passes -- only a belief that disagrees with where the robot
    // actually was at that moment fails. ---
    double pose_err_m = -1.0;
    double pose_err_deg = -1.0;
    try {
        const auto base_in_map = tf_buffer_.lookupTransform(
            std::string(geometry::kMapFrame),
            std::string(geometry::kBaseLinkFrame), tf2::TimePointZero);
        const double belief_t =
            (rclcpp::Time(base_in_map.header.stamp) - start_time_).seconds();
        if (belief_t > kGradingWarmupSeconds) {
            const tf2::Transform believed = toTf2(base_in_map);
            const tf2::Transform truth = world::trueBasePoseInMap(belief_t);
            pose_err_m = believed.getOrigin().distance(truth.getOrigin());
            pose_err_deg = rotationErrorDegrees(believed.getRotation(),
                                                truth.getRotation());
            pose_err_m_max_ = std::max(pose_err_m_max_, pose_err_m);
            pose_err_deg_max_ = std::max(pose_err_deg_max_, pose_err_deg);
        }
    }
    catch (const tf2::TransformException&) {
        // map -> odom not published yet; not itself a failure condition.
    }

    // --- Stage 3: does the believed dock-marker pose in map match the
    // surveyed dock pose? The dock never moves, so this grades the entire
    // chain: localization, sensor mounts, and the detection itself. ---
    double dock_err_m = -1.0;
    double dock_err_deg = -1.0;
    try {
        const auto marker_in_map = tf_buffer_.lookupTransform(
            std::string(geometry::kMapFrame),
            std::string(geometry::kDockMarkerFrame), tf2::TimePointZero);
        const double belief_t =
            (rclcpp::Time(marker_in_map.header.stamp) - start_time_).seconds();
        if (belief_t > kGradingWarmupSeconds) {
            const tf2::Transform believed = toTf2(marker_in_map);
            const tf2::Transform truth = world::trueDockMarkerPoseInMap();
            dock_err_m = believed.getOrigin().distance(truth.getOrigin());
            dock_err_deg = rotationErrorDegrees(believed.getRotation(),
                                                truth.getRotation());
            dock_err_m_max_ = std::max(dock_err_m_max_, dock_err_m);
            dock_err_deg_max_ = std::max(dock_err_deg_max_, dock_err_deg);
        }
    }
    catch (const tf2::TransformException&) {
        // No detection in the buffer yet.
    }

    const std::uint64_t clearance_writes =
        clearance_cache_.writesCommitted() - clearance_writes_baseline_;

    std::printf(
        "[DIAG] odom_gap_ms=%.0f pose_err_m=%.3f pose_err_deg=%.1f "
        "dock_err_m=%.3f dock_err_deg=%.1f clearance_writes=%lu\n",
        odom_gap_ms, pose_err_m, pose_err_deg, dock_err_m, dock_err_deg,
        static_cast<unsigned long>(clearance_writes));
    std::fflush(stdout);
}

bool Diagnostics::printFinalReport() {
    const std::uint64_t clearance_writes_total =
        clearance_cache_.writesCommitted() - clearance_writes_baseline_;

    const bool stage1_pass =
        have_prior_odom_stamp_ && odom_gap_ms_max_ < kOdomGapToleranceMs;
    const bool stage2_pass = pose_err_m_max_ >= 0.0 &&
                             pose_err_m_max_ < kPoseToleranceMeters &&
                             pose_err_deg_max_ < kPoseToleranceDegrees;
    const bool stage3_pass = dock_err_m_max_ >= 0.0 &&
                             dock_err_m_max_ < kDockToleranceMeters &&
                             dock_err_deg_max_ < kDockToleranceDegrees;
    const bool stage4_pass = static_cast<double>(clearance_writes_total) >=
                             expected_clearance_writes_min_;

    std::printf(
        "[SUMMARY] odom_gap_ms_max=%.0f pose_err_m_max=%.3f "
        "pose_err_deg_max=%.1f dock_err_m_max=%.3f dock_err_deg_max=%.1f "
        "clearance_writes_total=%lu clearance_writes_expected_min=%.0f\n",
        odom_gap_ms_max_, pose_err_m_max_, pose_err_deg_max_, dock_err_m_max_,
        dock_err_deg_max_, static_cast<unsigned long>(clearance_writes_total),
        expected_clearance_writes_min_);
    std::printf("[STAGE1] %s\n", stage1_pass ? "PASS" : "FAIL");
    std::printf("[STAGE2] %s\n", stage2_pass ? "PASS" : "FAIL");
    std::printf("[STAGE3] %s\n", stage3_pass ? "PASS" : "FAIL");
    std::printf("[STAGE4] %s\n", stage4_pass ? "PASS" : "FAIL");
    std::fflush(stdout);

    return stage1_pass && stage2_pass && stage3_pass && stage4_pass;
}

}  // namespace fleet_tf_lab
