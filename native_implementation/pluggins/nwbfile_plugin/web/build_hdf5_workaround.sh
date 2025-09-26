#!/bin/bash

# Emscripten build script with HDF5 workarounds

set -e

# Check if we're in the correct directory by looking for the specific file needed
if [ ! -f "src/sz_stubs.cpp" ]; then
    echo "Error: 'src/sz_stubs.cpp' file not found in current directory"
    echo "Please run this script from the web directory: PLUGINS/nwbfile_plugin/web/"
    echo "Current directory: $(pwd)"
    exit 1
fi

# Check if emcc is available
if ! command -v emcc &> /dev/null; then
    echo "Error: emcc (Emscripten compiler) not found in PATH"
    echo "Please install Emscripten and activate it in your environment"
    exit 1
fi

# Create output directory
mkdir -p dist

echo "Building NWB Plugin with Emscripten using HDF5 workarounds..."

# Find all source files except web version and stub files (now including HDF5IO with proper WASM libraries)
# But include sz_stubs.cpp specifically for SZ compression stubs
SOURCES=$(find src -name "*.cpp" -o -name "*.c" | grep -v "_web" | grep -v "_stub" | tr '\n' ' ')
SOURCES="$SOURCES src/sz_stubs.cpp"

# Paths to compiled HDF5 libraries
HDF5_LIB_PATH="./hdf5_build/build/bin"
HDF5_INCLUDE_PATH="./hdf5_build/hdf5/src"

# Build with Emscripten using compiled HDF5 but avoiding problematic code
emcc $SOURCES \
    -I./src \
    -I./include \
    -I./boost \
    -I$HDF5_INCLUDE_PATH \
    -L$HDF5_LIB_PATH \
    -lhdf5 \
    -lhdf5_cpp \
    -lhdf5_hl \
    -s USE_BOOST_HEADERS=1 \
    -s USE_ZLIB=1 \
    -s ALLOW_MEMORY_GROWTH=1 \
    -s EXPORTED_RUNTIME_METHODS=['ccall','cwrap','UTF8ToString','FS'] \
    -s EXPORTED_FUNCTIONS=['_sum','_sum_long_running','_processing_init','_processing_update','_check_annotation_series','_get_nwb_file_size','_get_nwb_file_data','_malloc','_free'] \
    -s EXPORT_NAME='NWBPlugin' \
    -s MODULARIZE=1 \
    -s WASM=1 \
    -s FORCE_FILESYSTEM=1 \
    -s ASSERTIONS=1 \
    -s SAFE_HEAP=1 \
    -s TOTAL_MEMORY=268435456 \
    -s ALLOW_TABLE_GROWTH=1 \
    -s ERROR_ON_UNDEFINED_SYMBOLS=0 \
    -s WARN_ON_UNDEFINED_SYMBOLS=0 \
    -O2 \
    -o dist/nwbfile_plugin.js

echo "Build completed successfully!"
echo "Generated files:"
ls -la dist/*.js dist/*.wasm 2>/dev/null || echo "No output files found"

echo "Files are ready in the dist/ directory"
