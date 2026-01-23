# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "nwbfile_plugin")
project(${PROJECT_NAME} LANGUAGES CXX)

# Set CMake policy to ensure MSVC_RUNTIME_LIBRARY property is respected
if(POLICY CMP0091)
    cmake_policy(SET CMP0091 NEW)
endif()

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Set include directories for Windows
include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/src/io
    ${CMAKE_CURRENT_SOURCE_DIR}/src/io/hdf5
    ${CMAKE_CURRENT_SOURCE_DIR}/src/nwb
    ${CMAKE_CURRENT_SOURCE_DIR}/src/include
    "C:/Users/p/Downloads/boost_1_88_0/boost_1_88_0"
)

# Set library directories
link_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/src/lib
)

# Add all aqnwb source files that actually exist
set(AQNWB_SOURCES
    src/Channel.cpp
    src/nwb/NWBFile.cpp
    src/nwb/RecordingContainers.cpp
    src/nwb/RegisteredType.cpp
    src/nwb/base/TimeSeries.cpp
    src/nwb/ecephys/ElectricalSeries.cpp
    src/nwb/ecephys/SpikeEventSeries.cpp
    src/nwb/device/Device.cpp
    src/nwb/hdmf/table/DynamicTable.cpp
    src/nwb/hdmf/table/VectorData.cpp
    src/nwb/hdmf/table/ElementIdentifiers.cpp
    src/nwb/hdmf/base/Data.cpp
    src/nwb/hdmf/base/Container.cpp
    src/nwb/file/ElectrodeTable.cpp
    src/nwb/file/ElectrodeGroup.cpp
    src/nwb/misc/AnnotationSeries.cpp
    src/io/BaseIO.cpp
    src/io/hdf5/HDF5IO.cpp
    src/io/hdf5/HDF5RecordingData.cpp
    src/io/hdf5/HDF5ArrayDataSetConfig.cpp
)

# First, create the aqnwb static library
add_library(aqnwb STATIC ${AQNWB_SOURCES})

# Set target properties for aqnwb library
set_target_properties(aqnwb PROPERTIES
    OUTPUT_NAME "aqnwb"
    # Force Release runtime library for all configurations (to match HDF5 libraries)
    MSVC_RUNTIME_LIBRARY "MultiThreadedDLL"
)

# Add compile definitions for aqnwb library
target_compile_definitions(aqnwb 
    PRIVATE WIN32_BUILD=1
    PRIVATE _CRT_SECURE_NO_WARNINGS
    PRIVATE NOMINMAX
    PRIVATE WIN32_LEAN_AND_MEAN
    PRIVATE _ITERATOR_DEBUG_LEVEL=0
)

# Override Debug flags to force Release runtime (/MD instead of /MDd)
# This removes /MDd and /RTC1 that are added by default in Debug
target_compile_options(aqnwb PRIVATE
    $<$<AND:$<CXX_COMPILER_ID:MSVC>,$<CONFIG:Debug>>:/MD>
    $<$<AND:$<CXX_COMPILER_ID:MSVC>,$<CONFIG:Debug>>:/D_ITERATOR_DEBUG_LEVEL=0>
)
# Remove Debug-specific runtime checks that require Debug runtime
target_compile_options(aqnwb PRIVATE
    $<$<AND:$<CXX_COMPILER_ID:MSVC>,$<CONFIG:Debug>>:/wd4996>
)

# Link HDF5 libraries to aqnwb library (using correct library names)
target_link_libraries(aqnwb
    ${CMAKE_CURRENT_SOURCE_DIR}/src/lib/libhdf5.lib
    ${CMAKE_CURRENT_SOURCE_DIR}/src/lib/libhdf5_cpp.lib
    ${CMAKE_CURRENT_SOURCE_DIR}/src/lib/libhdf5_hl.lib
    ${CMAKE_CURRENT_SOURCE_DIR}/src/lib/libhdf5_hl_cpp.lib
    ${CMAKE_CURRENT_SOURCE_DIR}/src/lib/libszaec.lib
    ${CMAKE_CURRENT_SOURCE_DIR}/src/lib/libaec.lib
    ${CMAKE_CURRENT_SOURCE_DIR}/src/lib/zlib-static.lib
    shlwapi
)

# Create the shared library with the plugin source
add_library(nwbfile_plugin SHARED
    src/nwbfile_processing_plugin.cpp
)

# Set target properties
set_target_properties(nwbfile_plugin PROPERTIES
    OUTPUT_NAME "nwbfile_plugin"
    # Force Release runtime library for all configurations (to match HDF5 libraries)
    MSVC_RUNTIME_LIBRARY "MultiThreadedDLL"
)

# Add compile definitions
target_compile_definitions(nwbfile_plugin 
    PUBLIC DART_SHARED_LIB
    PRIVATE WIN32_BUILD=1
    PRIVATE _CRT_SECURE_NO_WARNINGS
    PRIVATE NOMINMAX
    PRIVATE WIN32_LEAN_AND_MEAN
    PRIVATE _ITERATOR_DEBUG_LEVEL=0
)

# Override Debug flags to force Release runtime (/MD instead of /MDd)
# This removes /MDd and /RTC1 that are added by default in Debug
target_compile_options(nwbfile_plugin PRIVATE
    $<$<AND:$<CXX_COMPILER_ID:MSVC>,$<CONFIG:Debug>>:/MD>
    $<$<AND:$<CXX_COMPILER_ID:MSVC>,$<CONFIG:Debug>>:/D_ITERATOR_DEBUG_LEVEL=0>
)
# Remove Debug-specific runtime checks that require Debug runtime
target_compile_options(nwbfile_plugin PRIVATE
    $<$<AND:$<CXX_COMPILER_ID:MSVC>,$<CONFIG:Debug>>:/wd4996>
)

# Link Windows system libraries and the aqnwb library
target_link_libraries(nwbfile_plugin
    # Windows system libraries
    ws2_32
    iphlpapi
    psapi
    # Our aqnwb library
    aqnwb
)

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
set(nwbfile_plugin_bundled_libraries
  $<TARGET_FILE:nwbfile_plugin>
  PARENT_SCOPE
)
