cmake_minimum_required(VERSION 3.16)
project(nwbfile_plugin_web LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_compile_definitions(AQNWB_CXX_STANDARD=17)

set(EXPORTS "['_sum','_sum_long_running','_processing_init','_nwbfile_add_electrical_series','_nwbfile_read_electrical_series','_nwbfile_seek_electrical_series','_nwbfile_add_event','_nwbfile_update_event','_nwbfile_delete_event','_nwbfile_get_event_count','_nwbfile_read_event','_nwbfile_set_meaning','_nwbfile_get_meaning_count','_nwbfile_read_meaning','_nwbfile_find_meaning','_get_nwb_file_size','_get_nwb_file_data','_cleanup_nwb_data','_debug_nwb_file_structure','_malloc','_free']")

if(EMSCRIPTEN)
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -s USE_ZLIB=1")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -s ALLOW_MEMORY_GROWTH=1")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -s FORCE_FILESYSTEM=1")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -s EXPORTED_RUNTIME_METHODS=['ccall','cwrap','UTF8ToString','FS','HEAP16','HEAP32','HEAPU8']")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -s EXPORTED_FUNCTIONS=${EXPORTS}")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -s EXPORT_NAME='NWBPlugin'")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -s MODULARIZE=1")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -s NO_DISABLE_EXCEPTION_CATCHING=1")
  set(CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS} -fexceptions")
endif()

include_directories(
  ${CMAKE_CURRENT_SOURCE_DIR}/src
  ${CMAKE_CURRENT_SOURCE_DIR}/include
  ${CMAKE_CURRENT_SOURCE_DIR}/hdf5_build/hdf5/src
)

file(GLOB_RECURSE SOURCES CONFIGURE_DEPENDS
  "src/*.cpp"
  "src/*.c"
)
list(FILTER SOURCES EXCLUDE REGEX ".*_web\\.cpp$")

add_executable(nwbfile_plugin_web_module ${SOURCES})
set_target_properties(nwbfile_plugin_web_module PROPERTIES
  OUTPUT_NAME "nwbfile_plugin"
  SUFFIX ".js"
)

if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/hdf5_build/build/bin/libhdf5.a")
  target_link_directories(nwbfile_plugin_web_module PRIVATE
    ${CMAKE_CURRENT_SOURCE_DIR}/hdf5_build/build/bin)
  target_link_libraries(nwbfile_plugin_web_module PRIVATE hdf5_cpp hdf5_hl hdf5)
endif()
