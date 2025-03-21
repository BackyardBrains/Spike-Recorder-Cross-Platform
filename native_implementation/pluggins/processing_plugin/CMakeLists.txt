cmake_minimum_required(VERSION 3.10)

project(processing_library VERSION 0.0.1 LANGUAGES CXX)

# Set C++ standard
set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

if(POLICY CMP0079)
  cmake_policy(SET CMP0079 NEW)
endif()

# Set system version for Windows
if(WIN32)
    set(CMAKE_SYSTEM_VERSION 10.0.22621.0)
endif()

# Create a list of source files
set(SOURCE_FILES
    src/DebuggingLogBYB.cpp
    src/processing.cpp
    src/dr_wav.cpp
    src/Processor.cpp
    src/SignalUtils.cpp
    src/SpikeAnalysis.cpp
    src/ThresholdProcessor.cpp
    src/HeartbeatHelper.cpp
    src/HighPassFilter.cpp
    src/IsiAnalysis.cpp
    src/LowPassFilter.cpp
    src/NotchFilter.cpp
    src/SampleStreamProcessor.cpp
    src/SampleStreamUtils.cpp
    src/AudioFFT.cpp
    src/AutocorrelationAnalysis.cpp
    src/AverageSpikeAnalysis.cpp
    src/CrossCorrelationAnalysis.cpp
    src/DrawingUtils.cpp
    src/EventTriggeredAverageAnalysis.cpp
    src/EventUtils.cpp
    src/FftProcessor.cpp
    src/FilterBase.cpp
    src/AmModulationProcessor.cpp
    src/AnalysisUtils.cpp
)

# Create shared library
add_library(processing SHARED ${SOURCE_FILES})
target_compile_definitions(processing PUBLIC DART_SHARED_LIB)

# Platform specific configurations
if(WIN32)
    # Windows specific settings
    set_target_properties(processing PROPERTIES
        PREFIX ""  # No 'lib' prefix on Windows
        OUTPUT_NAME "processing"
        SUFFIX ".dll"
    )
    
    # Windows specific libraries
    target_link_libraries(processing PRIVATE 
        ole32
        oleaut32
    )
elseif(APPLE)
    # macOS specific settings
    set_target_properties(processing PROPERTIES
        PREFIX "lib"
        OUTPUT_NAME "processing"
        SUFFIX ".dylib"
    )
    
    # macOS specific libraries
    find_library(CORE_FOUNDATION_LIBRARY CoreFoundation)
    find_library(CORE_AUDIO_LIBRARY CoreAudio)
    message(STATUS "CoreFoundation Library: ${CORE_FOUNDATION_LIBRARY}")
    message(STATUS "CoreAudio Library: ${CORE_AUDIO_LIBRARY}")
    
    target_link_libraries(processing PRIVATE 
        ${CORE_FOUNDATION_LIBRARY}
        ${CORE_AUDIO_LIBRARY}
    )
endif()

# Include directories
target_include_directories(processing PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/src/includes
)

# Set output directories
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)
set(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)
set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib) 