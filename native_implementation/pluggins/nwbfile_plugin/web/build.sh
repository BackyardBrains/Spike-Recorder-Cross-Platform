#!/bin/bash

# Build script for NWB File Plugin with Emscripten

set -e

# Check if emcc is available
if ! command -v emcc &> /dev/null; then
    echo "Error: emcc (Emscripten compiler) not found in PATH"
    echo "Please install Emscripten and activate it in your environment"
    echo "Visit: https://emscripten.org/docs/getting_started/downloads.html"
    exit 1
fi

# Create build directory
mkdir -p build
cd build

# Configure with CMake
echo "Configuring with CMake..."
emcmake cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_FLAGS="-s USE_BOOST_HEADERS=1 -s USE_HDF5=1 -s ALLOW_MEMORY_GROWTH=1 -s EXPORTED_RUNTIME_METHODS=['ccall','cwrap'] -s EXPORTED_FUNCTIONS=['_sum','_sum_long_running','_processing_init'] -s EXPORT_NAME='NWBPlugin' -s MODULARIZE=1"

# Build the project
echo "Building with Emscripten..."
emmake make -j$(nproc)

echo "Build completed successfully!"
echo "Generated files:"
ls -la *.js *.wasm 2>/dev/null || echo "No .js or .wasm files found"

# Copy files to a more accessible location
mkdir -p ../dist
cp -f *.js *.wasm ../dist/ 2>/dev/null || echo "No .js or .wasm files to copy"

echo "Files copied to dist/ directory"

