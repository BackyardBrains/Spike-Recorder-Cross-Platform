# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(processing_ffi_library VERSION 0.0.1 LANGUAGES C CXX)

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Include directories
include_directories(.)
include_directories(includes)

add_library(processing_ffi SHARED
  "processing.cpp"
  "AmModulationProcessor.cpp"
  "AnalysisUtils.cpp"
  "AudioFFT.cpp"
  "AutocorrelationAnalysis.cpp"
  "AverageSpikeAnalysis.cpp"
  "CrossCorrelationAnalysis.cpp"
  "DebuggingLogBYB.cpp"
  "dr_wav.cpp"
  "DrawingUtils.cpp"
  "EventTriggeredAverageAnalysis.cpp"
  "EventUtils.cpp"
  "FftProcessor.cpp"
  "FilterBase.cpp"
  "HeartbeatHelper.cpp"
  "HighPassFilter.cpp"
  "IsiAnalysis.cpp"
  "LowPassFilter.cpp"
  "NotchFilter.cpp"
  "Processor.cpp"
  "SampleStreamProcessor.cpp"
  "SampleStreamUtils.cpp"
  "SignalUtils.cpp"
  "SpikeAnalysis.cpp"
  "ThresholdProcessor.cpp"
  "dart_api_dl.c"
  "dart_api_dl.h"
  "dart_api.h"
  "dart_embedder_api.h"
  "dart_native_api.h"
  "dart_tools_api.h"
  "dart_version.h"
)

set_target_properties(processing_ffi PROPERTIES
  PUBLIC_HEADER processing_ffi.h
  OUTPUT_NAME "processing_ffi"
)

target_compile_definitions(processing_ffi PUBLIC DART_SHARED_LIB)

# Link Android logging library
if(ANDROID)
    find_library(log-lib log)
    target_link_libraries(processing_ffi ${log-lib})
endif()
