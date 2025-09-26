# NWB File Plugin - Web Build

This directory contains the web build configuration for the NWB (Neurodata Without Borders) file plugin using Emscripten.

## Prerequisites

1. **Emscripten SDK**: Install and activate Emscripten
   ```bash
   # Install Emscripten
   git clone https://github.com/emscripten-core/emsdk.git
   cd emsdk
   ./emsdk install latest
   ./emsdk activate latest
   source ./emsdk_env.sh
   ```

2. **CMake**: Version 3.16 or higher
   ```bash
   # On macOS
   brew install cmake
   
   # On Ubuntu/Debian
   sudo apt-get install cmake
   ```

## Building

### Quick Build
```bash
# Make the build script executable
chmod +x build.sh

# Run the build
./build.sh
```

### Manual Build
```bash
# Create build directory
mkdir build
cd build

# Configure with CMake
emcmake cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CXX_FLAGS="-s USE_BOOST_HEADERS=1 -s USE_HDF5=1 -s ALLOW_MEMORY_GROWTH=1 -s EXPORTED_RUNTIME_METHODS=['ccall','cwrap'] -s EXPORTED_FUNCTIONS=['_sum','_sum_long_running','_processing_init'] -s EXPORT_NAME='NWBPlugin' -s MODULARIZE=1"

# Build
emmake make -j$(nproc)
```

## Output Files

After successful build, you'll find:
- `dist/nwbfile_plugin.js` - JavaScript wrapper module
- `dist/nwbfile_plugin.wasm` - WebAssembly binary

## Usage in Web Applications

### Basic Usage
```html
<!DOCTYPE html>
<html>
<head>
    <title>NWB Plugin Test</title>
</head>
<body>
    <script>
        // Load the module
        var NWBPlugin = require('./dist/nwbfile_plugin.js');
        
        // Initialize the plugin
        NWBPlugin().then(function(Module) {
            // Call exported functions
            var result = Module.ccall('sum', 'number', ['number', 'number'], [5, 3]);
            console.log('Sum result:', result);
            
            // Initialize processing
            var initResult = Module.ccall('processing_init', 'number', [], []);
            console.log('Processing init result:', initResult);
        });
    </script>
</body>
</html>
```

### With ES6 Modules
```javascript
import NWBPlugin from './dist/nwbfile_plugin.js';

async function useNWBPlugin() {
    const Module = await NWBPlugin();
    
    // Use the module
    const result = Module.ccall('sum', 'number', ['number', 'number'], [10, 20]);
    console.log('Result:', result);
}

useNWBPlugin();
```

## Exported Functions

The following C++ functions are exported to JavaScript:

- `sum(int a, int b)` - Simple addition function
- `sum_long_running(int a, int b)` - Long-running addition function (use in worker thread)
- `processing_init()` - Initialize NWB file processing workflow

## Troubleshooting

### Common Issues

1. **Emscripten not found**: Make sure Emscripten is installed and activated
   ```bash
   source /path/to/emsdk/emsdk_env.sh
   ```

2. **HDF5 compilation errors**: The build uses Emscripten's built-in HDF5 port
   ```bash
   # Make sure HDF5 is available
   emcc --show-ports | grep hdf5
   ```

3. **Memory issues**: The build includes `ALLOW_MEMORY_GROWTH=1` to handle large files

4. **Boost headers not found**: The build uses Emscripten's Boost port
   ```bash
   # Verify Boost is available
   emcc --show-ports | grep boost
   ```

### Debug Build
For debugging, use a debug build:
```bash
emcmake cmake .. -DCMAKE_BUILD_TYPE=Debug
```

## Dependencies

- **HDF5**: For file I/O operations
- **Boost**: For C++ utilities and data structures
- **Emscripten**: For WebAssembly compilation

## License

MIT License - see the main project license for details.

