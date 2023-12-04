cmake_minimum_required(VERSION 3.10)

project(native_add_library VERSION 0.0.1 LANGUAGES CXX)
set(CMAKE_SYSTEM_VERSION 10.0.22621.0)

if(POLICY CMP0079)
  cmake_policy(SET CMP0079 NEW)
endif()

# Create a list of source files
set(SOURCE_FILES
        filter_util.cpp
        high_pass_filter.cpp
        low_pass_filter.cpp
        filter_base.cpp
        notch_filter.cpp
)

# Check if compiling for Windows
if(WIN32)
  list(APPEND SOURCE_FILES capture_audio.cpp)
elseif(APPLE)
  list(APPEND SOURCE_FILES mac_capture_audio.cpp)
  find_library(CORE_AUDIO_LIBRARY CoreAudio)
  message(STATUS "CoreAudio Library: ${CORE_AUDIO_LIBRARY}")

  find_library(AUDIO_TOOLBOX_LIBRARY AudioToolbox)
  message(STATUS "AudioToolbox Library: ${AUDIO_TOOLBOX_LIBRARY}")

  find_library(AUDIO_UNIT_LIBRARY AudioUnit)
  message(STATUS "AudioUnit Library: ${AUDIO_UNIT_LIBRARY}")

  find_library(CORE_FOUNDATION_LIBRARY CoreFoundation)
  message(STATUS "CoreFoundation Library: ${CORE_FOUNDATION_LIBRARY}")
endif()

add_library(native_add SHARED ${SOURCE_FILES})
target_compile_definitions(native_add PUBLIC DART_SHARED_LIB)

# Link against different libraries based on the target platform
if(WIN32)
  target_link_libraries(native_add PRIVATE 
    ole32.lib
    oleaut32.lib
    mmdevapi.lib
    ksuser.lib
  )
elseif(ANDROID)
  # Add Android-specific libraries here if necessary
elseif(APPLE)
  target_link_libraries(native_add PRIVATE 
    ${CORE_AUDIO_LIBRARY}
    ${AUDIO_TOOLBOX_LIBRARY}
    ${AUDIO_UNIT_LIBRARY}
    ${CORE_FOUNDATION_LIBRARY}
  )
endif()


