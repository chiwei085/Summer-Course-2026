cmake_minimum_required(VERSION 3.24)

project(week4_advanced_robot_arm LANGUAGES CXX)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(Sophus REQUIRED CONFIG)
find_package(Eigen3 REQUIRED CONFIG)

add_executable(robot_arm_pick_place src/main.cpp)
target_include_directories(robot_arm_pick_place PRIVATE include)
target_link_libraries(robot_arm_pick_place PRIVATE Eigen3::Eigen)

if(TARGET Sophus::Sophus)
  target_link_libraries(robot_arm_pick_place PRIVATE Sophus::Sophus)
elseif(TARGET sophus::sophus)
  target_link_libraries(robot_arm_pick_place PRIVATE sophus::sophus)
elseif(TARGET Sophus::sophus)
  target_link_libraries(robot_arm_pick_place PRIVATE Sophus::sophus)
else()
  message(FATAL_ERROR "Conan generated Sophus package, but no known Sophus CMake target was found.")
endif()

find_program(CLANG_FORMAT_EXECUTABLE clang-format)
set(FORMAT_SOURCES
    src/main.cpp
    include/arm_model.hpp
    include/kinematics_control.hpp
    include/task_execution.hpp
    include/html_plot.hpp
    include/trajectory_diagnostics.hpp
    include/physical_checks.hpp
    include/render_checks.hpp)

if(CLANG_FORMAT_EXECUTABLE)
  add_custom_target(
    format
    COMMAND ${CLANG_FORMAT_EXECUTABLE} -i ${FORMAT_SOURCES}
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    COMMENT "Formatting C++ sources with clang-format")

  add_custom_target(
    format-check
    COMMAND ${CLANG_FORMAT_EXECUTABLE} --dry-run --Werror ${FORMAT_SOURCES}
    WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
    COMMENT "Checking C++ source formatting")
else()
  message(STATUS "clang-format not found; format targets will not be available")
endif()
