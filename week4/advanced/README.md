# Week 4 Advanced: Robot Arm Cube Pick-and-Place

This exercise uses C++20, Conan 2, CMake, Ninja, Sophus, and Eigen to build a
small robot-arm pick-and-place simulation. A fixed-base UR5-style 6R arm tracks
scene-defined end-effector SE(3) targets, closes its gripper on a table-top
cube, lifts it, transfers it, places it, and retreats.

Core concepts:

- `Sophus::SE3d` represents each tool target pose.
- UR5-style Denavit-Hartenberg parameters define fixed link geometry.
- A geometric spatial Jacobian maps joint velocity into tool linear and angular
  velocity.
- Damped least-squares inverse kinematics turns SE(3) pose error into joint
  velocity commands.
- A light posture-bias term keeps the arm near an elbow-up industrial-arm shape
  while still prioritizing tool pose tracking.

## Build and Run

This exercise is independent from `week4/basic` and uses Conan 2 to manage
Sophus and Eigen.

```bash
conan profile detect --force
conan install . --output-folder=build --build=missing -s build_type=Release -s compiler.cppstd=20
cmake -S . -B build -G Ninja -DCMAKE_TOOLCHAIN_FILE=build/conan_toolchain.cmake -DCMAKE_BUILD_TYPE=Release
cmake --build build
./build/robot_arm_pick_place
```

## What to Observe

The program prints the convergence status for each task stage:

- `home`
- `pre-grasp`
- `grasp`
- `lift`
- `transfer`
- `place`
- `release`
- `retreat`

The program also generates `trajectory.html`, which shows the UR5-style fixed
links, base, wrist, gripper state, table, source/destination pads, cube motion,
target marker, tool trace, joint-limit warning state, and SE(3) error chart.
