cmake_minimum_required(VERSION 3.24)

project(week3_camera_calibration_lab LANGUAGES C CXX)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(Threads REQUIRED)

add_library(camera_calibration_core
  src/calibration.cpp
  src/dataset.cpp
  src/image.cpp
  src/linalg.cpp)

target_include_directories(camera_calibration_core
  PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include
  PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/third_party/stb)

target_compile_options(camera_calibration_core PRIVATE
  $<$<CXX_COMPILER_ID:Clang,GNU>:-Wall -Wextra -Wpedantic>)

add_executable(calibrate_camera src/main.cpp)
target_link_libraries(calibrate_camera PRIVATE camera_calibration_core)

add_library(mongoose STATIC third_party/mongoose/mongoose.c)
target_include_directories(mongoose PUBLIC third_party/mongoose)
target_compile_definitions(mongoose PUBLIC MG_ENABLE_LINES=1)

add_library(calibration_web
  src/server.cpp
  src/api.cpp)

target_include_directories(calibration_web
  PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include
  PRIVATE ${CMAKE_CURRENT_SOURCE_DIR}/third_party)

target_link_libraries(calibration_web
  PUBLIC camera_calibration_core mongoose
  PRIVATE Threads::Threads)

target_compile_options(calibration_web PRIVATE
  $<$<CXX_COMPILER_ID:Clang,GNU>:-Wall -Wextra -Wpedantic>)

add_executable(calibration_notebook src/notebook_main.cpp)
target_link_libraries(calibration_notebook PRIVATE calibration_web)

find_program(CLANG_FORMAT_EXECUTABLE clang-format)
set(FORMAT_SOURCES
  include/week3/calibration/api.hpp
  include/week3/calibration/calibration.hpp
  include/week3/calibration/dataset.hpp
  include/week3/calibration/image.hpp
  include/week3/calibration/linalg.hpp
  include/week3/calibration/result.hpp
  include/week3/calibration/server.hpp
  src/api.cpp
  src/calibration.cpp
  src/dataset.cpp
  src/image.cpp
  src/linalg.cpp
  src/main.cpp
  src/notebook_main.cpp
  src/server.cpp)

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
