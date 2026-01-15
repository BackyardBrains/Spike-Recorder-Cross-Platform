# NWB Plugin Web - Current State Backup

This document captures the current state of the NWB plugin web implementation as of the last update before overwriting with newer files.

## Directory Structure

```
native_implementation/pluggins/nwbfile_plugin/web/
├── README.md                          # Main documentation
├── CMakeLists.txt                     # CMake build configuration
├── package.json                       # Node.js package configuration
├── .gitignore                        # Git ignore rules
├── setup.sh                          # Setup script for dependencies
├── build.sh                           # Main build script (CMake-based)
├── build_direct.sh                    # Direct Emscripten build script
├── build_simple.sh                    # Simple build script
├── build_with_stubs.sh                # Build with stubs
├── build_with_compiled_hdf5.sh        # Build with compiled HDF5
├── build_with_compiled_hdf5_libs.sh   # Build with compiled HDF5 libraries
├── build_with_macos_hdf5.sh           # Build with macOS HDF5
├── build_hdf5_workaround.sh           # HDF5 workaround build
├── test.html                          # Browser test page
├── test_node.js                       # Node.js test script
├── test_with_nwb_data.html            # Test with NWB data
├── test_file_data.js                  # Test file data
├── src/                               # Source files
│   ├── nwbfile_plugin.c               # Main plugin C file (commented out)
│   ├── nwbfile_plugin.h               # Main plugin header (commented out)
│   ├── nwbfile_processing_plugin.hpp  # Processing plugin header
│   ├── nwbfile_processing_plugin.cpp  # Processing plugin implementation
│   ├── nwbfile_processing_plugin_web.cpp  # Web-specific implementation
│   ├── Channel.cpp/hpp                # Channel implementation
│   ├── io/                            # I/O implementations
│   │   ├── BaseIO.cpp/hpp
│   │   └── hdf5/
│   │       ├── HDF5IO.cpp/hpp
│   │       ├── HDF5IO_stub.cpp        # Stub implementation for web
│   │       ├── HDF5ArrayDataSetConfig.cpp/hpp
│   │       └── HDF5RecordingData.cpp/hpp
│   ├── nwb/                           # NWB file structure
│   │   ├── NWBFile.cpp/hpp
│   │   ├── RecordingContainers.cpp/hpp
│   │   ├── base/TimeSeries.cpp/hpp
│   │   ├── device/Device.cpp/hpp
│   │   ├── ecephys/
│   │   │   ├── ElectricalSeries.cpp/hpp
│   │   │   └── SpikeEventSeries.cpp/hpp
│   │   ├── file/
│   │   │   ├── ElectrodeGroup.cpp/hpp
│   │   │   └── ElectrodeTable.cpp/hpp
│   │   ├── hdmf/
│   │   └── misc/
│   ├── spec/                          # Specification files
│   ├── sz_stubs.cpp                   # Compression stubs
│   ├── Types.hpp
│   └── Utils.hpp
├── include/                           # Header includes
├── lib/                               # Compiled libraries (macOS)
├── boost/                             # Boost headers
├── hdf5_build/                        # HDF5 build artifacts
├── build/                             # Build directory
└── dist/                              # Distribution directory (output)
```

## Key Files Content

### README.md
- Comprehensive documentation for building and using the NWB plugin
- Prerequisites: Emscripten SDK, CMake
- Build instructions (quick and manual)
- Usage examples (HTML and ES6 modules)
- Exported functions: `sum`, `sum_long_running`, `processing_init`
- Troubleshooting section

### CMakeLists.txt
- CMake minimum version: 3.16
- C++ standard: 17
- Emscripten-specific flags:
  - `USE_BOOST_HEADERS=1`
  - `USE_HDF5=1`
  - `ALLOW_MEMORY_GROWTH=1`
  - `EXPORTED_RUNTIME_METHODS=['ccall','cwrap']`
  - `EXPORTED_FUNCTIONS=['_sum','_sum_long_running','_processing_init']`
  - `EXPORT_NAME='NWBPlugin'`
  - `MODULARIZE=1`
- Include directories: src, include, boost
- Source files: all .cpp and .c files in src/
- Creates both static library and JavaScript module

