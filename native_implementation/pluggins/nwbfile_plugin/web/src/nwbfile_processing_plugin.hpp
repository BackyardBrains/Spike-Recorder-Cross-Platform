#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#if _WIN32
#include <windows.h>
#else
#include <pthread.h>
#include <unistd.h>
#endif

#if _WIN32
#define FFI_PLUGIN_EXPORT extern "C" __declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT extern "C" 
#endif

// A very short-lived native function.
//
// For very short-lived functions, it is fine to call them on the main isolate.
// They will block the Dart execution while running the native function, so
// only do this for native functions which are guaranteed to be short-lived.
FFI_PLUGIN_EXPORT int sum(int a, int b);

// A longer lived native function, which occupies the thread calling it.
//
// Do not call these kind of native functions in the main isolate. They will
// block Dart execution. This will cause dropped frames in Flutter applications.
// Instead, call these native functions on a separate isolate.
FFI_PLUGIN_EXPORT int sum_long_running(int a, int b);

// Processing initialization function
// FFI_PLUGIN_EXPORT int32_t processing_init();

// // Function to check for annotation series
// FFI_PLUGIN_EXPORT int32_t check_annotation_series();

// // Processing update function
// FFI_PLUGIN_EXPORT int32_t processing_update();

FFI_PLUGIN_EXPORT int32_t processing_init(const char* path, int sampleRate, int channelCount, const char* deviceInfo, const char* deviceManufacturer);
FFI_PLUGIN_EXPORT int32_t nwbfile_add_electrical_series(short* inSamples, int* samplesCount, int selectedChannel, int channelCount, int isFinishRecording);
FFI_PLUGIN_EXPORT int32_t nwbfile_read_electrical_series(short* outSamples, int* outSamplesCount, int selectedChannel, int channelCount);
FFI_PLUGIN_EXPORT int get_nwb_file_size();
FFI_PLUGIN_EXPORT int get_nwb_file_data(uint8_t* buffer, int buffer_size);
FFI_PLUGIN_EXPORT int32_t debug_nwb_file_structure(const char* filePath);
FFI_PLUGIN_EXPORT int32_t nwbfile_seek_electrical_series(const char* path, short* outSamples, int* outSamplesCount, int* outConfig, int startTimeStamp, int endTimeStamp, int startChannel, int endChannel);
