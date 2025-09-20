#ifndef PROCESSING_H
#define PROCESSING_H

// Add this export macro definition at the top of the file
#ifdef _WIN32
    #ifdef BUILDING_DLL
        #define PROCESSING_API __declspec(dllexport)
    #else
        #define PROCESSING_API __declspec(dllimport)
    #endif
#else
    #define PROCESSING_API
#endif

#ifdef __cplusplus
#define EXTERNC extern "C"
#else
#define EXTERNC
#endif

#if defined(__GNUC__)
    #define FUNCTION_ATTRIBUTE __attribute__((visibility("default"))) __attribute__((used))
#elif defined(_MSC_VER)
    #define FUNCTION_ATTRIBUTE __declspec(dllexport)
#endif

#include <stdint.h>
#include "FilterBase.h"
#include "LowPassFilter.h"
#include "HighPassFilter.h"
#include "NotchFilter.h"
#include "SignalUtils.h"
#include "AmModulationProcessor.h"
#include "SampleStreamProcessor.h"
#include "SampleStreamUtils.h"
#include "ThresholdProcessor.h"
#include "FftProcessor.h"
#include "DrawingUtils.h"
#include "EventTriggeredAverageAnalysis.h"
#include "SpikeAnalysis.h"
#include "AutocorrelationAnalysis.h"
#include "CrossCorrelationAnalysis.h"
#include "IsiAnalysis.h"
#include "AverageSpikeAnalysis.h"
#include "AnalysisUtils.h"
#include "EventUtils.h"


