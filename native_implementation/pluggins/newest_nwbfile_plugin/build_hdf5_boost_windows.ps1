# Build script for HDF5 and Boost on Windows
# This script downloads and builds HDF5 and Boost for Windows

param(
    [string]$BuildType = "Release",
    [string]$Architecture = "x64"
)

Write-Host "Building HDF5 and Boost for Windows..." -ForegroundColor Green

# Configuration
$HDF5_VERSION = "1.14.6"
$BOOST_VERSION = "1_84_0"
$BUILD_DIR = Join-Path $PWD "hdf5_boost_windows_build"
$INSTALL_DIR = Join-Path $PWD "windows\src"

# Create build directory
if (!(Test-Path $BUILD_DIR)) {
    New-Item -ItemType Directory -Path $BUILD_DIR | Out-Null
}
Set-Location $BUILD_DIR

# Download HDF5 source if not already present
$HDF5_SOURCE_DIR = "hdf5-hdf5-$HDF5_VERSION"
if (!(Test-Path $HDF5_SOURCE_DIR)) {
    Write-Host "Downloading HDF5 source..." -ForegroundColor Yellow
    $HDF5_URL = "https://github.com/HDFGroup/hdf5/archive/refs/tags/hdf5-$HDF5_VERSION.zip"
    $HDF5_ZIP = "hdf5-$HDF5_VERSION.zip"
    
    Invoke-WebRequest -Uri $HDF5_URL -OutFile $HDF5_ZIP
    Expand-Archive -Path $HDF5_ZIP -DestinationPath "." -Force
    Remove-Item $HDF5_ZIP
}

# Download Boost source if not already present
$BOOST_SOURCE_DIR = "boost_$BOOST_VERSION"
if (!(Test-Path $BOOST_SOURCE_DIR)) {
    Write-Host "Downloading Boost source..." -ForegroundColor Yellow
    $BOOST_URL = "https://boostorg.jfrog.io/artifactory/main/release/$BOOST_VERSION/source/boost_$BOOST_VERSION.zip"
    $BOOST_ZIP = "boost_$BOOST_VERSION.zip"
    
    Invoke-WebRequest -Uri $BOOST_URL -OutFile $BOOST_ZIP
    Expand-Archive -Path $BOOST_ZIP -DestinationPath "." -Force
    Remove-Item $BOOST_ZIP
}

# Create build directories
$HDF5_BUILD_DIR = Join-Path $BUILD_DIR "hdf5_build"
$BOOST_BUILD_DIR = Join-Path $BUILD_DIR "boost_build"

if (!(Test-Path $HDF5_BUILD_DIR)) {
    New-Item -ItemType Directory -Path $HDF5_BUILD_DIR | Out-Null
}
if (!(Test-Path $BOOST_BUILD_DIR)) {
    New-Item -ItemType Directory -Path $BOOST_BUILD_DIR | Out-Null
}

# Build HDF5
Write-Host "Building HDF5..." -ForegroundColor Yellow
Set-Location $HDF5_BUILD_DIR

$HDF5_CMAKE_ARGS = @(
    "..\$HDF5_SOURCE_DIR",
    "-DCMAKE_BUILD_TYPE=$BuildType",
    "-DCMAKE_INSTALL_PREFIX=`"$INSTALL_DIR`"",
    "-DBUILD_SHARED_LIBS=OFF",
    "-DHDF5_BUILD_CPP_LIB=ON",
    "-DHDF5_BUILD_HL_LIB=ON",
    "-DHDF5_BUILD_TOOLS=OFF",
    "-DHDF5_BUILD_EXAMPLES=OFF",
    "-DHDF5_BUILD_TESTS=OFF",
    "-DHDF5_ENABLE_PARALLEL=OFF",
    "-DHDF5_ENABLE_THREADSAFE=OFF",
    "-DHDF5_ENABLE_Z_LIB_SUPPORT=ON",
    "-DHDF5_ENABLE_SZIP_SUPPORT=OFF",
    "-DHDF5_DISABLE_COMPILER_WARNINGS=ON"
)

$HDF5_CMAKE_CMD = "cmake " + ($HDF5_CMAKE_ARGS -join " ")
Write-Host "Running: $HDF5_CMAKE_CMD" -ForegroundColor Cyan
Invoke-Expression $HDF5_CMAKE_CMD

if ($LASTEXITCODE -ne 0) {
    Write-Host "HDF5 CMake configuration failed" -ForegroundColor Red
    exit 1
}

Write-Host "Building HDF5..." -ForegroundColor Cyan
cmake --build . --config $BuildType
if ($LASTEXITCODE -ne 0) {
    Write-Host "HDF5 build failed" -ForegroundColor Red
    exit 1
}

Write-Host "Installing HDF5..." -ForegroundColor Cyan
cmake --install .
if ($LASTEXITCODE -ne 0) {
    Write-Host "HDF5 install failed" -ForegroundColor Red
    exit 1
}

# Build Boost
Write-Host "Building Boost..." -ForegroundColor Yellow
Set-Location $BOOST_BUILD_DIR

$BOOST_CMAKE_ARGS = @(
    "..\$BOOST_SOURCE_DIR",
    "-DCMAKE_BUILD_TYPE=$BuildType",
    "-DCMAKE_INSTALL_PREFIX=`"$INSTALL_DIR`"",
    "-DBUILD_SHARED_LIBS=OFF",
    "-DBOOST_ENABLE_CMAKE=ON",
    "-DBOOST_INCLUDE_LIBRARIES=filesystem,system,thread,chrono,atomic"
)

$BOOST_CMAKE_CMD = "cmake " + ($BOOST_CMAKE_ARGS -join " ")
Write-Host "Running: $BOOST_CMAKE_CMD" -ForegroundColor Cyan
Invoke-Expression $BOOST_CMAKE_CMD

if ($LASTEXITCODE -ne 0) {
    Write-Host "Boost CMake configuration failed" -ForegroundColor Red
    exit 1
}

Write-Host "Building Boost..." -ForegroundColor Cyan
cmake --build . --config $BuildType
if ($LASTEXITCODE -ne 0) {
    Write-Host "Boost build failed" -ForegroundColor Red
    exit 1
}

Write-Host "Installing Boost..." -ForegroundColor Cyan
cmake --install .
if ($LASTEXITCODE -ne 0) {
    Write-Host "Boost install failed" -ForegroundColor Red
    exit 1
}

Write-Host "HDF5 and Boost Windows build completed successfully!" -ForegroundColor Green
Write-Host "Libraries installed in: $INSTALL_DIR" -ForegroundColor Green

# List created files
Set-Location $INSTALL_DIR
Write-Host "`nCreated libraries:" -ForegroundColor Yellow
Get-ChildItem -Path "lib" -Filter "*.lib" | ForEach-Object { Write-Host "  $($_.Name)" }

Write-Host "`nCreated headers:" -ForegroundColor Yellow
Get-ChildItem -Path "include" -Directory | ForEach-Object { Write-Host "  $($_.Name)" }

