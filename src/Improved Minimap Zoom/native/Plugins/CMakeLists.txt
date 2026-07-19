cmake_minimum_required(VERSION 3.15)
project(ImprovedMinimapZoomNative LANGUAGES CXX)

# -----------------------
# Compiler / build basics
# -----------------------
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)

# Default to Release for single-config generators
if (NOT CMAKE_CONFIGURATION_TYPES)
    if (NOT DEFINED CMAKE_BUILD_TYPE)
        set(CMAKE_BUILD_TYPE "Release" CACHE STRING "Choose the type of build." FORCE)
    endif()
endif()

# Prefer x64; allow override from CLI or GUI
if (NOT DEFINED CMAKE_GENERATOR_PLATFORM)
    set(CMAKE_GENERATOR_PLATFORM "x64" CACHE STRING "Generator platform")
endif()

# -----------------------
# Plugin identity and sources
# -----------------------
# Target name is the DLL base name we want to produce.
set(TARGET_NAME "ImprovedMinimapZoom_Native")
# Deployed folder name under red4ext/plugins — matches the r6 scripts folder
set(PLUGIN_NAME "ImprovedMinimapZoom")
set(SOURCES
    "${CMAKE_CURRENT_SOURCE_DIR}/Main.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/Log.cpp"
    "${CMAKE_CURRENT_SOURCE_DIR}/MinimapDump.cpp"
)

add_library(${TARGET_NAME} SHARED ${SOURCES})

# -----------------------
# Per-config LOG_DEBUG control
# -----------------------
target_compile_definitions(${TARGET_NAME}
    PRIVATE
        $<$<OR:$<CONFIG:Debug>,$<CONFIG:RelWithDebInfo>>:LOG_DEBUG=1>
        $<$<OR:$<CONFIG:Release>,$<CONFIG:MinSizeRel>>:LOG_DEBUG=0>
)

# -----------------------
# RED4ext SDK location
# -----------------------
# Fetched at configure time (into the git-ignored build folder), pinned to
# https://github.com/Sekers/RED4ext.SDK commit 046877f9
# (SDK-Release-CyberPunk2077-1.63-HF1). RED4ext 1.15.0 requires a plugin built
# against SDK 0.3.0–0.4.0; newer SDK checkouts also describe post-1.63 struct
# layouts — do NOT bump this pin. Set RED4EXT_SDK_DIR to use a local checkout
# instead (skips the download).
set(RED4EXT_SDK_DIR "" CACHE PATH "Optional path to a local RED4ext SDK include folder")

if (RED4EXT_SDK_DIR STREQUAL "")
    include(FetchContent)
    FetchContent_Declare(
        RED4extSDK
        GIT_REPOSITORY https://github.com/Sekers/RED4ext.SDK.git
        GIT_TAG 046877f9d9e31662033307dec9d6e5b9c055adb6 # SDK-Release-CyberPunk2077-1.63-HF1
        SOURCE_SUBDIR "cmake-subdir-disabled" # header-only use; skip the SDK's own CMakeLists
    )
    FetchContent_MakeAvailable(RED4extSDK)
    set(RED4EXT_SDK_DIR "${red4extsdk_SOURCE_DIR}/include")
endif()

if (NOT EXISTS "${RED4EXT_SDK_DIR}")
    message(FATAL_ERROR "RED4ext SDK not found at: ${RED4EXT_SDK_DIR}\nSet RED4EXT_SDK_DIR to the correct SDK path.")
endif()

target_include_directories(${TARGET_NAME}
    PRIVATE
        "${CMAKE_SOURCE_DIR}"
        "${RED4EXT_SDK_DIR}"
        "${CMAKE_CURRENT_SOURCE_DIR}"
)

# -----------------------
# Ensure MSVC actually uses C++20
# -----------------------
target_compile_options(${TARGET_NAME}
    PRIVATE
        $<$<CXX_COMPILER_ID:MSVC>:/std:c++20>
)

