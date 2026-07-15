#include "nwbfile_plugin.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

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

// Global buffer to store NWB file data (iOS version)
static char* g_nwb_file_data = NULL;
static int g_nwb_file_size = 0;
static int g_nwb_file_ready = 0;

// Processing initialization function for iOS
FFI_PLUGIN_EXPORT int32_t processing_init() {
    printf("iOS: Initializing NWB processing...\n");
    
    // Create a simple mock NWB file structure for iOS
    const char* mock_nwb_content = 
        "NWB File Header\n"
        "Version: 2.0\n"
        "Platform: iOS\n"
        "Electrodes: 4\n"
        "ElectricalSeries: 1\n"
        "Data Points: 1000\n"
        "Sampling Rate: 30000 Hz\n"
        "File Size: iOS Mock Data\n"
        "Created with: Flutter iOS Plugin\n";
    
    // Free previous data if exists
    if (g_nwb_file_data) {
        free(g_nwb_file_data);
    }
    
    // Allocate and copy the mock data
    g_nwb_file_size = strlen(mock_nwb_content);
    g_nwb_file_data = (char*)malloc(g_nwb_file_size + 1);
    if (g_nwb_file_data) {
        strcpy(g_nwb_file_data, mock_nwb_content);
        g_nwb_file_ready = 1;
        printf("iOS: NWB file data ready (%d bytes)\n", g_nwb_file_size);
        return 0; // Success
    } else {
        printf("iOS: Failed to allocate memory for NWB file data\n");
        return 1; // Error
    }
}

// Get NWB file size
FFI_PLUGIN_EXPORT int32_t get_nwb_file_size() {
    if (!g_nwb_file_ready) {
        return -1; // Not ready
    }
    return g_nwb_file_size;
}

// Get NWB file data
FFI_PLUGIN_EXPORT int32_t get_nwb_file_data(char* buffer, int buffer_size) {
    if (!g_nwb_file_ready || !g_nwb_file_data) {
        return -1; // Not ready
    }
    
    if (buffer_size < g_nwb_file_size) {
        return -2; // Buffer too small
    }
    
    // Copy the data to the provided buffer
    memcpy(buffer, g_nwb_file_data, g_nwb_file_size);
    printf("iOS: Retrieved %d bytes of NWB file data\n", g_nwb_file_size);
    return g_nwb_file_size;
}

// Cleanup function
FFI_PLUGIN_EXPORT void cleanup_nwb_data() {
    if (g_nwb_file_data) {
        free(g_nwb_file_data);
        g_nwb_file_data = NULL;
        g_nwb_file_size = 0;
        g_nwb_file_ready = 0;
        printf("iOS: NWB file data cleaned up\n");
    }
}
