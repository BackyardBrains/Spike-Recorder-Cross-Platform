#include "nwbfile_processing_plugin.hpp"
#include <iostream>
#include <memory>
#include <string>
#include <vector>

// A very short-lived native function.
//
// For very short-lived functions, it is fine to call them on the main isolate.
// They will block the Dart execution while running the native function, so
// only do this for native functions which are guaranteed to be short-lived.
FFI_PLUGIN_EXPORT int sum(int a, int b) { return a + b; }

// A longer-lived native function, which occupies the thread calling it.
//
// Do not call these kind of native functions in the main isolate. They will
// block Dart execution. This will cause dropped frames in Flutter applications.
// Instead, call these native functions on a separate isolate.
FFI_PLUGIN_EXPORT int sum_long_running(int a, int b) {
  // Simulate work.
#if _WIN32
  Sleep(5000);
#else
  usleep(5000 * 1000);
#endif
  return a + b;
}

// Processing initialization function (web version without HDF5)
FFI_PLUGIN_EXPORT int32_t processing_init() {
  try {
    std::cout << "AQNWB Recording Workflow Example (Web Version)" << std::endl;
    std::cout << "=============================================" << std::endl;
    std::cout << "This is a web-compatible version of the NWB plugin" << std::endl;
    std::cout << "HDF5 functionality is not available in this build" << std::endl;
    
    // Simulate the workflow steps
    std::cout << "1. Creating I/O object... (simulated)" << std::endl;
    std::cout << "2. Creating RecordingContainers... (simulated)" << std::endl;
    std::cout << "3. Initializing NWBFile... (simulated)" << std::endl;
    std::cout << "4. Creating electrodes table... (simulated)" << std::endl;
    std::cout << "5. Creating ElectricalSeries... (simulated)" << std::endl;
    std::cout << "6. Starting recording... (simulated)" << std::endl;
    std::cout << "7. Writing data... (simulated)" << std::endl;
    std::cout << "8. Stopping recording... (simulated)" << std::endl;
    std::cout << "9. Finalizing file... (simulated)" << std::endl;
    
    std::cout << "Processing initialization completed successfully" << std::endl;
    std::cout << "Note: This is a demonstration version. For full HDF5 support," << std::endl;
    std::cout << "you would need to compile HDF5 for Emscripten separately." << std::endl;
    
    return 0;
  } catch (const std::exception& e) {
      std::cerr << "Error: " << e.what() << std::endl;
      return 1;
  }    
  return -1;
}


