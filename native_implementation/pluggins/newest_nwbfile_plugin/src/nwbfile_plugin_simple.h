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

int32_t get_nwb_file_size();
int32_t get_nwb_file_data(char* buffer, int buffer_size);
void cleanup_nwb_data();

int32_t debug_nwb_file_structure(const char* filePath);

#ifdef __cplusplus
}
#endif

#endif  // NWBFILE_PLUGIN_SIMPLE_H