# -----------------------
# Release optimization and linker flags
# -----------------------
target_compile_options(${TARGET_NAME} PRIVATE
    $<$<AND:$<CXX_COMPILER_ID:MSVC>,$<OR:$<CONFIG:Release>,$<CONFIG:MinSizeRel>>>:/O2 /GL /Gy>
    $<$<AND:$<CXX_COMPILER_ID:MSVC>,$<CONFIG:RelWithDebInfo>>:/O2 /Gy>
)

target_link_options(${TARGET_NAME} PRIVATE
    $<$<AND:$<CXX_COMPILER_ID:MSVC>,$<OR:$<CONFIG:Release>,$<CONFIG:MinSizeRel>>>:/LTCG /OPT:REF /OPT:ICF /INCREMENTAL:NO>
)

# -----------------------
# Reduce Windows header noise
# -----------------------
target_compile_definitions(${TARGET_NAME} PRIVATE WIN32_LEAN_AND_MEAN)

# -----------------------
# Output layout
# -----------------------
set_target_properties(${TARGET_NAME} PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
    RUNTIME_OUTPUT_DIRECTORY_RELEASE "${CMAKE_BINARY_DIR}/bin"
)

set(PLUGIN_MODULE_DIR "${CMAKE_SOURCE_DIR}/Module/red4ext/plugins/${PLUGIN_NAME}" CACHE PATH "Module publish folder for plugin")
set(BUILD_LIB_DIR "${CMAKE_BINARY_DIR}/lib")
set(SYMBOLS_DIR "${CMAKE_BINARY_DIR}/symbols")

set_target_properties(${TARGET_NAME} PROPERTIES
    ARCHIVE_OUTPUT_DIRECTORY "${BUILD_LIB_DIR}"
    PDB_OUTPUT_DIRECTORY "${SYMBOLS_DIR}"
)

foreach(cfg IN ITEMS Debug Release RelWithDebInfo MinSizeRel)
    set_target_properties(${TARGET_NAME} PROPERTIES
        ARCHIVE_OUTPUT_DIRECTORY_${cfg} "${BUILD_LIB_DIR}"
        PDB_OUTPUT_DIRECTORY_${cfg} "${SYMBOLS_DIR}"
    )
endforeach()

# -----------------------
# Post-build copy to the Module publish folder
# -----------------------
add_custom_command(TARGET ${TARGET_NAME} POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E make_directory "${PLUGIN_MODULE_DIR}"
    COMMAND ${CMAKE_COMMAND} -E copy_if_different
        "$<TARGET_FILE:${TARGET_NAME}>"
        "${PLUGIN_MODULE_DIR}/$<TARGET_FILE_NAME:${TARGET_NAME}>"
)

# -----------------------
# MSVC runtime selection (dynamic CRT)
# -----------------------
if (MSVC)
    set_property(TARGET ${TARGET_NAME} PROPERTY
        MSVC_RUNTIME_LIBRARY
        $<$<CONFIG:Debug>:MultiThreadedDebugDLL>$<$<NOT:$<CONFIG:Debug>>:MultiThreadedDLL>
    )
endif()

# -----------------------
# Emit PDBs for Release (MSVC)
# -----------------------
if (MSVC)
    target_compile_options(${TARGET_NAME} PRIVATE
        $<$<CONFIG:Release>:/Zi>
        $<$<CONFIG:RelWithDebInfo>:/Zi>
    )
    target_link_options(${TARGET_NAME} PRIVATE
        $<$<CONFIG:Release>:/DEBUG>
        $<$<CONFIG:RelWithDebInfo>:/DEBUG>
    )
endif()

message(STATUS "Using RED4ext SDK directory: ${RED4EXT_SDK_DIR}")
message(STATUS "Plugin module directory (publish): ${PLUGIN_MODULE_DIR}")
