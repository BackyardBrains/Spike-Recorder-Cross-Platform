@echo off
setlocal enabledelayedexpansion

:: Check if running on Windows
ver | find "Windows" > nul
if errorlevel 1 (
    echo This script is for Windows only
    exit /b 1
)

:: Create build directory
if not exist build mkdir build
cd build

:: Check for Visual Studio
where cl > nul 2>&1
if errorlevel 1 (
    echo Visual Studio not found in PATH
    echo Please run this script from a Visual Studio Developer Command Prompt
    exit /b 1
)

:: Generate build files with CMake
echo Generating CMake build files...
cmake -G "Visual Studio 17 2022" -A x64 ..
if errorlevel 1 (
    echo CMake generation failed
    exit /b 1
)

:: Build the library
echo Building library...
cmake --build . --config Release
if errorlevel 1 (
    echo Build failed
    exit /b 1
)

:: Copy the library to the plugin directory
echo Copying library to plugin directory...
copy /Y Release\processing.dll ..\
if errorlevel 1 (
    echo Failed to copy DLL
    exit /b 1
)

:: Verify the library exists
if exist ..\processing.dll (
    echo Library built successfully!
    echo Library is in native_implementation\pluggins\processing_plugin\processing.dll
) else (
    echo Error: Library build failed!
    exit /b 1
)

cd .. 