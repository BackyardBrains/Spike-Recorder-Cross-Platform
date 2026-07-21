#ifndef NWBFILE_PLUGIN_SIMPLE_H
#define NWBFILE_PLUGIN_SIMPLE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Basic math functions
int sum(int a, int b);
int sum_long_running(int a, int b);

// NWB processing functions (Spike-Recorder API, AqNWB 0.4.0)
int32_t processing_init(const char* path,
                        int sampleRate,
                        int channelCount,
                        const char* deviceInfo,
                        const char* deviceManufacturer);

int32_t nwbfile_add_electrical_series(short* inSamples,
                                      int* samplesCount,
                                      int selectedChannel,
                                      int channelCount,
                                      int isFinishRecording);

// SpikeEventSeries (threshold-crossing waveform snippets).
// nwbfile_create_spike_event_series must be called after processing_init and
// before the first write that starts SWMR recording (e.g. add_electrical_series).
// Returns the recording container index (>= 0), or -1 on failure.
int32_t nwbfile_create_spike_event_series(int32_t channelIndex);

// Writes one spike event. waveform is float32[numSamples] in volts.
// Returns 0 on success, -1 on failure.
int32_t nwbfile_write_spike_event(int32_t channelIndex,
                                  float timestampSeconds,
                                  const float* waveform,
                                  int32_t numSamples);

// Returns the number of spike events written for channelIndex, or -1 on failure.
int32_t nwbfile_get_spike_event_count(int32_t channelIndex);

int32_t nwbfile_read_electrical_series(short* outSamples,
                                       int* outSamplesCount,
                                       int selectedChannel,
                                       int channelCount);

int32_t nwbfile_seek_electrical_series(const char* path,
                                       short* outSamples,
                                       int* outSamplesCount,
                                       int* outConfig,
                                       int startTimeStamp,
                                       int endTimeStamp,
                                       int startChannel,
                                       int endChannel);

// EventsTable
int32_t nwbfile_add_event(float timestampSeconds, int32_t eventLabel);
int32_t nwbfile_update_event(int32_t rowIndex,
                             float timestampSeconds,
                             int32_t eventLabel);
int32_t nwbfile_delete_event(int32_t rowIndex);
int32_t nwbfile_read_event(int32_t rowIndex,
                           float* outTimestampSeconds,
                           int32_t* outEventLabel,
                           uint8_t* outDeleted);
int32_t nwbfile_get_event_count();

// MeaningsTable for EventsTable event_type column
int32_t nwbfile_set_meaning(int32_t value, const char* meaning);
int32_t nwbfile_get_meaning_count();
int32_t nwbfile_read_meaning(int32_t rowIndex,
                             int32_t* outValue,
                             char* outMeaning,
                             int32_t outMeaningCapacity);
int32_t nwbfile_find_meaning(int32_t value,
                             char* outMeaning,
                             int32_t outMeaningCapacity);

int32_t get_nwb_file_size();
int32_t get_nwb_file_data(char* buffer, int buffer_size);
void cleanup_nwb_data();

int32_t debug_nwb_file_structure(const char* filePath);

#ifdef __cplusplus
}
#endif

#endif  // NWBFILE_PLUGIN_SIMPLE_H
