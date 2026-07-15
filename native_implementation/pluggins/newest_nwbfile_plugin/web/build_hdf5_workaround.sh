#!/bin/bash
# Build AqNWB 0.4.0 + Spike-Recorder recording API for Web (Emscripten/WASM).
# No Boost required. Uses prebuilt HDF5 in ./hdf5_build/build/bin.
set -euo pipefail

cd "$(dirname "$0")"

if [ ! -f "src/sz_stubs.cpp" ]; then
  echo "Error: run from PLUGINS/nwbfile_plugin/web/ (sz_stubs.cpp missing)"
  exit 1
fi

if ! command -v emcc >/dev/null 2>&1; then
  echo "Error: emcc not found. Install/activate Emscripten first."
  exit 1
fi

if [ ! -f "hdf5_build/build/bin/libhdf5.a" ]; then
  echo "Error: missing HDF5 wasm libs under hdf5_build/build/bin/"
  echo "Build HDF5 for Emscripten before running this script."
  exit 1
fi

# web/ -> nwbfile_plugin -> PLUGINS -> nwbapplication/web/nwb
mkdir -p dist ../../../web/nwb

echo "Collecting sources..."
# C++ only (skip empty/commented nwbfile_plugin.c — -std=c++17 breaks emcc on .c).
SOURCES=$(find src -name '*.cpp' \
  | grep -v '_web' \
  | grep -v '_stub' \
  | tr '\n' ' ')
SOURCES="$SOURCES src/sz_stubs.cpp"

HDF5_LIB_PATH="./hdf5_build/build/bin"
HDF5_INCLUDE_PATH="./hdf5_build/hdf5/src"
# Prefer headers from plugin include/ (H5Cpp) when present
EXTRA_INCLUDES="-I./src -I./include -I${HDF5_INCLUDE_PATH}"
if [ -d "./hdf5_build/build/src" ]; then
  EXTRA_INCLUDES="$EXTRA_INCLUDES -I./hdf5_build/build/src"
fi

EXPORTS="['_sum','_sum_long_running','_processing_init','_nwbfile_add_electrical_series','_nwbfile_read_electrical_series','_nwbfile_seek_electrical_series','_get_nwb_file_size','_get_nwb_file_data','_cleanup_nwb_data','_debug_nwb_file_structure','_malloc','_free']"

echo "Building nwbfile_plugin.wasm with emcc..."
# shellcheck disable=SC2086
emcc $SOURCES \
  $EXTRA_INCLUDES \
  -L"$HDF5_LIB_PATH" \
  -lhdf5_cpp -lhdf5_hl -lhdf5 \
  -std=c++17 \
  -DAQNWB_CXX_STANDARD=17 \
  -s USE_ZLIB=1 \
  -s ALLOW_MEMORY_GROWTH=1 \
  -s FORCE_FILESYSTEM=1 \
  -s EXPORTED_RUNTIME_METHODS="['ccall','cwrap','UTF8ToString','stringToUTF8','lengthBytesUTF8','FS','HEAP8','HEAP16','HEAP32','HEAPU8']" \
  -s EXPORTED_FUNCTIONS="$EXPORTS" \
  -s EXPORT_NAME='NWBPlugin' \
  -s MODULARIZE=1 \
  -s WASM=1 \
  -s ASSERTIONS=1 \
  -s INITIAL_MEMORY=268435456 \
  -s ALLOW_TABLE_GROWTH=1 \
  -s ERROR_ON_UNDEFINED_SYMBOLS=0 \
  -s WARN_ON_UNDEFINED_SYMBOLS=0 \
  -s NO_DISABLE_EXCEPTION_CATCHING=1 \
  -fexceptions \
  -O2 \
  -o dist/nwbfile_plugin.js

# Copy into Flutter web/ so index.html can load them as static assets.
cp -f dist/nwbfile_plugin.js dist/nwbfile_plugin.wasm ../../../web/nwb/

echo "Build completed."
ls -lh dist/nwbfile_plugin.js dist/nwbfile_plugin.wasm
ls -lh ../../../web/nwb/
