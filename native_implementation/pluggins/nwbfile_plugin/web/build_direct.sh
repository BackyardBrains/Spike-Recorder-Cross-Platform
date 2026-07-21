#!/bin/bash

# Direct Emscripten build script for NWB File Plugin

set -e

# Check if emcc is available
if ! command -v emcc &> /dev/null; then
    echo "Error: emcc (Emscripten compiler) not found in PATH"
    echo "Please install Emscripten and activate it in your environment"
    exit 1
fi

# Create output directory
mkdir -p dist

echo "Building NWB Plugin with Emscripten..."

# Find all source files
SOURCES=$(find src -name "*.cpp" -o -name "*.c" | tr '\n' ' ')

# Build with Emscripten (without HDF5 for now)
emcc $SOURCES \
    -I./src \
    -I./include \
    -I./boost \
    -s USE_BOOST_HEADERS=1 \
    -s ALLOW_MEMORY_GROWTH=1 \
    -s EXPORTED_RUNTIME_METHODS=['ccall','cwrap','HEAP16'] \
    -s EXPORTED_FUNCTIONS=['_sum','_sum_long_running','_processing_init'] \
    -s EXPORT_NAME='NWBPlugin' \
    -s MODULARIZE=1 \
    -s WASM=1 \
    -s ASSERTIONS=1 \
    -s SAFE_HEAP=1 \
    -s NO_DISABLE_EXCEPTION_CATCHING=1 \
    -O2 \
    -o dist/nwbfile_plugin.js

echo "Build completed successfully!"
echo "Generated files:"
ls -la dist/*.js dist/*.wasm 2>/dev/null || echo "No output files found"

echo "Files are ready in the dist/ directory"
