#include <geometry_msgs/msg/transform_stamped.hpp>
#include <rclcpp/rclcpp.hpp>
#include <tf2/LinearMath/Transform.h>
#include <tf2_ros/buffer.h>
#include <tf2_ros/static_transform_broadcaster.h>
#include <tf2_ros/transform_broadcaster.h>
#include <tf2_ros/transform_listener.h>

#include <chrono>
#include <cmath>
#include <cstdint>
#include <deque>
#include <future>
#include <mutex>
#include <stop_token>
#include <thread>
#include <vector>

#include "fleet_tf_lab/clearance_cache.hpp"
#include "fleet_tf_lab/diagnostics.hpp"
#include "fleet_tf_lab/robot_geometry.hpp"
#include "fleet_tf_lab/world_model.hpp"

namespace geom = fleet_tf_lab::geometry;
using fleet_tf_lab::ClearanceCache;
using fleet_tf_lab::ClearanceState;
using fleet_tf_lab::Diagnostics;

namespace
{

// How long the whole delivery leg runs for one attempt. Long enough for the
// freshness/starvation symptoms to accumulate into a clear verdict, short
// enough for a tight tutor.py edit-build-run loop.
constexpr double kRunSeconds = 8.0;

// Lidar clearance pipeline.
constexpr double kClearanceWriterPeriodSeconds = 0.04;
constexpr double kExpectedClearanceWritesMin =
    (kRunSeconds / kClearanceWriterPeriodSeconds) * 0.5;
constexpr double kCorridorHalfWidthMeters = 1.8;

// Scan matching: a real matcher does not answer instantly. By the time the
// pose estimate for a scan is ready, the scan itself is this old.
constexpr double kScanProcessingLatencySeconds = 0.15;

// Dock camera: fiducial detections arrive at this period, stamped with the
// exposure time (slightly before the driver hands the result over).
constexpr double kCameraPeriodSeconds = 0.6;
constexpr double kCameraExposureLagSeconds = 0.03;

geometry_msgs::msg::TransformStamped stampedTransform(
    const rclcpp::Time& stamp, const std::string& parent,
    const std::string& child, const tf2::Transform& transform) {
    geometry_msgs::msg::TransformStamped msg;
    msg.header.stamp = stamp;
    msg.header.frame_id = parent;
    msg.child_frame_id = child;
    msg.transform.translation.x = transform.getOrigin().x();
    msg.transform.translation.y = transform.getOrigin().y();
    msg.transform.translation.z = transform.getOrigin().z();
    msg.transform.rotation.x = transform.getRotation().x();
    msg.transform.rotation.y = transform.getRotation().y();
    msg.transform.rotation.z = transform.getRotation().z();
    msg.transform.rotation.w = transform.getRotation().w();
    return msg;
}

tf2::Transform toTf2(const geometry_msgs::msg::TransformStamped& msg) {
    return tf2::Transform(
        tf2::Quaternion(msg.transform.rotation.x, msg.transform.rotation.y,
                        msg.transform.rotation.z, msg.transform.rotation.w),
        tf2::Vector3(msg.transform.translation.x, msg.transform.translation.y,
                     msg.transform.translation.z));
}

}  // namespace

