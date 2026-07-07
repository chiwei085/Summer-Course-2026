#pragma once

#include <tf2/LinearMath/Quaternion.h>
#include <tf2/LinearMath/Transform.h>
#include <tf2/LinearMath/Vector3.h>

#include <string_view>

namespace fleet_tf_lab::geometry
{

// ---------------------------------------------------------------------------
// Frame names. Every broadcaster and every consumer in this package spells a
// frame id through one of these constants so a typo can never silently split
// the tree into two disconnected trees.
// ---------------------------------------------------------------------------
inline constexpr std::string_view kMapFrame = "map";
inline constexpr std::string_view kOdomFrame = "odom";
inline constexpr std::string_view kBaseLinkFrame = "base_link";
inline constexpr std::string_view kLaserFrame = "laser_link";
inline constexpr std::string_view kImuFrame = "imu_link";
inline constexpr std::string_view kMastFrame = "mast_link";
inline constexpr std::string_view kCameraFrame = "camera_link";
inline constexpr std::string_view kCameraOpticalFrame = "camera_optical_frame";
inline constexpr std::string_view kDockMarkerFrame = "dock_marker";

// ---------------------------------------------------------------------------
// Motion. The AMR drives a deterministic delivery route down a warehouse
// corridor: a smooth weave at roughly 1 m/s. The same functions feed both the
// live system and the world model's ground truth, so the only ways the two
// can disagree are (a) how a broadcaster assembles transforms and timestamps
// from these pieces, and (b) how the pieces are scheduled at runtime.
// ---------------------------------------------------------------------------

// True pose of base_link in map at elapsed time t. This is "where the robot
// physically is" -- only the world model and the simulated scan matcher are
// allowed to see it.
tf2::Transform trueBasePoseInMap(double t);

// Accumulated wheel-odometry drift at elapsed time t: the transform a perfect
// localizer would have to publish as map -> odom to cancel the drift. Grows
// smoothly from identity at t = 0 (wheel slip plus a slow gyro yaw bias).
tf2::Transform odometryDrift(double t);

// odom -> base_link as the wheel-encoder pipeline reports it: the true pose
// contaminated by odometryDrift(t). Stands in for integrating encoder ticks.
tf2::Transform wheelOdomPoseInOdom(double t);

// ---------------------------------------------------------------------------
// Fixed sensor geometry. Where each sensor is bolted onto the chassis. These
// numbers are correct by construction -- bugs in this lab come from *how* a
// broadcaster assembles a transform from these pieces, not from the numbers.
// ---------------------------------------------------------------------------
tf2::Transform laserMountOffset();   // base_link -> laser_link
tf2::Transform imuMountOffset();     // base_link -> imu_link
tf2::Transform mastMountOffset();    // base_link -> mast_link
tf2::Transform cameraMountOffset();  // mast_link -> camera_link

// The REP-103 optical-frame rotation: camera_link uses the ROS mechanical
// convention (x-forward, y-left, z-up); camera_optical_frame uses the vision
// convention (z-forward, x-right, y-down). Every camera driver in the ROS
// ecosystem applies this rotation once, between the mechanical frame and the
// optical frame -- it is easy to forget because skipping it does not stop
// anything from compiling or even from publishing a fully connected TF tree.
tf2::Quaternion cameraOpticalRotation();

}  // namespace fleet_tf_lab::geometry
