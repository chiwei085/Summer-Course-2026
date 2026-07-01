# Week 4 Basic: Sophus SE(3) Closed-Loop Control

This exercise uses C++20, Conan 2, CMake, and Sophus to build a small drone pose-tracking simulation. The program makes the drone follow a closed-loop trajectory in 3D space and eventually return to its starting pose.

Core concepts:

- `Sophus::SE3d` represents the position and orientation of a rigid body in 3D space.
- `world_T_drone.inverse() * world_T_goal` computes the target error expressed in the body frame.
- `log()` converts the SE(3) error into a 6D tangent vector, also known as the twist error.
- `exp(twist * dt)` integrates the velocity command back onto SE(3) and updates the drone pose.

Sophus arranges an SE(3) tangent vector as `[upsilon, omega]`:

- `upsilon` is the 3D translational error.
- `omega` is the 3D rotational error.

## Build and Run

This exercise uses Conan 2 to manage Sophus and Eigen.

```bash
conan profile detect --force
conan install . --output-folder=build --build=missing -s build_type=Release -s compiler.cppstd=20
cmake -S . -B build -G Ninja -DCMAKE_TOOLCHAIN_FILE=build/conan_toolchain.cmake -DCMAKE_BUILD_TYPE=Release
cmake --build build
./build/closed_loop_se3
```

## What to Observe

The program prints the convergence status for each waypoint in the terminal:

- Waypoint index and name
- Number of steps and simulated time
- Translation error
- Rotation error

When the loop is closed successfully, the final closure error should be below:

- Translation error: `0.05 m`
- Rotation error: `0.05 rad`

The program also generates a `trajectory.html` file.
