cmake_minimum_required(VERSION 3.10)
project(processing_plugin LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 14)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_SYSTEM_VERSION 10.0.22621.0)

add_library(processing_plugin SHARED
  "../src/processing.cpp"
)

target_compile_definitions(processing_plugin PRIVATE DART_SHARED_LIB) 