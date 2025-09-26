#ifndef NWBFILE_PLUGIN_SIMPLE_H
#define NWBFILE_PLUGIN_SIMPLE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Basic math functions
int sum(int a, int b);
int sum_long_running(int a, int b);

// NWB processing functions
int32_t processing_init(const char* path);
int32_t get_nwb_file_size();
int32_t get_nwb_file_data(char* buffer, int buffer_size);
void cleanup_nwb_data();

// NWB File Append Functions
int32_t append_timeseries_data(const char* file_path, 
                              const char* series_name,
                              const double* timestamps, 
                              int32_t num_timestamps,
                              const void* data, 
                              int32_t data_type,
                              int32_t num_samples,
                              int32_t num_channels);

int32_t append_electrical_series_data(const char* file_path,
                                     const char* series_name,
                                     const double* timestamps,
                                     int32_t num_timestamps,
                                     const void* data,
                                     int32_t data_type,
                                     int32_t num_samples,
                                     int32_t num_channels);

int32_t append_interval_data(const char* file_path,
                            const char* interval_name,
                            const double* start_times,
                            const double* stop_times,
                            int32_t num_intervals,
                            const char** tags,
                            int32_t num_tags);

int32_t append_acquisition_data(const char* file_path,
                               const char* acquisition_name,
                               const double* timestamps,
                               int32_t num_timestamps,
                               const void* data,
                               int32_t data_type,
                               int32_t num_samples,
                               int32_t num_channels);

int32_t create_new_timeseries(const char* file_path,
                              const char* series_name,
                              int32_t data_type,
                              int32_t num_channels,
                              const char** channel_names,
                              float sampling_rate);

int32_t create_new_interval(const char* file_path,
                            const char* interval_name,
                            const char** column_names,
                            int32_t num_columns);

#ifdef __cplusplus
}
#endif

#endif // NWBFILE_PLUGIN_SIMPLE_H