#ifdef __cplusplus
extern "C" {
#endif

// Constants
#define PROCESSING_MAX_CHANNELS 6
#define PROCESSING_DEFAULT_SAMPLE_RATE 44100
#define PROCESSING_DEFAULT_BITS_PER_SAMPLE 16
#define PROCESSING_MIN_FILTER_CUTOFF 0.0f
#define PROCESSING_MAX_FILTER_CUTOFF 5000.0f
#define PROCESSING_DEFAULT_AVERAGED_SAMPLE_COUNT 10
#define PROCESSING_MAX_FFT_WINDOWS 100  // Maximum number of FFT windows to process

// Basic initialization and configuration
PROCESSING_API int32_t processing_init();
PROCESSING_API void processing_cleanup();

// Sample rate and channel configuration
PROCESSING_API int32_t processing_set_sample_rate(int32_t sample_rate);
PROCESSING_API int32_t processing_set_channel_count(int32_t channel_count);
PROCESSING_API int32_t processing_set_bits_per_sample(int32_t bits_per_sample);
PROCESSING_API int32_t processing_set_selected_channel(int32_t selected_channel);

// Filter configuration
PROCESSING_API int32_t processing_set_band_filter(float low_cut_off_freq, float high_cut_off_freq);
PROCESSING_API int32_t processing_set_notch_filter(float center_freq);
PROCESSING_API int32_t processing_set_channel_filter_enabled(int32_t channel, bool enabled);

// Stream processing
PROCESSING_API int32_t processing_process_sample_stream(int16_t* out_samples, int32_t* out_sample_counts,
                                       const uint8_t* in_data, int32_t length,
                                       int32_t hardware_type);

PROCESSING_API int32_t processing_process_microphone_stream(int16_t* out_samples, int32_t* out_sample_counts,
                                           const uint8_t* in_data, int32_t length);

PROCESSING_API int32_t processing_process_playback_stream(int16_t* out_samples, int32_t* out_sample_counts,
                                         const uint8_t* in_data, int32_t length,
                                         const int32_t* event_indices, const char* event_names,
                                         int32_t event_count, int64_t start, int64_t end,
                                         int32_t prepend_samples);


PROCESSING_API int32_t processing_get_most_right(int chan, int from_sample, int to_sample, int bufferSize);

// Signal analysis
// PROCESSING_API float processing_rms(const int16_t* data, int32_t length);
PROCESSING_API int32_t processing_map(float* out_data, const float* in_data, int32_t length,
                      float in_min, float in_max, float out_min, float out_max);


// AM modulation detection
PROCESSING_API int32_t processing_is_audio_stream_am_modulated();

// Threshold processing
PROCESSING_API int32_t processing_get_averaged_sample_count();
PROCESSING_API void processing_set_averaged_sample_count(int32_t count);
PROCESSING_API int32_t processing_get_averaging_trigger_type();
PROCESSING_API void processing_set_averaging_trigger_type(int32_t type);
PROCESSING_API void processing_set_threshold(float threshold);
PROCESSING_API void processing_reset_threshold();
PROCESSING_API void processing_resume_threshold();
PROCESSING_API void processing_pause_threshold();
PROCESSING_API void processing_set_is_thresholding(bool flag);
PROCESSING_API int32_t processing_process_threshold(int16_t* out_samples, int32_t* out_sample_counts,
                                   int16_t* in_samples, int32_t* in_sample_counts,
                                   const int32_t* in_event_indices, const int32_t* in_event_labels, int32_t in_event_count,
                                   bool average_samples);

// STEVE COMMENTED THIS OUT
// PROCESSING_API int32_t processing_process_threshold(int16_t** out_samples, int32_t* out_sample_counts,
//                                    const int16_t** in_samples, const int32_t* in_sample_counts,
//                                    bool average_samples);

// BPM processing
PROCESSING_API void processing_set_bpm_processing(bool process_bpm);

// Drawing utilities

PROCESSING_API int32_t processing_prepare_for_signal_drawing(
    int16_t* out_samples, 
    int* out_sample_counts,
    float* out_event_indices, 
    int32_t* out_event_count,
    const int32_t* in_event_indices, 
    int32_t in_event_count,
    int32_t from_sample, 
    int32_t to_sample,
    int32_t draw_surface_width);

// Event analysis
// STEVE COMMENTED THIS OUT
// PROCESSING_API int32_t processing_parse_events(const char* file_path, float sample_rate,
//                               int32_t* event_indices, char** event_names);

// PROCESSING_API int32_t processing_check_events(const char* file_path, char** event_names);

// PROCESSING_API void processing_event_triggered_average_analysis(const char* file_path,
//                                                const char* events_file_path,
//                                                const char** events,
//                                                int32_t event_count,
//                                                float** averages,
//                                                float** norm_averages,
//                                                float** norm_mc_averages,
//                                                float** norm_mc_top,
//                                                float** norm_mc_bottom,
//                                                float* min_max,
//                                                int32_t channel_count,
//                                                int32_t frame_count,
//                                                bool remove_noise_intervals,
//                                                const char* confidence_intervals_event);

// Spike analysis
// STEVE COMMENTED THIS OUT
// PROCESSING_API int32_t** processing_find_spikes(const char* file_path,
//                                 int16_t** values_pos,
//                                 int32_t** indices_pos,
//                                 float** times_pos,
//                                 int16_t** values_neg,
//                                 int32_t** indices_neg,
//                                 float** times_neg,
//                                 int32_t channel_count,
//                                 int32_t max_spikes);

// PROCESSING_API void processing_autocorrelation_analysis(float** spike_trains,
//                                        int32_t spike_train_count,
//                                        int32_t* spike_counts,
//                                        int32_t** analysis,
//                                        int32_t analysis_bin_count);

// PROCESSING_API void processing_isi_analysis(float** spike_trains,
//                            int32_t spike_train_count,
//                            int32_t* spike_counts,
//                            int32_t** analysis,
//                            int32_t analysis_bin_count);

// EXTERNC FUNCTION_ATTRIBUTE PROCESSING_API void processing_cross_correlation_analysis(float** spike_trains,
//                                          int32_t spike_train_count,
//                                          int32_t* spike_counts,
//                                          int32_t** analysis,
//                                          int32_t analysis_count,
//                                          int32_t analysis_bin_count);

// PROCESSING_API void processing_average_spike_analysis(const char* file_path,
//                                      int32_t** spike_trains,
//                                      int32_t spike_train_count,
//                                      int32_t* spike_counts,
//                                      float** average_spike,
//                                      float** norm_average_spike,
//                                      float** norm_top_std_line,
//                                      float** norm_bottom_std_line,
//                                      int32_t batch_spike_count);
PROCESSING_API short processing_pass_pointers(short* ptrExpBoardType);

// FFT processing
// STEVE COMMENTED THIS OUT
PROCESSING_API int32_t processing_process_fft(float* _out_fft, int32_t* out_window_count,
    int32_t* out_window_size, int16_t* _in_samples,
    const int32_t* in_sample_counts);
PROCESSING_API void processing_reset_fft_normalization();

PROCESSING_API int32_t processing_prepare_fft_for_drawing(float* out_vertices, int16_t* out_indices,
                                         float* out_colors, int32_t* out_vertex_count,
                                         int32_t* out_index_count, int32_t* out_color_count,
                                         float* _fft_data, int32_t window_count,
                                         int32_t window_size, float width, float height);
                                           

#ifdef __cplusplus
}
#endif

#endif // PROCESSING_H




// public class FftDrawData {

//     public float[] vertices;
//     public short[] indices;
//     public float[] colors;

//     public int vertexCount;
//     public int indexCount;
//     public int colorCount;

//     public float scaleX;
//     public float scaleY;

//     public FftDrawData(int maxSegments) {
//         vertices = new float[maxSegments * 2];
//         indices = new short[maxSegments * 6];
//         colors = new float[maxSegments * 4];
//         vertexCount = 0;
//         indexCount = 0;
//         colorCount = 0;
//     }
// }
