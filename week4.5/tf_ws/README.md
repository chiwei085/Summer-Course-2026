# Week 4.5: TF + Concurrency Lab -- Fleet Ops Diagnostic Shift

An independent ROS 2 (Jazzy) lab: a single-process, multi-threaded warehouse
AMR (autonomous mobile robot) navigation stack with four real bugs hidden
inside it. 

Like on a real robot, **the bugs' symptoms overlap**: a pure concurrency bug
shows up on the scorecard as a localization failure, and the real TF bugs
only become visible once the pipeline underneath them is healthy again. 

You are the on-call engineer; a `tutor.py` (outside the colcon workspace, so it
is never built) drives you through diagnosing and fixing each one.

## The scenario

`src/fleet_tf_lab` is a single ROS 2 node (`fleet_tf_lab_node`, node name
`amr_nav_node`) that models one warehouse AMR ("Unit 12") end to end while it
drives a delivery leg toward its charging dock:

```
map                          (scan matcher publishes map -> odom)
 └─ odom                     (wheel odometry publishes odom -> base_link)
     └─ base_link
         ├─ laser_link       (static)
         ├─ imu_link         (static)
         └─ mast_link        (static)
             └─ camera_link  (static)
                 └─ camera_optical_frame (static)
                     └─ dock_marker      (fiducial detection)
```

The robot's true motion, its wheel-odometry drift, and the dock's surveyed
pose are all deterministic functions (`robot_geometry.hpp`), so every run is
reproducible. A `world_model.hpp/.cpp` holds an independent, always-correct
ground truth used to synthesize what the scan matcher and the dock camera
"measure" -- it never reads anything the live TF tree publishes, so it can't
be contaminated by the live system's own bugs.

The interesting part is the *pipeline* between those measurements and the TF
tree:

- **Wheel odometry**: an encoder-driver `std::jthread` streams tick samples
  into a queue; a 20 ms timer drains it and broadcasts `odom -> base_link`
  (with realistic, deterministic drift).
- **Scan-to-map localization**: a 125 ms timer models a scan matcher with
  150 ms of processing latency. It combines the matched pose with wheel
  odometry to broadcast the `map -> odom` correction -- the same
  publish-the-correction pattern AMCL and slam_toolbox use.
- **Dock approach controller**: a 250 ms timer that refuses to steer against
  a stale marker sighting.
- All three of the above share **one `MutuallyExclusive` callback group**
  ("they all touch the pose estimate, so they are serialized" -- a very
  common and very defensible-sounding design).
- **Dock camera driver**: a plain `std::jthread` publishing
  `camera_optical_frame -> dock_marker` fiducial detections every 600 ms,
  stamped at exposure time.
- **Lidar clearance pipeline**: a writer `std::jthread` commits obstacle
  clearance snapshots into a hand-rolled reader/writer cache
  (`clearance_cache.hpp`); six consumer threads (safety supervisor,
  telemetry uplink, dashboard, ...) poll it continuously.

A `Diagnostics` component (`diagnostics.hpp/.cpp`) is the lab's ground-truth
grader -- it plays the role of the warehouse's external tracking rig. It
grades the robot's *belief at time T against the truth at the same time T*,
so a belief that is merely behind doesn't fail; a belief that is *wrong*
does. It prints `[DIAG]` lines throughout the run and a final `[SUMMARY]` /
`[STAGE1..4]` verdict.

The node runs for a fixed ~8 second session and exits on its own
(`echo $?` is 0 only if all four stages pass).

## The four bugs

The lab ships broken in four independent ways. None of them throw, crash, or
fail the build -- and their *symptoms are entangled*, which is the actual
lesson:

1. **A busy-wait that starves its callback-group siblings.** The dock
   approach controller spins waiting for a fresh detection while sharing a
   `MutuallyExclusive` group with the wheel-odometry and scan-matcher
   timers. Both freeze for ~600 ms stretches, and the pose error explodes
   to tens of centimeters -- so a concurrency bug reads as a localization
   failure. Naively adding a `sleep_for()` does *not* fix it: the callback
   still has to return before the group frees up.
2. **A timestamp-pairing error in the localization correction.** The scan
   matcher's answer describes where the robot was 150 ms ago, but it is
   combined with wheel odometry looked up at `tf2::TimePointZero`
   ("latest"). The resulting error is proportional to speed x latency
   (~15 cm) -- invisible until bug 1 is fixed, because the starvation error
   dwarfs it.
3. **A silently wrong static transform.** The camera's
   `camera_link -> camera_optical_frame` mount is missing the REP-103
   optical rotation, so the believed dock-marker pose lands meters from the
   surveyed dock pose -- large, constant, and perfectly repeatable.
4. **Reader/writer starvation, not busy-waiting.** A hand-rolled
   reader-preferring lock lets a steady stream of well-behaved,
   properly-blocking reader threads starve the clearance writer
   indefinitely, purely because of the locking policy (the classic
   first-readers-writers problem).

The intended diagnosis order is itself part of the curriculum: establish
*freshness* before you trust *accuracy*, then peel the remaining layers.

## Running the lab

```bash
source /opt/ros/jazzy/setup.bash   # or your ROS 2 Jazzy install
cd week4.5/tf_ws
python3 tools/tutor.py
```

`tutor.py` builds the package with `colcon`, runs one diagnostic session,
shows you Fleet Ops' scorecard, and -- only for whichever stage is still
failing -- asks a short comprehension question and gives an escalating
hint. It never names a file or line number outright. Fix the code, press
Enter, and it rebuilds and reruns automatically.

`tools/` sits outside `src/`, so `colcon build` never tries to compile
`tutor.py` as a package.

### Running the node by hand

```bash
colcon build --symlink-install --packages-select fleet_tf_lab
source install/setup.bash
./install/fleet_tf_lab/lib/fleet_tf_lab/fleet_tf_lab_node
```

## Requirements

- ROS 2 Jazzy (`rclcpp`, `tf2`, `tf2_ros`, `tf2_geometry_msgs`)
- colcon
- A C++20 compiler
- Python 3 (for `tutor.py`)

## Layout

```
tf_ws/
  src/fleet_tf_lab/          -- the ROS 2 package (colcon-built)
    include/fleet_tf_lab/
      robot_geometry.hpp     -- frame names, route, drift model, sensor mounts
      world_model.hpp        -- independent ground truth + synthetic measurements
      clearance_cache.hpp    -- the reader/writer telemetry cache (bug 4 lives here)
      diagnostics.hpp        -- the ground-truth grader (external tracking rig)
    src/
      main.cpp               -- the node: executor, callback groups, broadcasters,
                                 background driver threads (bugs 1-3 live here)
      robot_geometry.cpp
      world_model.cpp
      diagnostics.cpp
  tools/
    tutor.py                 -- the Fleet Ops tutor (not part of the colcon build)
```
