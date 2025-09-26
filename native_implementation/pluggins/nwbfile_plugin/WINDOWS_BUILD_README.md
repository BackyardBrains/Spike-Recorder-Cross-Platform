# Windows Build Instructions for NWB File Plugin

This document provides instructions for building the NWB File Plugin on Windows with HDF5 and Boost support.

## Prerequisites

1. **Visual Studio 2019 or 2022** with C++ development tools
2. **CMake 3.14 or later**
3. **Git** (for cloning the repository)
4. **PowerShell** (for running the build script)

## Build Steps

### 1. Build HDF5 and Boost Libraries

Run the PowerShell build script to download and compile HDF5 and Boost:

```powershell
# Navigate to the plugin directory
cd PLUGINS/nwbfile_plugin

# Run the build script (PowerShell)
.\build_hdf5_boost_windows.ps1

# Or run the batch script (Command Prompt)
.\build_hdf5_boost_windows.bat
```

This script will:
- Download HDF5 1.14.6 and Boost 1.84.0 source code
- Build static libraries for both
- Install them to `windows/src/`

### 2. Build the Flutter Windows App

Once the libraries are built, you can build the Flutter Windows app:

```bash
# From the project root
flutter build windows
```

## Build Script Options

The PowerShell script accepts optional parameters:

```powershell
# Build with Debug configuration
.\build_hdf5_boost_windows.ps1 -BuildType Debug

# Build with Release configuration (default)
.\build_hdf5_boost_windows.ps1 -BuildType Release
```

## Directory Structure

After building, the following structure will be created:

```
PLUGINS/nwbfile_plugin/
├── windows/
│   └── src/
│       ├── include/
│       │   ├── hdf5/          # HDF5 headers
│       │   └── boost/         # Boost headers
│       └── lib/
│           ├── hdf5.lib       # HDF5 static library
│           ├── hdf5_cpp.lib   # HDF5 C++ static library
│           ├── hdf5_hl.lib    # HDF5 high-level static library
│           ├── hdf5_hl_cpp.lib # HDF5 high-level C++ static library
│           ├── boost_filesystem.lib
│           ├── boost_system.lib
│           ├── boost_thread.lib
│           ├── boost_chrono.lib
│           └── boost_atomic.lib
```

## Troubleshooting

### Common Issues

1. **CMake not found**: Make sure CMake is installed and in your PATH
2. **Visual Studio not found**: Install Visual Studio with C++ development tools
3. **Download failures**: Check your internet connection and firewall settings
4. **Build failures**: Ensure you have sufficient disk space (at least 2GB free)

### Build Logs

The build script provides detailed output. If you encounter issues:

1. Check the console output for specific error messages
2. Verify all prerequisites are installed
3. Try running with Debug configuration for more verbose output

## Manual Build (Alternative)

If the automated script doesn't work, you can build manually:

1. Download HDF5 and Boost source manually
2. Use CMake GUI or command line to configure and build
3. Copy the resulting libraries to `windows/src/lib/`
4. Copy headers to `windows/src/include/`

## Notes

- The build creates static libraries to avoid runtime dependencies
- All libraries are built for x64 architecture
- The build process may take 10-30 minutes depending on your system
- Generated libraries are approximately 50-100MB total

