# The Flutter tooling requires that developers have CMake 3.10 or later
# installed. You should not increase this version, as doing so will cause
# the plugin to fail to compile for some customers of the plugin.
cmake_minimum_required(VERSION 3.10)

project(processing_ffi_library VERSION 0.0.1 LANGUAGES C)

add_library(processing_ffi SHARED
  "processing_ffi.c"
)

set_target_properties(processing_ffi PROPERTIES
  PUBLIC_HEADER processing_ffi.h
  OUTPUT_NAME "processing_ffi"
)

target_compile_definitions(processing_ffi PUBLIC DART_SHARED_LIB)
