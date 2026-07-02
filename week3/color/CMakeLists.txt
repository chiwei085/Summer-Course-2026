cmake_minimum_required(VERSION 3.24)

project(week3_color_notebook LANGUAGES C CXX)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

find_package(Threads REQUIRED)

add_library(mongoose STATIC third_party/mongoose/mongoose.c)
target_include_directories(mongoose PUBLIC third_party/mongoose)
target_compile_definitions(mongoose PUBLIC MG_ENABLE_LINES=1)

add_library(color_core
  src/image.cpp
  src/color.cpp
  src/histogram.cpp
  src/server.cpp
  src/api.cpp)

target_include_directories(color_core
  PUBLIC ${CMAKE_CURRENT_SOURCE_DIR}/include
  PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/third_party/stb
    ${CMAKE_CURRENT_SOURCE_DIR}/third_party)

target_link_libraries(color_core PUBLIC mongoose PRIVATE Threads::Threads)

target_compile_options(color_core PRIVATE
  $<$<CXX_COMPILER_ID:Clang,GNU>:-Wall -Wextra -Wpedantic>)

add_executable(color_notebook src/main.cpp)
target_link_libraries(color_notebook PRIVATE color_core)

find_program(CLANG_FORMAT_EXECUTABLE clang-format)
file(GLOB_RECURSE FORMAT_SOURCES
  ${CMAKE_CURRENT_SOURCE_DIR}/include/week3/color/*.hpp
  ${CMAKE_CURRENT_SOURCE_DIR}/src/*.cpp)

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