// ---------------------------------------------------------------------------
// The AMR navigation node. Everything below models one warehouse AMR ("Unit
// 12") as a single process with several concurrent subsystems:
//
//   state_estimation_group : the wheel-odometry integrator, the scan-matcher
//                            correction, AND the dock-approach controller.
//                            All three read or write the robot's pose
//                            estimate, so they share one MutuallyExclusive
//                            callback group -- none of them can ever race
//                            another on that state.
//   uplink_group           : the fleet telemetry uplink, decoupled from
//                            state estimation.
//   diagnostics_group      : the external grader, isolated from everything.
//
// The encoder driver, the dock camera driver, and the lidar clearance
// pipeline (one writer, several consumers) run as plain std::jthread workers
// outside the executor entirely, modeling sensor drivers that ship their own
// threading rather than living inside rclcpp callbacks. Each carries its own
// std::stop_token and joins automatically on destruction.
// ---------------------------------------------------------------------------
class AmrNavNode : public rclcpp::Node
{
public:
    AmrNavNode()
        : rclcpp::Node("amr_nav_node"),
          start_time_(this->now()),
          tf_buffer_(this->get_clock()),
          tf_listener_(tf_buffer_),
          broadcaster_(*this),
          static_broadcaster_(*this),
          diagnostics_(tf_buffer_, clearance_cache_, start_time_,
                       kExpectedClearanceWritesMin) {
        publishStaticFrames();

        state_estimation_group_ =
            create_callback_group(rclcpp::CallbackGroupType::MutuallyExclusive);
        uplink_group_ =
            create_callback_group(rclcpp::CallbackGroupType::MutuallyExclusive);
        diagnostics_group_ =
            create_callback_group(rclcpp::CallbackGroupType::MutuallyExclusive);

        wheel_odom_timer_ = create_wall_timer(
            std::chrono::milliseconds(20), [this] { integrateWheelOdometry(); },
            state_estimation_group_);

        scan_matcher_timer_ = create_wall_timer(
            std::chrono::milliseconds(125), [this] { runScanMatcherTick(); },
            state_estimation_group_);

        dock_controller_timer_ = create_wall_timer(
            std::chrono::milliseconds(250), [this] { runDockApproachTick(); },
            state_estimation_group_);

        uplink_timer_ = create_wall_timer(
            std::chrono::milliseconds(200), [this] { runUplinkTick(); },
            uplink_group_);

        diagnostics_timer_ = create_wall_timer(
            std::chrono::milliseconds(150), [this] { runDiagnosticsTick(); },
            diagnostics_group_);

        shutdown_timer_ = create_wall_timer(
            std::chrono::duration<double>(kRunSeconds), [this] { finish(); });

        startBackgroundThreads();
    }

    ~AmrNavNode() override { stopBackgroundThreads(); }

    bool passed() const {
        std::lock_guard<std::mutex> lock(verdict_mutex_);
        return passed_;
    }

private:
    double elapsedSeconds() const {
        return (this->now() - start_time_).seconds();
    }

    rclcpp::Time stampAtElapsed(double t) const {
        return start_time_ + rclcpp::Duration::from_seconds(t);
    }

    // -------------------------------------------------------------------
    // Static frames: sensor mounts. Every one of these is published exactly
    // once at startup, the way a real static_transform_publisher /
    // robot_state_publisher would.
    // -------------------------------------------------------------------
    void publishStaticFrames() {
        std::vector<geometry_msgs::msg::TransformStamped> statics;
        const rclcpp::Time stamp = this->now();

        statics.push_back(stampedTransform(
            stamp, std::string(geom::kBaseLinkFrame),
            std::string(geom::kLaserFrame), geom::laserMountOffset()));
        statics.push_back(stampedTransform(
            stamp, std::string(geom::kBaseLinkFrame),
            std::string(geom::kImuFrame), geom::imuMountOffset()));
        statics.push_back(stampedTransform(
            stamp, std::string(geom::kBaseLinkFrame),
            std::string(geom::kMastFrame), geom::mastMountOffset()));
        statics.push_back(stampedTransform(stamp, std::string(geom::kMastFrame),
                                           std::string(geom::kCameraFrame),
                                           geom::cameraMountOffset()));

        // camera_link -> camera_optical_frame: rotates from the ROS
        // mechanical convention (x-forward, y-left, z-up) into the vision
        // convention (z-forward, x-right, y-down) that the fiducial
        // detector's output is expressed in.
        statics.push_back(
            stampedTransform(stamp, std::string(geom::kCameraFrame),
                             std::string(geom::kCameraOpticalFrame),
                             tf2::Transform(tf2::Quaternion::getIdentity(),
                                            tf2::Vector3(0, 0, 0))));

        static_broadcaster_.sendTransform(statics);
    }

