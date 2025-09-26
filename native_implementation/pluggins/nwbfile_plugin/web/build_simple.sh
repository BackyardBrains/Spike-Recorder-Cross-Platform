#!/bin/bash

# Simple Emscripten build script for NWB File Plugin (without HDF5)

set -e

# Check if emcc is available
if ! command -v emcc &> /dev/null; then
    echo "Error: emcc (Emscripten compiler) not found in PATH"
    echo "Please install Emscripten and activate it in your environment"
    exit 1
fi

# Create output directory
mkdir -p dist

echo "Building NWB Plugin with Emscripten (Simplified Version)..."

# Use only the web-specific source file
SOURCES="src/nwbfile_processing_plugin_web.cpp"

# Build with Emscripten
emcc $SOURCES \
    -I./src \
    -s ALLOW_MEMORY_GROWTH=1 \
    -s EXPORTED_RUNTIME_METHODS=['ccall','cwrap'] \
    -s EXPORTED_FUNCTIONS=['_sum','_sum_long_running','_processing_init'] \
    -s EXPORT_NAME='NWBPlugin' \
    -s MODULARIZE=1 \
    -s WASM=1 \
    -s ASSERTIONS=1 \
    -s SAFE_HEAP=1 \
    -O2 \
    -o dist/nwbfile_plugin.js

echo "Build completed successfully!"
echo "Generated files:"
ls -la dist/*.js dist/*.wasm 2>/dev/null || echo "No output files found"

echo "Files are ready in the dist/ directory"
