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

// Spike-Recorder NWB recording API (AqNWB 0.4.0)
FFI_PLUGIN_EXPORT int sum(int a, int b);
FFI_PLUGIN_EXPORT int sum_long_running(int a, int b);

FFI_PLUGIN_EXPORT int32_t processing_init(const char* path,
                                          int sampleRate,
                                          int channelCount,
                                          const char* deviceInfo,
                                          const char* deviceManufacturer);

FFI_PLUGIN_EXPORT int32_t nwbfile_add_electrical_series(short* inSamples,
                                                        int* samplesCount,
                                                        int selectedChannel,
                                                        int channelCount,
                                                        int isFinishRecording);

// EventsTable row-based API (AqNWB EventsTable / addRow).
// nwbfile_add_event returns the new row index (>= 0) on success, or -1 on failure.
// update/delete return 0 on success, -1 on failure. delete is a soft-delete
// (sets the deleted column to 1) so append recording state stays valid.
FFI_PLUGIN_EXPORT int32_t nwbfile_add_event(float timestampSeconds,
                                            int32_t eventLabel);
FFI_PLUGIN_EXPORT int32_t nwbfile_update_event(int32_t rowIndex,
                                               float timestampSeconds,
                                               int32_t eventLabel);
FFI_PLUGIN_EXPORT int32_t nwbfile_delete_event(int32_t rowIndex);

FFI_PLUGIN_EXPORT int32_t nwbfile_read_electrical_series(short* outSamples,
                                                         int* outSamplesCount,
                                                         int selectedChannel,
                                                         int channelCount);

FFI_PLUGIN_EXPORT int32_t nwbfile_seek_electrical_series(const char* path,
                                                         short* outSamples,
                                                         int* outSamplesCount,
                                                         int* outConfig,
                                                         int startTimeStamp,
                                                         int endTimeStamp,
                                                         int startChannel,
                                                         int endChannel);

FFI_PLUGIN_EXPORT int get_nwb_file_size();
FFI_PLUGIN_EXPORT int get_nwb_file_data(uint8_t* buffer, int buffer_size);
FFI_PLUGIN_EXPORT void cleanup_nwb_data();
FFI_PLUGIN_EXPORT int32_t debug_nwb_file_structure(const char* filePath);
