@echo off
setlocal enabledelayedexpansion

REM Build script for HDF5 and Boost on Windows
REM This script downloads and builds HDF5 and Boost for Windows

echo Building HDF5 and Boost for Windows...

REM Configuration
set HDF5_VERSION=1.14.6
set BOOST_VERSION=1_84_0
set BUILD_DIR=%cd%\hdf5_boost_windows_build
set INSTALL_DIR=%cd%\windows\src

REM Create build directory
if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"
cd /d "%BUILD_DIR%"

REM Download HDF5 source if not already present
if not exist "hdf5-%HDF5_VERSION%" (
    echo Downloading HDF5 source...
    powershell -Command "Invoke-WebRequest -Uri 'https://github.com/HDFGroup/hdf5/archive/refs/tags/hdf5-%HDF5_VERSION%.zip' -OutFile 'hdf5-%HDF5_VERSION%.zip'"
    powershell -Command "Expand-Archive -Path 'hdf5-%HDF5_VERSION%.zip' -DestinationPath '.'"
)

REM Download Boost source if not already present
if not exist "boost_%BOOST_VERSION%" (
    echo Downloading Boost source...
    powershell -Command "Invoke-WebRequest -Uri 'https://boostorg.jfrog.io/artifactory/main/release/%BOOST_VERSION%/source/boost_%BOOST_VERSION%.zip' -OutFile 'boost_%BOOST_VERSION%.zip'"
    powershell -Command "Expand-Archive -Path 'boost_%BOOST_VERSION%.zip' -DestinationPath '.'"
)

REM Create build directories
if not exist "hdf5_build" mkdir "hdf5_build"
if not exist "boost_build" mkdir "boost_build"

REM Build HDF5
echo Building HDF5...
cd /d "hdf5_build"
cmake ..\hdf5-hdf5-%HDF5_VERSION% ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_INSTALL_PREFIX="%INSTALL_DIR%" ^
    -DBUILD_SHARED_LIBS=OFF ^
    -DHDF5_BUILD_CPP_LIB=ON ^
    -DHDF5_BUILD_HL_LIB=ON ^
    -DHDF5_BUILD_TOOLS=OFF ^
    -DHDF5_BUILD_EXAMPLES=OFF ^
    -DHDF5_BUILD_TESTS=OFF ^
    -DHDF5_ENABLE_PARALLEL=OFF ^
    -DHDF5_ENABLE_THREADSAFE=OFF ^
    -DHDF5_ENABLE_Z_LIB_SUPPORT=ON ^
    -DHDF5_ENABLE_SZIP_SUPPORT=OFF ^
    -DHDF5_DISABLE_COMPILER_WARNINGS=ON

if %ERRORLEVEL% neq 0 (
    echo HDF5 CMake configuration failed
    exit /b 1
)

cmake --build . --config Release
if %ERRORLEVEL% neq 0 (
    echo HDF5 build failed
    exit /b 1
)

cmake --install .
if %ERRORLEVEL% neq 0 (
    echo HDF5 install failed
    exit /b 1
)

REM Build Boost
echo Building Boost...
cd /d "..\boost_build"
cmake ..\boost_%BOOST_VERSION% ^
    -DCMAKE_BUILD_TYPE=Release ^
    -DCMAKE_INSTALL_PREFIX="%INSTALL_DIR%" ^
    -DBUILD_SHARED_LIBS=OFF ^
    -DBOOST_ENABLE_CMAKE=ON ^
    -DBOOST_INCLUDE_LIBRARIES=filesystem,system,thread,chrono,atomic

if %ERRORLEVEL% neq 0 (
    echo Boost CMake configuration failed
    exit /b 1
)

cmake --build . --config Release
if %ERRORLEVEL% neq 0 (
    echo Boost build failed
    exit /b 1
)

cmake --install .
if %ERRORLEVEL% neq 0 (
    echo Boost install failed
    exit /b 1
)

echo HDF5 and Boost Windows build completed successfully!
echo Libraries installed in: %INSTALL_DIR%

cd /d "%INSTALL_DIR%"
echo.
echo Created libraries:
dir /b lib\*.lib
echo.
echo Created headers:
dir /b include

endlocal