    // -------------------------------------------------------------------
    // state_estimation_group_: wheel odometry. Drains whatever encoder
    // samples the driver thread has queued since the last tick and
    // publishes odom -> base_link stamped at the newest sample's time.
    // -------------------------------------------------------------------
    void integrateWheelOdometry() {
        double latest_sample_t = -1.0;
        {
            std::lock_guard<std::mutex> lock(encoder_queue_mutex_);
            if (!encoder_queue_.empty()) {
                latest_sample_t = encoder_queue_.back();
                encoder_queue_.clear();
            }
        }
        if (latest_sample_t < 0.0) {
            return;  // Driver hasn't produced a sample yet.
        }
        broadcaster_.sendTransform(stampedTransform(
            stampAtElapsed(latest_sample_t), std::string(geom::kOdomFrame),
            std::string(geom::kBaseLinkFrame),
            geom::wheelOdomPoseInOdom(latest_sample_t)));
    }

    // -------------------------------------------------------------------
    // state_estimation_group_: scan-to-map localization. Each tick, the
    // matcher finishes processing a laser scan that was TAKEN
    // kScanProcessingLatencySeconds ago and recovers the robot's map pose
    // for that scan. Combining that matched pose with wheel odometry yields
    // the map -> odom correction this node is responsible for.
    // -------------------------------------------------------------------
    void runScanMatcherTick() {
        const double scan_t = elapsedSeconds() - kScanProcessingLatencySeconds;
        if (scan_t < 0.05) {
            return;  // First scan still being processed.
        }
        const rclcpp::Time scan_stamp = stampAtElapsed(scan_t);
        const tf2::Transform map_from_base =
            fleet_tf_lab::world::scanMatcherPoseEstimate(scan_t);

        geometry_msgs::msg::TransformStamped odom_msg;
        try {
            odom_msg = tf_buffer_.lookupTransform(
                std::string(geom::kOdomFrame),
                std::string(geom::kBaseLinkFrame), tf2::TimePointZero);
        }
        catch (const tf2::TransformException&) {
            return;  // Wheel odometry not up yet; correct next tick.
        }
        const tf2::Transform odom_from_base = toTf2(odom_msg);

        // map->odom = map->base * inverse(odom->base): the correction that
        // makes wheel odometry agree with the matched pose.
        const tf2::Transform map_from_odom =
            map_from_base * odom_from_base.inverse();
        broadcaster_.sendTransform(
            stampedTransform(scan_stamp, std::string(geom::kMapFrame),
                             std::string(geom::kOdomFrame), map_from_odom));
    }

    // -------------------------------------------------------------------
    // state_estimation_group_: dock approach controller. Runs in the SAME
    // callback group as the wheel odometry and scan matcher above, so
    // whatever this callback does blocks BOTH of them for as long as this
    // callback takes to return.
    //
    // Policy: never steer against a stale marker sighting. The approach
    // command must be computed from a detection no older than the freshness
    // tolerance.
    // -------------------------------------------------------------------
    void runDockApproachTick() {
        constexpr double kFreshnessToleranceSeconds = 0.06;

        while (true) {
            geometry_msgs::msg::TransformStamped sighting;
            try {
                sighting = tf_buffer_.lookupTransform(
                    std::string(geom::kBaseLinkFrame),
                    std::string(geom::kDockMarkerFrame), tf2::TimePointZero);
            }
            catch (const tf2::TransformException&) {
                return;  // Dock not sighted yet at all; nothing to steer
                         // against.
            }

            const double age_seconds =
                (this->now() - rclcpp::Time(sighting.header.stamp)).seconds();
            if (age_seconds < kFreshnessToleranceSeconds) {
                // Fresh enough: compute the approach command and finish.
                std::lock_guard<std::mutex> lock(dock_range_mutex_);
                last_dock_range_m_ = toTf2(sighting).getOrigin().length();
                return;
            }

            // Stale sighting: keep re-checking until the camera delivers a
            // fresh one, so this tick never acts on old data.
        }
    }