### package.json
- Name: `nwbfile-plugin-web`
- Version: `1.0.0`
- Main: `dist/nwbfile_plugin.js`
- Scripts: build, clean, install-deps, test
- Keywords: nwb, neuroscience, hdf5, emscripten, webassembly
- Node.js engine: >=14.0.0

### build.sh
- Main build script using CMake
- Checks for emcc availability
- Creates build directory
- Configures with CMake and Emscripten flags
- Builds with `emmake make`
- Copies output to `dist/` directory

### src/nwbfile_processing_plugin_web.cpp
- Web-specific implementation
- Exported functions:
  - `sum(int a, int b)` - Simple addition
  - `sum_long_running(int a, int b)` - Long-running addition (5 second delay)
  - `processing_init()` - NWB processing initialization (simulated, no HDF5)
- Note: Web version simulates NWB workflow without actual HDF5 support

### src/nwbfile_processing_plugin.hpp
- Header file with function declarations
- Defines `FFI_PLUGIN_EXPORT` macro for cross-platform exports
- Declares:
  - `sum(int a, int b)`
  - `sum_long_running(int a, int b)`
  - `processing_init(const char* path, int sampleRate, int channelCount, const char* deviceInfo, const char* deviceManufacturer)` - Full signature
  - Additional functions commented out or with different signatures:
    - `nwbfile_add_electrical_series`
    - `nwbfile_read_electrical_series`
    - `get_nwb_file_size`
    - `get_nwb_file_data`
    - `debug_nwb_file_structure`
    - `nwbfile_seek_electrical_series`

### test.html
- Browser-based test page
- Tests module loading
- Tests sum function
- Tests long-running sum function
- Tests NWB processing initialization
- Uses CommonJS require() to load module

### test_node.js
- Node.js test script
- Checks for dist/ directory and required files
- Loads and tests the module
- Tests all exported functions
- Provides colored console output

### .gitignore
- Ignores: build/, dist/, emsdk/, node_modules/
- OS files: .DS_Store, Thumbs.db, etc.
- IDE files: .vscode/, .idea/, *.swp, etc.
- CMake files: CMakeCache.txt, CMakeFiles/, etc.
- Emscripten artifacts: *.js.mem, *.wasm.map, etc.

## Build Configuration

### Emscripten Flags
- `USE_BOOST_HEADERS=1` - Use Boost headers port
- `USE_HDF5=1` - Use HDF5 port (note: web version simulates without actual HDF5)
- `ALLOW_MEMORY_GROWTH=1` - Allow memory to grow for large files
- `EXPORTED_RUNTIME_METHODS=['ccall','cwrap']` - Export runtime methods
- `EXPORTED_FUNCTIONS=['_sum','_sum_long_running','_processing_init']` - Export specific functions
- `EXPORT_NAME='NWBPlugin'` - Module export name
- `MODULARIZE=1` - Create modularized output

### Output Files
- `dist/nwbfile_plugin.js` - JavaScript wrapper module
- `dist/nwbfile_plugin.wasm` - WebAssembly binary

## Current Implementation Status

### Working Features
- Basic function exports (`sum`, `sum_long_running`)
- Module loading and initialization
- Web-compatible build system
- Test infrastructure (browser and Node.js)

### Limitations
- `processing_init()` is simulated - does not actually use HDF5
- HDF5 functionality is stubbed out for web compatibility
- Full NWB file operations not implemented in web version

### Source Files Structure
- Complete NWB file structure implementation (NWBFile, ElectricalSeries, etc.)
- HDF5 I/O layer with stub implementation for web
- Boost headers included for C++ utilities
- Channel and device management
- Recording containers and data structures

## Notes

1. The web version uses `nwbfile_processing_plugin_web.cpp` which provides a simulated implementation
2. The header file shows more complete function signatures that may be implemented in native versions
3. Multiple build scripts exist for different scenarios (with/without HDF5, different platforms)
4. The implementation includes a full NWB file structure but web version simulates the workflow
5. HDF5 support in Emscripten is limited, hence the stub implementations

## Date Captured
This state was captured before planned updates/overwrites.
