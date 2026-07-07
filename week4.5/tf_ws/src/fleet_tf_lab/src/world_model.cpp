#include "fleet_tf_lab/world_model.hpp"

#include <numbers>

#include "fleet_tf_lab/robot_geometry.hpp"

namespace fleet_tf_lab::world
{

namespace geom = fleet_tf_lab::geometry;

tf2::Transform trueDockMarkerPoseInMap() {
    // Mounted on the end wall of the corridor, facing back down the aisle
    // toward approaching robots.
    tf2::Quaternion rotation;
    rotation.setRPY(0.0, 0.0, std::numbers::pi * 0.94);
    return tf2::Transform(rotation, tf2::Vector3(9.20, 0.55, 0.45));
}

tf2::Transform trueBasePoseInMap(double t) {
    return geom::trueBasePoseInMap(t);
}

tf2::Transform trueCameraOpticalPoseInMap(double t) {
    tf2::Transform pose = geom::trueBasePoseInMap(t);
    pose *= geom::mastMountOffset();
    pose *= geom::cameraMountOffset();
    // The one link this file is careful never to get wrong: the ROS
    // mechanical frame to vision optical frame rotation.
    pose *= tf2::Transform(geom::cameraOpticalRotation(),
                           tf2::Vector3(0.0, 0.0, 0.0));
    return pose;
}

tf2::Transform scanMatcherPoseEstimate(double t) {
    // Stands in for scan-to-map matching that has fully converged: the
    // matcher, given a scan taken at time t, recovers exactly where the
    // robot was at time t. Whatever the live system then *does* with this
    // answer is its own responsibility.
    return geom::trueBasePoseInMap(t);
}

tf2::Transform synthesizeDockDetection(double t) {
    const tf2::Transform camera_optical_in_map = trueCameraOpticalPoseInMap(t);
    return camera_optical_in_map.inverse() * trueDockMarkerPoseInMap();
}

}  // namespace fleet_tf_lab::world
