#!/bin/bash

# Emscripten build script with HDF5 compiled from source

set -e

# Check if emcc is available
if ! command -v emcc &> /dev/null; then
    echo "Error: emcc (Emscripten compiler) not found in PATH"
    echo "Please install Emscripten and activate it in your environment"
    exit 1
fi

# Create directories
mkdir -p dist
mkdir -p hdf5_build

echo "Building HDF5 for Emscripten..."

# Download and build HDF5 for Emscripten
if [ ! -d "hdf5_build/hdf5" ]; then
    echo "Downloading HDF5 source..."
    cd hdf5_build
    curl -L -o hdf5.tar.gz https://support.hdfgroup.org/ftp/HDF5/releases/hdf5-1.14/hdf5-1.14.3/src/hdf5-1.14.3.tar.gz
    tar -xzf hdf5.tar.gz
    mv hdf5-1.14.3 hdf5
    cd ..
fi

# Create build directory for HDF5
mkdir -p hdf5_build/build
cd hdf5_build/build

# Configure HDF5 for Emscripten
echo "Configuring HDF5 for Emscripten..."
emcmake cmake ../hdf5 \
    -DCMAKE_BUILD_TYPE=Release \
    -DHDF5_BUILD_TOOLS=OFF \
    -DHDF5_BUILD_EXAMPLES=OFF \
    -DHDF5_BUILD_HL_LIB=ON \
    -DHDF5_BUILD_CPP_LIB=ON \
    -DHDF5_ENABLE_Z_LIB_SUPPORT=ON \
    -DHDF5_ENABLE_SZIP_SUPPORT=OFF \
    -DHDF5_ENABLE_THREADSAFE=OFF \
    -DHDF5_ENABLE_PARALLEL=OFF \
    -DHDF5_BUILD_SHARED_LIBS=OFF \
    -DCMAKE_INSTALL_PREFIX=../install

# Build HDF5
echo "Building HDF5..."
emmake make -j$(nproc)
emmake make install

cd ../../

echo "Building NWB Plugin with compiled HDF5..."

# Find all source files
SOURCES=$(find src -name "*.cpp" -o -name "*.c" | tr '\n' ' ')

# Build with Emscripten using compiled HDF5
emcc $SOURCES \
    -I./src \
    -I./include \
    -I./boost \
    -I./hdf5_build/install/include \
    -L./hdf5_build/install/lib \
    -lhdf5 \
    -lhdf5_cpp \
    -lhdf5_hl \
    -lhdf5_hl_cpp \
    -s USE_BOOST_HEADERS=1 \
    -s ALLOW_MEMORY_GROWTH=1 \
    -s EXPORTED_RUNTIME_METHODS=['ccall','cwrap'] \
    -s EXPORTED_FUNCTIONS=['_sum','_sum_long_running','_processing_init'] \
    -s EXPORT_NAME='NWBPlugin' \
    -s MODULARIZE=1 \
    -s WASM=1 \
    -s ASSERTIONS=1 \
    -s SAFE_HEAP=1 \
    -s TOTAL_MEMORY=268435456 \
    -s ALLOW_TABLE_GROWTH=1 \
    -O2 \
    -o dist/nwbfile_plugin.js

echo "Build completed successfully!"
echo "Generated files:"
ls -la dist/*.js dist/*.wasm 2>/dev/null || echo "No output files found"

echo "Files are ready in the dist/ directory"
