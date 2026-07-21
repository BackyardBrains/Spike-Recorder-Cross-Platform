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

// SpikeEventSeries (threshold-crossing waveform snippets).
// nwbfile_create_spike_event_series must be called after processing_init and
// before the first write that starts SWMR recording.
// Returns the recording container index (>= 0), or -1 on failure.
FFI_PLUGIN_EXPORT int32_t nwbfile_create_spike_event_series(int32_t channelIndex);

// Writes one spike event. waveform is float32[numSamples] in volts.
// Returns 0 on success, -1 on failure.
FFI_PLUGIN_EXPORT int32_t nwbfile_write_spike_event(int32_t channelIndex,
                                                      float timestampSeconds,
                                                      const float* waveform,
                                                      int32_t numSamples);

// Returns the number of spike events written for channelIndex, or -1 on failure.
FFI_PLUGIN_EXPORT int32_t nwbfile_get_spike_event_count(int32_t channelIndex);

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

// Reads one EventsTable row by index into the output params. Returns 0 on
// success, -1 on failure (e.g. invalid rowIndex or uninitialized table).
// outDeleted is 1 if the row was soft-deleted via nwbfile_delete_event.
FFI_PLUGIN_EXPORT int32_t nwbfile_read_event(int32_t rowIndex,
                                             float* outTimestampSeconds,
                                             int32_t* outEventLabel,
                                             uint8_t* outDeleted);

// Returns the total number of EventsTable rows added so far (including
// soft-deleted rows), or 0 if the table has not been initialized.
FFI_PLUGIN_EXPORT int32_t nwbfile_get_event_count();

// MeaningsTable management for the EventsTable `event_type` column.
// Maps integer event codes -> human-readable labels (e.g. 1 -> "lick").
//
// nwbfile_set_meaning: upsert by value. Returns row index (>= 0) on success,
// or -1 on failure. New values are appended; existing values update in place.
// nwbfile_get_meaning_count: number of meaning rows (0 if uninitialized).
// nwbfile_read_meaning: read by row index into outValue / outMeaning buffer.
//   Returns 0 on success, -1 on failure. outMeaning is null-terminated;
//   truncated if longer than outMeaningCapacity-1.
// nwbfile_find_meaning: lookup label by event_type value. Returns 0 if found,
//   -1 if not found / uninitialized.
FFI_PLUGIN_EXPORT int32_t nwbfile_set_meaning(int32_t value, const char* meaning);
FFI_PLUGIN_EXPORT int32_t nwbfile_get_meaning_count();
FFI_PLUGIN_EXPORT int32_t nwbfile_read_meaning(int32_t rowIndex,
                                               int32_t* outValue,
                                               char* outMeaning,
                                               int32_t outMeaningCapacity);
FFI_PLUGIN_EXPORT int32_t nwbfile_find_meaning(int32_t value,
                                               char* outMeaning,
                                               int32_t outMeaningCapacity);

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
