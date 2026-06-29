cmake_minimum_required(VERSION 3.16)

project(git_merge_lab LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_library(velocity_controller
    src/velocity_controller.cpp
)

target_include_directories(velocity_controller
    PUBLIC include
)

add_executable(test_velocity_controller
    tests/test_velocity_controller.cpp
)

target_link_libraries(test_velocity_controller
    PRIVATE velocity_controller
)

enable_testing()
add_test(NAME velocity_controller_tests COMMAND test_velocity_controller)

