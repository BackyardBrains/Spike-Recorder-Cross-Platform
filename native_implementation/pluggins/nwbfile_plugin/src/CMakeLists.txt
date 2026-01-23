# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(nwbfile_plugin_library VERSION 0.0.1 LANGUAGES C CXX)

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Find required packages
# find_package(PkgConfig REQUIRED)
if (NOT WIN32)
    find_package(PkgConfig REQUIRED)
endif()

# Set include directories
include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}
)

# Platform-specific include directories
if(ANDROID)
    include_directories(
        ${CMAKE_CURRENT_SOURCE_DIR}/../android/src/main/cpp/src
        ${CMAKE_CURRENT_SOURCE_DIR}/../android/src/main/cpp/boost
        ${CMAKE_CURRENT_SOURCE_DIR}/../android/src/main/cpp/include
    )
elseif(WIN32)
    include_directories(
        ${CMAKE_CURRENT_SOURCE_DIR}/../windows/src
        ${CMAKE_CURRENT_SOURCE_DIR}/../android/src/main/cpp/src
        ${CMAKE_CURRENT_SOURCE_DIR}/../android/src/main/cpp/boost
        ${CMAKE_CURRENT_SOURCE_DIR}/../windows/src/include
        ${CMAKE_CURRENT_SOURCE_DIR}/../windows/src/include/hdf5
        ${CMAKE_CURRENT_SOURCE_DIR}/../windows/src/include/boost
    )
else()
    include_directories(
        ${CMAKE_CURRENT_SOURCE_DIR}/../macos/Classes/src
        ${CMAKE_CURRENT_SOURCE_DIR}/../macos/Classes/boost
        ${CMAKE_CURRENT_SOURCE_DIR}/../macos/Classes/include
    )
endif()

# Platform-specific configuration
if(ANDROID)
    # Android-specific settings
    set(ANDROID_NDK_ROOT $ENV{ANDROID_NDK_ROOT})
    if(NOT ANDROID_NDK_ROOT)
        set(ANDROID_NDK_ROOT $ENV{ANDROID_NDK_HOME})
    endif()
    
    # Add Android NDK include paths
    include_directories(
        ${ANDROID_NDK_ROOT}/sources/cxx-stl/llvm-libc++/include
        ${ANDROID_NDK_ROOT}/toolchains/llvm/prebuilt/linux-x86_64/sysroot/usr/include
    )
    
    # Disable fortified source to avoid missing __*_chk functions
    add_compile_definitions(_FORTIFY_SOURCE=0)
    
    # Use the full C++ implementation for Android (same as iOS)
    add_library(nwbfile_plugin SHARED
        "../android/src/main/cpp/src/nwbfile_processing_plugin.cpp"
        "../android/src/main/cpp/src/Channel.cpp"
        "../android/src/main/cpp/src/io/BaseIO.cpp"
        "../android/src/main/cpp/src/nwb/NWBFile.cpp"
        "../android/src/main/cpp/src/nwb/RecordingContainers.cpp"
        "../android/src/main/cpp/src/nwb/RegisteredType.cpp"
        "../android/src/main/cpp/src/nwb/base/TimeSeries.cpp"
        "../android/src/main/cpp/src/nwb/device/Device.cpp"
        "../android/src/main/cpp/src/nwb/ecephys/ElectricalSeries.cpp"
        "../android/src/main/cpp/src/nwb/ecephys/SpikeEventSeries.cpp"
        "../android/src/main/cpp/src/nwb/file/ElectrodeGroup.cpp"
        "../android/src/main/cpp/src/nwb/file/ElectrodeTable.cpp"
        # "../android/src/main/cpp/src/nwb/file/ElectrodesTable.cpp"
        "../android/src/main/cpp/src/nwb/hdmf/base/Container.cpp"
        "../android/src/main/cpp/src/nwb/hdmf/base/Data.cpp"
        "../android/src/main/cpp/src/nwb/hdmf/table/DynamicTable.cpp"
        "../android/src/main/cpp/src/nwb/hdmf/table/ElementIdentifiers.cpp"
        "../android/src/main/cpp/src/nwb/hdmf/table/VectorData.cpp"
        "../android/src/main/cpp/src/nwb/misc/AnnotationSeries.cpp"
        "../android/src/main/cpp/src/io/hdf5/HDF5IO.cpp"
        "../android/src/main/cpp/src/io/hdf5/HDF5ArrayDataSetConfig.cpp"
        "../android/src/main/cpp/src/io/hdf5/HDF5RecordingData.cpp"
    )
elseif(WIN32)
    # Windows platform uses its own CMakeLists.txt in windows/ directory
    # This is handled by windows/CMakeLists.txt which is called from the plugin's windows/CMakeLists.txt
    # No need to build here - the windows/CMakeLists.txt handles everything
    message(STATUS "Windows build is handled by windows/CMakeLists.txt")
else()
    # Non-Android platforms can use the full C++ implementation
    # This will be expanded later when we add HDF5/Boost for Android
    add_library(nwbfile_plugin SHARED
        "nwbfile_plugin.c"
    )
endif()

set_target_properties(nwbfile_plugin PROPERTIES
    PUBLIC_HEADER nwbfile_plugin.h
    OUTPUT_NAME "nwbfile_plugin"
)

target_compile_definitions(nwbfile_plugin PUBLIC DART_SHARED_LIB)

# Link libraries
if(ANDROID)
    # Add Android-specific compile definitions
    target_compile_definitions(nwbfile_plugin PRIVATE ANDROID_BUILD=1)
    
    # Use static C++ standard library to avoid runtime dependency
    # Add 16KB page size compatibility for Android devices with 16KB pages
    # This is required for devices like Pixel 9, Pixel 9 Pro, and future devices
    set_target_properties(nwbfile_plugin PROPERTIES
        LINK_FLAGS "-static-libstdc++ -Wl,-z,max-page-size=16384"
    )
    
    # Add library search path for Android
    link_directories(${CMAKE_CURRENT_SOURCE_DIR}/../android/src/main/cpp/lib)
    
    # Android-specific libraries with HDF5
    target_link_libraries(nwbfile_plugin
        android
        log
        # HDF5 libraries (C and C++ interfaces)
        ${CMAKE_CURRENT_SOURCE_DIR}/../android/src/main/cpp/lib/libhdf5.a
        ${CMAKE_CURRENT_SOURCE_DIR}/../android/src/main/cpp/lib/libhdf5_cpp.a
        ${CMAKE_CURRENT_SOURCE_DIR}/../android/src/main/cpp/lib/libhdf5_hl.a
        ${CMAKE_CURRENT_SOURCE_DIR}/../android/src/main/cpp/lib/libhdf5_hl_cpp.a
        # Standard libraries (use static linking to avoid runtime dependencies)
        z
        c
        m
    )
elseif(WIN32)
    # Windows platform uses its own CMakeLists.txt in windows/ directory
    # Linking is handled by windows/CMakeLists.txt
    message(STATUS "Windows linking is handled by windows/CMakeLists.txt")
else()
    # Other platforms can link additional libraries here
    # target_link_libraries(nwbfile_plugin ...)
endif()