    // -------------------------------------------------------------------
    // uplink_group_: fleet telemetry uplink. Samples the clearance cache
    // and the latest dock range for the (simulated) fleet coordinator.
    // -------------------------------------------------------------------
    void runUplinkTick() {
        const ClearanceState clearance = clearance_cache_.read();
        (void)clearance;
        double dock_range = -1.0;
        {
            std::lock_guard<std::mutex> lock(dock_range_mutex_);
            dock_range = last_dock_range_m_;
        }
        (void)dock_range;
        ++uplink_frames_sent_;
    }

    // -------------------------------------------------------------------
    // diagnostics_group_: independent grading, does not affect the system.
    // -------------------------------------------------------------------
    void runDiagnosticsTick() {
        diagnostics_.sample();
        // This callback lives alone in a MutuallyExclusive group, so the
        // guard flag needs no further synchronization of its own.
        if (elapsedSeconds() >= kRunSeconds - 0.2 && !final_report_printed_) {
            final_report_printed_ = true;
            const bool ok = diagnostics_.printFinalReport();
            std::lock_guard<std::mutex> lock(verdict_mutex_);
            passed_ = ok;
        }
    }

    void finish() {
        shutdown_timer_->cancel();
        rclcpp::shutdown();
    }

    // -------------------------------------------------------------------
    // Background subsystems: the encoder driver, the dock camera driver,
    // and the lidar clearance pipeline. These are plain OS threads,
    // independent of the rclcpp executor, the way an encoder board driver,
    // a camera SDK, or a lidar driver would be in a real stack. Modeled
    // with std::jthread: each carries its own std::stop_token, and
    // stopBackgroundThreads() collapses to requesting stop and letting the
    // jthread destructors join.
    // -------------------------------------------------------------------
    void startBackgroundThreads() {
        // Encoder board: streams tick samples at 100 Hz into a queue that
        // the wheel-odometry callback drains.
        encoder_driver_thread_ = std::jthread([this](std::stop_token stop) {
            while (!stop.stop_requested()) {
                {
                    std::lock_guard<std::mutex> lock(encoder_queue_mutex_);
                    encoder_queue_.push_back(elapsedSeconds());
                    if (encoder_queue_.size() > 512) {
                        encoder_queue_.pop_front();
                    }
                }
                std::this_thread::sleep_for(std::chrono::milliseconds(10));
            }
        });

        // Dock camera: the fiducial detector reports the marker pose in the
        // optical frame, stamped at the frame's exposure time.
        camera_driver_thread_ = std::jthread([this](std::stop_token stop) {
            std::this_thread::sleep_for(std::chrono::milliseconds(250));
            while (!stop.stop_requested()) {
                const double exposure_t =
                    elapsedSeconds() - kCameraExposureLagSeconds;
                const tf2::Transform detection =
                    fleet_tf_lab::world::synthesizeDockDetection(exposure_t);
                broadcaster_.sendTransform(stampedTransform(
                    stampAtElapsed(exposure_t),
                    std::string(geom::kCameraOpticalFrame),
                    std::string(geom::kDockMarkerFrame), detection));
                std::this_thread::sleep_for(
                    std::chrono::duration<double>(kCameraPeriodSeconds));
            }
        });

        // Lidar clearance writer: measures the distance to the corridor
        // walls and commits a fresh snapshot into the shared cache.
        clearance_writer_thread_ = std::jthread([this](std::stop_token stop) {
            std::uint64_t sequence = 0;
            while (!stop.stop_requested()) {
                const double t = elapsedSeconds();
                const double lateral =
                    geom::trueBasePoseInMap(t).getOrigin().y();
                ClearanceState state;
                state.min_clearance_m =
                    kCorridorHalfWidthMeters - std::abs(lateral);
                state.slow_zone = state.min_clearance_m < 1.2;
                state.sequence = sequence++;
                clearance_cache_.write(state);
                std::this_thread::sleep_for(std::chrono::duration<double>(
                    kClearanceWriterPeriodSeconds));
            }
        });

        // Several consumer threads (safety supervisor, dashboard feed, dock
        // approach checker, ...), each holding the read lock for ~1ms to
        // process the snapshot in place. Every one of them blocks properly
        // between reads -- nobody spins.
        constexpr int kReaderThreadCount = 6;
        for (int i = 0; i < kReaderThreadCount; ++i) {
            clearance_reader_threads_.emplace_back([this](
                                                       std::stop_token stop) {
                while (!stop.stop_requested()) {
                    const ClearanceState state =
                        clearance_cache_.readWithSimulatedWork(
                            std::chrono::microseconds(1200));
                    (void)state;
                    std::this_thread::sleep_for(std::chrono::microseconds(50));
                }
            });
        }
    }

