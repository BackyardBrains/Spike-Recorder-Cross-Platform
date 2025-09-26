# Test CMake configuration for Windows build
cmake_minimum_required(VERSION 3.14)
project(test_windows_config)

# Test if we can detect Windows
if(WIN32)
    message(STATUS "Windows platform detected")
else()
    message(STATUS "Not Windows platform")
endif()

# Test include directories
set(TEST_INCLUDE_DIRS
    "${CMAKE_CURRENT_SOURCE_DIR}/windows/src/include"
    "${CMAKE_CURRENT_SOURCE_DIR}/windows/src/include/hdf5"
    "${CMAKE_CURRENT_SOURCE_DIR}/windows/src/include/boost"
)

foreach(dir ${TEST_INCLUDE_DIRS})
    if(EXISTS ${dir})
        message(STATUS "Include directory exists: ${dir}")
    else()
        message(STATUS "Include directory missing: ${dir}")
    endif()
endforeach()

# Test library paths
set(TEST_LIBRARIES
    "${CMAKE_CURRENT_SOURCE_DIR}/windows/src/lib/hdf5.lib"
    "${CMAKE_CURRENT_SOURCE_DIR}/windows/src/lib/hdf5_cpp.lib"
    "${CMAKE_CURRENT_SOURCE_DIR}/windows/src/lib/boost_filesystem.lib"
    "${CMAKE_CURRENT_SOURCE_DIR}/windows/src/lib/boost_system.lib"
)

foreach(lib ${TEST_LIBRARIES})
    if(EXISTS ${lib})
        message(STATUS "Library exists: ${lib}")
    else()
        message(STATUS "Library missing: ${lib}")
    endif()
endforeach()

message(STATUS "Windows CMake configuration test completed")

