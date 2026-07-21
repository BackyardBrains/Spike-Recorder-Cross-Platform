# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(nwbfile_plugin_library VERSION 0.0.1 LANGUAGES C CXX)

# AqNWB 0.4.0 requires C++17+
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

include_directories(${CMAKE_CURRENT_SOURCE_DIR})

# AqNWB 0.4.0 source list relative to a platform root
set(AQNWB_SOURCES_RELATIVE
    Channel.cpp
    io/BaseIO.cpp
    io/RecordingObjects.cpp
    io/hdf5/HDF5IO.cpp
    io/hdf5/HDF5RecordingData.cpp
    io/hdf5/HDF5ArrayDataSetConfig.cpp
    nwb/NWBFile.cpp
    nwb/RegisteredType.cpp
    nwb/base/NWBData.cpp
    nwb/base/NWBDataInterface.cpp
    nwb/base/NWBContainer.cpp
    nwb/base/ProcessingModule.cpp
    nwb/base/TimeSeries.cpp
    nwb/device/Device.cpp
    nwb/ecephys/ElectricalSeries.cpp
    nwb/ecephys/SpikeEventSeries.cpp
    nwb/event/EventsTable.cpp
    nwb/event/TimestampVectorData.cpp
    nwb/event/DurationVectorData.cpp
    nwb/file/ElectrodeGroup.cpp
    nwb/file/ElectrodesTable.cpp
    nwb/misc/AnnotationSeries.cpp
    nwb/hdmf/base/Container.cpp
    nwb/hdmf/base/Data.cpp
    nwb/hdmf/table/DynamicTable.cpp
    nwb/hdmf/table/MeaningsTable.cpp
    nwb/hdmf/table/VectorData.cpp
    nwb/hdmf/table/ElementIdentifiers.cpp
    spec/NamespaceRegistry.cpp
)

function(nwb_add_sources out_var root)
  set(_srcs "")
  foreach(_rel ${AQNWB_SOURCES_RELATIVE})
    list(APPEND _srcs "${root}/${_rel}")
  endforeach()
  list(APPEND _srcs "${root}/nwbfile_processing_plugin.cpp")
  set(${out_var} "${_srcs}" PARENT_SCOPE)
endfunction()

add_compile_definitions(AQNWB_CXX_STANDARD=17)

if(ANDROID)
  include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/../android/src/main/cpp/src
    ${CMAKE_CURRENT_SOURCE_DIR}/../android/src/main/cpp/include
  )

  set(ANDROID_NDK_ROOT $ENV{ANDROID_NDK_ROOT})
  if(NOT ANDROID_NDK_ROOT)
    set(ANDROID_NDK_ROOT $ENV{ANDROID_NDK_HOME})
  endif()
  if(ANDROID_NDK_ROOT)
    include_directories(
      ${ANDROID_NDK_ROOT}/sources/cxx-stl/llvm-libc++/include
    )
  endif()

  add_compile_definitions(_FORTIFY_SOURCE=0 ANDROID_BUILD=1)

  nwb_add_sources(_plugin_sources
    "${CMAKE_CURRENT_SOURCE_DIR}/../android/src/main/cpp/src")
  add_library(nwbfile_plugin SHARED ${_plugin_sources})

  set_target_properties(nwbfile_plugin PROPERTIES LINK_FLAGS "-static-libstdc++")
  target_link_libraries(nwbfile_plugin
    android
    log
    ${CMAKE_CURRENT_SOURCE_DIR}/../android/src/main/cpp/lib/libhdf5.a
    ${CMAKE_CURRENT_SOURCE_DIR}/../android/src/main/cpp/lib/libhdf5_cpp.a
    ${CMAKE_CURRENT_SOURCE_DIR}/../android/src/main/cpp/lib/libhdf5_hl.a
    ${CMAKE_CURRENT_SOURCE_DIR}/../android/src/main/cpp/lib/libhdf5_hl_cpp.a
    z
    m
  )

elseif(WIN32)
  include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/../windows/src
    ${CMAKE_CURRENT_SOURCE_DIR}/../windows/src/include
    ${CMAKE_CURRENT_SOURCE_DIR}/../windows/src/include/hdf5
  )

  nwb_add_sources(_plugin_sources
    "${CMAKE_CURRENT_SOURCE_DIR}/../windows/src")
  add_library(nwbfile_plugin SHARED ${_plugin_sources})

  # Boost removed in AqNWB 0.4; bcrypt used for UUID helpers.
  target_link_libraries(nwbfile_plugin
    ${CMAKE_CURRENT_SOURCE_DIR}/../windows/src/lib/hdf5.lib
    ${CMAKE_CURRENT_SOURCE_DIR}/../windows/src/lib/hdf5_cpp.lib
    ${CMAKE_CURRENT_SOURCE_DIR}/../windows/src/lib/hdf5_hl.lib
    ${CMAKE_CURRENT_SOURCE_DIR}/../windows/src/lib/hdf5_hl_cpp.lib
    bcrypt
    ws2_32
    iphlpapi
    psapi
  )

elseif(UNIX AND NOT APPLE)
  # Linux — AqNWB sources under linux/src, HDF5 from system
  find_package(HDF5 REQUIRED COMPONENTS CXX)
  find_package(PkgConfig REQUIRED)

  include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/../linux/src
    ${HDF5_INCLUDE_DIRS}
  )

  nwb_add_sources(_plugin_sources
    "${CMAKE_CURRENT_SOURCE_DIR}/../linux/src")
  add_library(nwbfile_plugin SHARED ${_plugin_sources})

  target_link_libraries(nwbfile_plugin
    ${HDF5_CXX_LIBRARIES}
    ${HDF5_LIBRARIES}
    z
    dl
    pthread
  )

else()
  # macOS / iOS use CocoaPods (podspec), not this CMake path.
  # Provide a thin fallback so accidental CMake configures still succeed.
  message(STATUS "nwbfile_plugin: Apple platforms use CocoaPods; building C FFI stub only.")
  add_library(nwbfile_plugin SHARED
    "nwbfile_plugin.c"
  )
endif()

set_target_properties(nwbfile_plugin PROPERTIES
  PUBLIC_HEADER nwbfile_plugin.h
  OUTPUT_NAME "nwbfile_plugin"
)

target_compile_definitions(nwbfile_plugin PUBLIC DART_SHARED_LIB)