    void stopBackgroundThreads() {
        encoder_driver_thread_.request_stop();
        camera_driver_thread_.request_stop();
        clearance_writer_thread_.request_stop();
        for (auto& reader : clearance_reader_threads_) {
            reader.request_stop();
        }
        // jthread destructors join automatically once stop is requested.
    }

    rclcpp::Time start_time_;

    tf2_ros::Buffer tf_buffer_;
    tf2_ros::TransformListener tf_listener_;
    tf2_ros::TransformBroadcaster broadcaster_;
    tf2_ros::StaticTransformBroadcaster static_broadcaster_;

    ClearanceCache clearance_cache_;
    Diagnostics diagnostics_;
    mutable std::mutex verdict_mutex_;
    bool passed_ = false;
    bool final_report_printed_ = false;

    std::mutex encoder_queue_mutex_;
    std::deque<double> encoder_queue_;
    std::mutex dock_range_mutex_;
    double last_dock_range_m_ = -1.0;
    std::uint64_t uplink_frames_sent_ = 0;

    rclcpp::CallbackGroup::SharedPtr state_estimation_group_;
    rclcpp::CallbackGroup::SharedPtr uplink_group_;
    rclcpp::CallbackGroup::SharedPtr diagnostics_group_;

    rclcpp::TimerBase::SharedPtr wheel_odom_timer_;
    rclcpp::TimerBase::SharedPtr scan_matcher_timer_;
    rclcpp::TimerBase::SharedPtr dock_controller_timer_;
    rclcpp::TimerBase::SharedPtr uplink_timer_;
    rclcpp::TimerBase::SharedPtr diagnostics_timer_;
    rclcpp::TimerBase::SharedPtr shutdown_timer_;

    std::jthread encoder_driver_thread_;
    std::jthread camera_driver_thread_;
    std::jthread clearance_writer_thread_;
    std::vector<std::jthread> clearance_reader_threads_;
};

int main(int argc, char** argv) {
    rclcpp::init(argc, argv);
    auto node = std::make_shared<AmrNavNode>();

    rclcpp::executors::MultiThreadedExecutor executor(rclcpp::ExecutorOptions(),
                                                      4);
    executor.add_node(node);

    auto spin_future =
        std::async(std::launch::async, [&executor] { executor.spin(); });

    const auto deadline = std::chrono::steady_clock::now() +
                          std::chrono::duration<double>(kRunSeconds + 2.0);
    while (std::chrono::steady_clock::now() < deadline) {
        if (spin_future.wait_for(std::chrono::milliseconds(50)) ==
            std::future_status::ready) {
            break;
        }
    }

    if (rclcpp::ok()) {
        rclcpp::shutdown();
    }

    // A callback stuck in an unresolved (or partially fixed) busy-wait bug
    // can prevent the executor's worker threads from ever noticing
    // shutdown. Give it a short grace period, then force-exit rather than
    // let one hung callback hang the whole diagnostic session forever.
    if (spin_future.wait_for(std::chrono::seconds(2)) !=
        std::future_status::ready) {
        std::fflush(stdout);
        std::_Exit(node->passed() ? 0 : 1);
    }

    const bool ok = node->passed();
    return ok ? 0 : 1;
}
