#!/bin/bash

# Exit on error
set -e

# Detect OS
if [[ "$OSTYPE" != "darwin"* ]]; then
    echo "This script is for macOS only"
    exit 1
fi

# Check for CMake
if ! command -v cmake &> /dev/null; then
    echo "CMake not found. Please install it using:"
    echo "brew install cmake"
    exit 1
fi

# Create build directory if it doesn't exist
mkdir -p build
cd build

# Generate build files with CMake
echo "Generating CMake build files..."
cmake -DCMAKE_BUILD_TYPE=Release \
      -DCMAKE_OSX_ARCHITECTURES="x86_64;arm64" \
      ..

# Build the library
echo "Building library..."
make -j$(sysctl -n hw.ncpu)

# Create a lib directory at the project root if it doesn't exist
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../" && pwd)"
LIB_DIR="$PROJECT_ROOT/lib/native"
mkdir -p "$LIB_DIR"

# Copy the built library to the lib directory
echo "Copying library to lib/native directory..."
cp "libprocessing.dylib" "$LIB_DIR/"

# Set the correct install name
install_name_tool -id "@rpath/libprocessing.dylib" "$LIB_DIR/libprocessing.dylib"

echo "Build complete. Library is in $LIB_DIR/libprocessing.dylib"

# Verify the library exists
if [ -f "$LIB_DIR/libprocessing.dylib" ]; then
    echo "Library built successfully!"
    echo "Library architecture information:"
    lipo -info "$LIB_DIR/libprocessing.dylib"
    echo "Library dependencies:"
    otool -L "$LIB_DIR/libprocessing.dylib"
else
    echo "Error: Library build failed!"
    exit 1
fi 