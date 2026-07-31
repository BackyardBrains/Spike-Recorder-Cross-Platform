# The Flutter tooling requires that developers have a version of Visual Studio
# installed that includes CMake 3.14 or later. You should not increase this
# version, as doing so will cause the plugin to fail to compile for some
# customers of the plugin.
cmake_minimum_required(VERSION 3.14)

# Project-level configuration.
set(PROJECT_NAME "nwbfile_plugin")
project(${PROJECT_NAME} LANGUAGES CXX)

# Invoke the build for native code shared with the other target platforms.
# This can be changed to accommodate different builds.
add_subdirectory("${CMAKE_CURRENT_SOURCE_DIR}/../src" "${CMAKE_CURRENT_BINARY_DIR}/shared")

# List of absolute paths to libraries that should be bundled with the plugin.
# This list could contain prebuilt libraries, or libraries created by an
# external build triggered from this build file.
#
# nwbfile_plugin links against HDF5 via import libraries (hdf5.lib etc. in
# ../src/lib), which means the actual HDF5 code lives in DLLs resolved at
# runtime via the normal Windows DLL search order. Those DLLs are NOT part of
# the OS or the Flutter engine, so unless we ship them here ourselves, the app
# only works on machines that happen to have a compatible HDF5 install on
# PATH (e.g. a dev machine with the HDF Group installer) - anyone else either
# gets a missing-module load failure or, worse, silently picks up a different
# hdf5.dll left behind by unrelated software (MATLAB, ArcGIS, etc.), which
# fails deep inside HDF5 with a version/ABI mismatch. Bundling the exact
# matching runtime DLLs makes the app self-contained.
set(nwbfile_plugin_bundled_libraries
  # Defined in ../src/CMakeLists.txt.
  # This can be changed to accommodate different builds.
  $<TARGET_FILE:nwbfile_plugin>
  "${CMAKE_CURRENT_SOURCE_DIR}/src/lib/hdf5.dll"
  "${CMAKE_CURRENT_SOURCE_DIR}/src/lib/hdf5_cpp.dll"
  "${CMAKE_CURRENT_SOURCE_DIR}/src/lib/hdf5_hl.dll"
  "${CMAKE_CURRENT_SOURCE_DIR}/src/lib/hdf5_hl_cpp.dll"
  PARENT_SCOPE
)
