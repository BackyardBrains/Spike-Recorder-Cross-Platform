#!/bin/bash

# Build script for HDF5 with Android NDK
# This script downloads and compiles HDF5 from source for Android ARM64

set -e

# Configuration
HDF5_VERSION="1.14.6"
HDF5_URL="https://github.com/HDFGroup/hdf5/archive/refs/tags/hdf5-${HDF5_VERSION}.tar.gz"
BUILD_DIR="$(pwd)/hdf5_android_build"
INSTALL_DIR="$(pwd)/android/src/main/cpp"
SOURCE_DIR="${BUILD_DIR}/hdf5-hdf5-${HDF5_VERSION}"

# Android NDK Configuration
ANDROID_NDK="${ANDROID_NDK_ROOT:-$ANDROID_NDK_HOME}"
if [ -z "$ANDROID_NDK" ]; then
    echo "Error: ANDROID_NDK_ROOT or ANDROID_NDK_HOME environment variable must be set"
    echo "Please set it to your Android NDK installation path"
    exit 1
fi

ANDROID_ABI="arm64-v8a"
ANDROID_PLATFORM="android-21"
ANDROID_TOOLCHAIN="${ANDROID_NDK}/toolchains/llvm/prebuilt/$(uname -s | tr '[:upper:]' '[:lower:]')-x86_64"

# Compiler settings
export CC="${ANDROID_TOOLCHAIN}/bin/aarch64-linux-android21-clang"
export CXX="${ANDROID_TOOLCHAIN}/bin/aarch64-linux-android21-clang++"
export AR="${ANDROID_TOOLCHAIN}/bin/llvm-ar"
export RANLIB="${ANDROID_TOOLCHAIN}/bin/llvm-ranlib"
export STRIP="${ANDROID_TOOLCHAIN}/bin/llvm-strip"

# Compiler flags to avoid fortified function issues
export CFLAGS="-fPIC -D_FORTIFY_SOURCE=0 -DANDROID -fdata-sections -ffunction-sections"
export CXXFLAGS="-fPIC -D_FORTIFY_SOURCE=0 -DANDROID -fdata-sections -ffunction-sections -std=c++17"
export LDFLAGS="-static-libstdc++"

echo "Building HDF5 ${HDF5_VERSION} for Android ARM64..."
echo "NDK Path: ${ANDROID_NDK}"
echo "Toolchain: ${ANDROID_TOOLCHAIN}"
echo "Install Dir: ${INSTALL_DIR}"

# Create build directory
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

# Download HDF5 source if not already present
if [ ! -d "${SOURCE_DIR}" ]; then
    echo "Downloading HDF5 source..."
    curl -L "${HDF5_URL}" -o "hdf5-${HDF5_VERSION}.tar.gz"
    tar -xzf "hdf5-${HDF5_VERSION}.tar.gz"
fi

# Create build directory
mkdir -p build
cd build

# Configure with CMake
echo "Configuring HDF5 with CMake..."
cmake "${SOURCE_DIR}" \
    -DCMAKE_TOOLCHAIN_FILE="${ANDROID_NDK}/build/cmake/android.toolchain.cmake" \
    -DANDROID_ABI="${ANDROID_ABI}" \
    -DANDROID_PLATFORM="${ANDROID_PLATFORM}" \
    -DANDROID_NDK="${ANDROID_NDK}" \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="${INSTALL_DIR}" \
    -DBUILD_SHARED_LIBS=OFF \
    -DHDF5_BUILD_CPP_LIB=ON \
    -DHDF5_BUILD_HL_LIB=ON \
    -DHDF5_BUILD_TOOLS=OFF \
    -DHDF5_BUILD_EXAMPLES=OFF \
    -DHDF5_BUILD_TESTS=OFF \
    -DHDF5_ENABLE_PARALLEL=OFF \
    -DHDF5_ENABLE_THREADSAFE=OFF \
    -DHDF5_ENABLE_Z_LIB_SUPPORT=ON \
    -DHDF5_ENABLE_SZIP_SUPPORT=OFF \
    -DHDF5_DISABLE_COMPILER_WARNINGS=ON \
    -DHDF5_ENABLE_DEBUG=OFF

# Build
echo "Building HDF5..."
make -j$(nproc)

# Install
echo "Installing HDF5 libraries..."
make install

# Copy libraries to the correct location
echo "Copying libraries to Android lib directory..."
mkdir -p "${INSTALL_DIR}/lib"
cp lib/libhdf5.a "${INSTALL_DIR}/lib/"
cp lib/libhdf5_cpp.a "${INSTALL_DIR}/lib/"
cp lib/libhdf5_hl.a "${INSTALL_DIR}/lib/"
cp lib/libhdf5_hl_cpp.a "${INSTALL_DIR}/lib/"

echo "HDF5 Android build completed successfully!"
echo "Libraries installed in: ${INSTALL_DIR}/lib/"
echo "Headers installed in: ${INSTALL_DIR}/include/"

# List the created libraries
echo ""
echo "Created libraries:"
ls -la "${INSTALL_DIR}/lib/libhdf5*.a"
