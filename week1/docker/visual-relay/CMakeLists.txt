cmake_minimum_required(VERSION 3.24)

project(visual_relay LANGUAGES CXX)

option(VISUAL_RELAY_BUILD_APPS "Build simulator/scout/catcher executables" ON)
option(VISUAL_RELAY_BUILD_TESTS "Build protocol and service tests" ON)
option(VISUAL_RELAY_REQUIRE_GUI "Require SDL3 GUI support for workstation apps" ON)
option(VISUAL_RELAY_BUILD_SIMULATOR "Build relay-simulator" ON)
option(VISUAL_RELAY_BUILD_SCOUT "Build scout-station" ON)
option(VISUAL_RELAY_BUILD_CATCHER "Build catcher-station" ON)

set(CMAKE_EXPORT_COMPILE_COMMANDS ON)
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

add_library(visual_relay_protocol
    src/protocol/protocol.cpp
)
target_include_directories(visual_relay_protocol PUBLIC include)
target_compile_options(visual_relay_protocol PRIVATE -Wall -Wextra -Wpedantic)

if(VISUAL_RELAY_BUILD_APPS)
    find_package(Threads REQUIRED)

    add_library(visual_relay_common
        src/common/service.cpp
    )
    target_include_directories(visual_relay_common PUBLIC include)
    target_link_libraries(visual_relay_common PUBLIC visual_relay_protocol)
    target_compile_options(visual_relay_common PRIVATE -Wall -Wextra -Wpedantic)

    if(VISUAL_RELAY_BUILD_SCOUT OR VISUAL_RELAY_BUILD_CATCHER)
        find_package(SDL3 QUIET CONFIG)
        if(VISUAL_RELAY_REQUIRE_GUI AND NOT SDL3_FOUND)
            message(FATAL_ERROR "SDL3 is required for Visual Relay GUI apps. Build through Docker or set VISUAL_RELAY_REQUIRE_GUI=OFF for protocol-only local checks.")
        endif()
        add_library(visual_relay_gui src/common/gui.cpp)
        target_include_directories(visual_relay_gui PUBLIC include)
        target_compile_options(visual_relay_gui PRIVATE -Wall -Wextra -Wpedantic)
        if(SDL3_FOUND)
            target_compile_definitions(visual_relay_gui PUBLIC VISUAL_RELAY_HAS_SDL3=1)
            target_link_libraries(visual_relay_gui PUBLIC SDL3::SDL3)
        endif()
    endif()

    function(add_visual_relay_service target output source)
        add_executable(${target} ${source})
        target_link_libraries(${target} PRIVATE visual_relay_common Threads::Threads)
        target_compile_options(${target} PRIVATE -Wall -Wextra -Wpedantic)
        set_target_properties(${target} PROPERTIES OUTPUT_NAME ${output})
        install(TARGETS ${target} RUNTIME DESTINATION bin)
    endfunction()

    if(VISUAL_RELAY_BUILD_SIMULATOR)
        add_visual_relay_service(relay_simulator relay-simulator src/relay_simulator/relay_simulator.cpp)
    endif()
    if(VISUAL_RELAY_BUILD_SCOUT)
        add_visual_relay_service(scout_station scout-station src/scout_station/scout_station.cpp)
        target_link_libraries(scout_station PRIVATE visual_relay_gui)
    endif()
    if(VISUAL_RELAY_BUILD_CATCHER)
        add_visual_relay_service(catcher_station catcher-station src/catcher_station/catcher_station.cpp)
        target_link_libraries(catcher_station PRIVATE visual_relay_gui)
    endif()
endif()

if(VISUAL_RELAY_BUILD_TESTS)
    enable_testing()
    add_executable(test_protocol tests/test_protocol.cpp)
    target_link_libraries(test_protocol PRIVATE visual_relay_protocol)
    target_compile_options(test_protocol PRIVATE -Wall -Wextra -Wpedantic)
    add_test(NAME protocol COMMAND test_protocol)
endif()

install(DIRECTORY assets/ DESTINATION share/visual-relay/assets)
