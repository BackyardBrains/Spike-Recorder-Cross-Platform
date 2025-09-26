cmake_minimum_required(VERSION 3.16)
project(nwbfile_plugin_web)

# Set C++ standard
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# Emscripten specific settings
if(EMSCRIPTEN)
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -s USE_BOOST_HEADERS=1")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -s USE_HDF5=1")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -s ALLOW_MEMORY_GROWTH=1")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -s EXPORTED_RUNTIME_METHODS=['ccall','cwrap']")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -s EXPORTED_FUNCTIONS=['_sum','_sum_long_running','_processing_init']")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -s EXPORT_NAME='NWBPlugin'")
    set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -s MODULARIZE=1")
endif()

# Include directories
include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/src
    ${CMAKE_CURRENT_SOURCE_DIR}/include
    ${CMAKE_CURRENT_SOURCE_DIR}/boost
)

# Find source files
file(GLOB_RECURSE SOURCES 
    "src/*.cpp"
    "src/*.c"
)

# Create the library
add_library(nwbfile_plugin_web STATIC ${SOURCES})

# Set target properties
set_target_properties(nwbfile_plugin_web PROPERTIES
    OUTPUT_NAME "nwbfile_plugin"
)

# If building with Emscripten, create the JavaScript module
if(EMSCRIPTEN)
    add_executable(nwbfile_plugin_web_module ${SOURCES})
    set_target_properties(nwbfile_plugin_web_module PROPERTIES
        OUTPUT_NAME "nwbfile_plugin"
        SUFFIX ".js"
    )
endif()

