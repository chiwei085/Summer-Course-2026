#pragma once

#include <tf2/LinearMath/Transform.h>

namespace fleet_tf_lab::world
{

// The world model is the simulation's ground truth. It is deliberately kept
// independent of the live broadcasters in main.cpp: it reconstructs the true
// robot and camera poses from the same motion functions the live system
// uses, but always assembles the fixed sensor geometry correctly (including
// the camera optical-frame rotation) and never suffers scheduling delays.
// Nothing in this file reads anything the live TF tree publishes.
//
// Three things are built from it:
//  - the simulated scan matcher's pose estimate (a stand-in for matching the
//    front laser against the warehouse map -- in this lab it always
//    converges to the true pose, so any residual localization error is the
//    live system's own doing),
//  - the synthetic dock-marker detection fed into the camera driver thread
//    (a stand-in for "what a real fiducial detector would report"), and
//  - the fixed true dock pose in map, used only by diagnostics to grade the
//    live system's TF-derived beliefs against reality.

// Fixed pose of the charging dock's fiducial marker in the map frame. Known
// from the warehouse survey; the one pose in the lab that never moves.
tf2::Transform trueDockMarkerPoseInMap();

// True pose of base_link in map at elapsed time t.
tf2::Transform trueBasePoseInMap(double t);

// True pose of camera_optical_frame in map at elapsed time t, computed with
// correct fixed sensor geometry end to end.
tf2::Transform trueCameraOpticalPoseInMap(double t);

// What the scan matcher reports for a laser scan taken at elapsed time t:
// the robot's pose in map at that instant. Perfect by construction.
tf2::Transform scanMatcherPoseEstimate(double t);

// What an ideal fiducial detector would measure: the dock marker's pose
// expressed in camera_optical_frame at elapsed time t. This is what the
// camera driver thread publishes as camera_optical_frame -> dock_marker.
tf2::Transform synthesizeDockDetection(double t);

}  // namespace fleet_tf_lab::world
