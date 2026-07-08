FROM ros:jazzy

# ros:jazzy is the ros base variant plus ros dev tools: it already ships
# colcon, CMake, GCC 13 (C++20), rosdep, and the core tf2 stack. The lab is
# headless (no rviz/Gazebo), so only add what it actually links against,
# gdb for the concurrency debugging stages, and clangd/clang-format so the
# workspace's .clangd/.clang-format work from any editor, including editors
# that download their own language server binaries.
RUN apt-get update && apt-get install -y --no-install-recommends \
        ros-jazzy-tf2-geometry-msgs \
        gdb \
        clangd \
        clang-format \
    && rm -rf /var/lib/apt/lists/*

# Editor terminals are plain interactive bash and skip the image's ROS
# entrypoint, so source the underlay for every shell.
RUN echo 'source /opt/ros/jazzy/setup.bash' >> /etc/bash.bashrc

# rclcpp aborts at startup if it can't create $HOME/.ros/log. With plain
# `docker run -u $(id -u)` the uid has no home dir, so keep ROS state
# somewhere always writable instead.
ENV ROS_HOME=/tmp/ros
