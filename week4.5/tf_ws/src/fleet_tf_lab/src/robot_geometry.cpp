#include "fleet_tf_lab/robot_geometry.hpp"

#include <cmath>
#include <numbers>

namespace fleet_tf_lab::geometry
{

namespace
{

// Delivery route: forward at ~0.95 m/s while weaving gently between the
// corridor's shelving rows. Heading always points along the velocity vector.
constexpr double kForwardSpeed = 0.95;    // m/s along +x of map
constexpr double kWeaveAmplitude = 0.80;  // m of lateral weave
constexpr double kWeaveOmega = 0.35;      // rad/s of the weave

// Wheel-odometry drift model: a slow yaw bias (uncalibrated gyro / unequal
// wheel diameters) plus steady translational slip. Deterministic so every
// run is reproducible.
constexpr double kDriftYawRate = 0.035;  // rad/s
constexpr double kDriftSlipX = 0.040;    // m/s
constexpr double kDriftSlipY = -0.028;   // m/s

}  // namespace

tf2::Transform trueBasePoseInMap(double t) {
    const double x = kForwardSpeed * t;
    const double y = kWeaveAmplitude * std::sin(kWeaveOmega * t);
    const double dy_dt =
        kWeaveAmplitude * kWeaveOmega * std::cos(kWeaveOmega * t);
    const double yaw = std::atan2(dy_dt, kForwardSpeed);
    tf2::Quaternion rotation;
    rotation.setRPY(0.0, 0.0, yaw);
    return tf2::Transform(rotation, tf2::Vector3(x, y, 0.0));
}

tf2::Transform odometryDrift(double t) {
    tf2::Quaternion rotation;
    rotation.setRPY(0.0, 0.0, kDriftYawRate * t);
    return tf2::Transform(rotation,
                          tf2::Vector3(kDriftSlipX * t, kDriftSlipY * t, 0.0));
}

tf2::Transform wheelOdomPoseInOdom(double t) {
    return odometryDrift(t).inverse() * trueBasePoseInMap(t);
}

tf2::Transform laserMountOffset() {
    tf2::Quaternion rotation;
    rotation.setRPY(0.0, 0.0, 0.0);
    return tf2::Transform(rotation, tf2::Vector3(0.22, 0.0, 0.18));
}

tf2::Transform imuMountOffset() {
    tf2::Quaternion rotation;
    rotation.setRPY(0.0, 0.0, 0.0);
    return tf2::Transform(rotation, tf2::Vector3(-0.05, 0.0, 0.10));
}

tf2::Transform mastMountOffset() {
    tf2::Quaternion rotation;
    rotation.setRPY(0.0, 0.0, 0.0);
    return tf2::Transform(rotation, tf2::Vector3(-0.15, 0.0, 0.55));
}

tf2::Transform cameraMountOffset() {
    // Forward-looking dock camera at the top of the mast, pitched slightly
    // down toward where dock fiducials are mounted.
    tf2::Quaternion rotation;
    rotation.setRPY(0.0, 0.12, 0.0);
    return tf2::Transform(rotation, tf2::Vector3(0.06, 0.0, 0.14));
}

tf2::Quaternion cameraOpticalRotation() {
    tf2::Quaternion rotation;
    rotation.setRPY(-std::numbers::pi / 2.0, 0.0, -std::numbers::pi / 2.0);
    return rotation;
}

}  // namespace fleet_tf_lab::geometry
