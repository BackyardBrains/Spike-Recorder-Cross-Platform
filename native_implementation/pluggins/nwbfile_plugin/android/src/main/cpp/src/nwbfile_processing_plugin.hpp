#ifndef PROCESSING_H
#define PROCESSING_H

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
#define FFI_PLUGIN_EXPORT _declspec(dllexport)
#else
#define FFI_PLUGIN_EXPORT
#endif


#ifdef __cplusplus
extern "C" {
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
FFI_PLUGIN_EXPORT int32_t processing_init(const char* path, int sampleRate, int channelCount, const char* deviceInfo, const char* deviceManufacturer);

// NWB file electrical series functions
FFI_PLUGIN_EXPORT int32_t nwbfile_add_electrical_series(short* inSamples, int* samplesCount, int selectedChannel, int channelCount, int isFinishRecording);
FFI_PLUGIN_EXPORT int32_t nwbfile_read_electrical_series(short* outSamples, int* outSamplesCount, int selectedChannel, int channelCount);
FFI_PLUGIN_EXPORT int32_t nwbfile_seek_electrical_series(const char* path, short* outSamples, int* outSamplesCount, int* outConfig, int startTimeStamp, int endTimeStamp, int startChannel, int endChannel);

// Debug function
FFI_PLUGIN_EXPORT int32_t debug_nwb_file_structure(const char* filePath);

// NWB file data functions
FFI_PLUGIN_EXPORT int32_t get_nwb_file_size();
FFI_PLUGIN_EXPORT int32_t get_nwb_file_data(uint8_t* buffer, int buffer_size);
FFI_PLUGIN_EXPORT void cleanup_nwb_data();

// NWB File Append Functions
FFI_PLUGIN_EXPORT int32_t append_timeseries_data(const char* file_path, 
                                                 const char* series_name,
                                                 const double* timestamps, 
                                                 int32_t num_timestamps,
                                                 const void* data, 
                                                 int32_t data_type,
                                                 int32_t num_samples,
                                                 int32_t num_channels);

FFI_PLUGIN_EXPORT int32_t append_electrical_series_data(const char* file_path,
                                                        const char* series_name,
                                                        const double* timestamps,
                                                        int32_t num_timestamps,
                                                        const void* data,
                                                        int32_t data_type,
                                                        int32_t num_samples,
                                                        int32_t num_channels);

FFI_PLUGIN_EXPORT int32_t append_interval_data(const char* file_path,
                                               const char* interval_name,
                                               const double* start_times,
                                               const double* stop_times,
                                               int32_t num_intervals,
                                               const char** tags,
                                               int32_t num_tags);

FFI_PLUGIN_EXPORT int32_t append_acquisition_data(const char* file_path,
                                                  const char* acquisition_name,
                                                  const double* timestamps,
                                                  int32_t num_timestamps,
                                                  const void* data,
                                                  int32_t data_type,
                                                  int32_t num_samples,
                                                  int32_t num_channels);

FFI_PLUGIN_EXPORT int32_t create_new_timeseries(const char* file_path,
                                                const char* series_name,
                                                int32_t data_type,
                                                int32_t num_channels,
                                                const char** channel_names,
                                                float sampling_rate);

FFI_PLUGIN_EXPORT int32_t create_new_interval(const char* file_path,
                                              const char* interval_name,
                                              const char** column_names,
                                              int32_t num_columns);

#ifdef __cplusplus
}
#endif


#endif // PROCESSING_H
