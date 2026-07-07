cmake_minimum_required(VERSION 3.16)
project(fleet_tf_lab CXX)

if(NOT CMAKE_CXX_STANDARD)
  set(CMAKE_CXX_STANDARD 20)
  set(CMAKE_CXX_STANDARD_REQUIRED ON)
  set(CMAKE_CXX_EXTENSIONS OFF)
endif()

if(NOT CMAKE_BUILD_TYPE)
  set(CMAKE_BUILD_TYPE Release)
endif()

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

find_package(ament_cmake REQUIRED)
find_package(rclcpp REQUIRED)
find_package(tf2 REQUIRED)
find_package(tf2_ros REQUIRED)
find_package(tf2_geometry_msgs REQUIRED)
find_package(geometry_msgs REQUIRED)

add_executable(fleet_tf_lab_node
  src/main.cpp
  src/robot_geometry.cpp
  src/world_model.cpp
  src/diagnostics.cpp
)

target_include_directories(fleet_tf_lab_node PRIVATE
  $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
)

target_compile_options(fleet_tf_lab_node PRIVATE -Wall -Wextra)

ament_target_dependencies(fleet_tf_lab_node
  rclcpp
  tf2
  tf2_ros
  tf2_geometry_msgs
  geometry_msgs
)

install(TARGETS fleet_tf_lab_node
  DESTINATION lib/${PROJECT_NAME}
)

ament_package()
