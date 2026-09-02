cmake_minimum_required(VERSION 3.20)

project(koalasand_native LANGUAGES CXX)

include(CTest)

if(NOT GODOT_CPP_DIR)
    message(FATAL_ERROR "GODOT_CPP_DIR must point to the pinned godot-cpp checkout")
endif()

set(GODOTCPP_API_VERSION "4.7" CACHE STRING "Godot API version" FORCE)
set(GODOTCPP_TARGET "template_release" CACHE STRING "Godot target" FORCE)
set(GODOTCPP_PRECISION "single" CACHE STRING "Godot precision" FORCE)
set(GODOTCPP_ENABLE_TESTING OFF CACHE BOOL "Disable godot-cpp tests" FORCE)

add_subdirectory("${GODOT_CPP_DIR}" godot-cpp)

add_library(koalasand_core STATIC
    core/physical_traits.cpp
    core/fluid_prototype.cpp
    core/parallel_executor.cpp
    core/thermal_prototype.cpp
)
target_include_directories(koalasand_core PUBLIC core)
target_compile_features(koalasand_core PUBLIC cxx_std_20)

add_executable(koalasand_core_probe core/portability_probe.cpp)
target_link_libraries(koalasand_core_probe PRIVATE koalasand_core)

add_executable(koalasand_fluid_benchmark core/fluid_benchmark.cpp)
target_link_libraries(koalasand_fluid_benchmark PRIVATE koalasand_core)

add_executable(koalasand_thermal_benchmark core/thermal_benchmark.cpp)
target_link_libraries(koalasand_thermal_benchmark PRIVATE koalasand_core)

add_library(koalasand_native SHARED
    src/native_sand_world.cpp
    src/native_factory_foundations.cpp
    src/native_automation.cpp
    src/native_physical_processing.cpp
    src/native_pipe_logistics.cpp
    src/native_power.cpp
    src/native_worldgen_v2.cpp
    src/native_worldgen_v5.cpp
    src/native_worldgen_v5_caves.cpp
    src/native_worldgen_v5_report.cpp
    src/native_fluid_prototype.cpp
    src/native_thermal_candidate.cpp
    src/native_thermodynamics.cpp
    src/native_organic_physics.cpp
    src/native_phase13.cpp
    src/register_types.cpp
)

target_include_directories(koalasand_native PRIVATE src)
target_link_libraries(koalasand_native PRIVATE godot-cpp koalasand_core)
target_compile_features(koalasand_native PRIVATE cxx_std_20)

function(koalasand_enable_warnings target)
    if(MSVC)
        target_compile_options(${target} PRIVATE /W4 /permissive-)
    else()
        target_compile_options(${target} PRIVATE -Wall -Wextra -Wshadow)
    endif()
endfunction()

koalasand_enable_warnings(koalasand_core)
koalasand_enable_warnings(koalasand_core_probe)
koalasand_enable_warnings(koalasand_fluid_benchmark)
koalasand_enable_warnings(koalasand_thermal_benchmark)
koalasand_enable_warnings(koalasand_native)
if(NOT MSVC)
    # godot-cpp templates intentionally leave some binding parameters unused.
    target_compile_options(koalasand_native PRIVATE -Wno-unused-parameter -Wno-unused-but-set-parameter)
endif()

if(MSVC)
    target_compile_options(koalasand_native PRIVATE /O2 /DNDEBUG)
else()
    target_compile_options(koalasand_native PRIVATE -O3 -DNDEBUG)
endif()

add_test(NAME koalasand_core_probe COMMAND koalasand_core_probe)

get_target_property(GODOTCPP_SUFFIX godot-cpp GODOTCPP_SUFFIX)
set_target_properties(koalasand_native PROPERTIES
    PREFIX "lib"
    OUTPUT_NAME "koalasand_native${GODOTCPP_SUFFIX}"
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/bin"
    LIBRARY_OUTPUT_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/bin"
)
