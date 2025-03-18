#include "processing.h"
#include <cmath>
#include <vector>
#include <cstring>
#include <algorithm>
#include <sys/time.h>

using namespace backyardbrains::filters;
using namespace backyardbrains::processing;
using namespace backyardbrains::analysis;
using namespace backyardbrains::utils;

// Constants
static constexpr int32_t PROCESSING_MAX_EVENTS = 100;  // Same as MAX_EVENTS in SampleStreamProcessor

// Internal state variables
static bool initialized = false;
static int32_t current_sample_rate = PROCESSING_DEFAULT_SAMPLE_RATE;
static int32_t current_channel_count = 1;
static int32_t current_bits_per_sample = PROCESSING_DEFAULT_BITS_PER_SAMPLE;
static int32_t current_selected_channel = 0;
static float current_low_cut_off_freq = PROCESSING_MIN_FILTER_CUTOFF;
static float current_high_cut_off_freq = PROCESSING_MAX_FILTER_CUTOFF;
static float current_notch_filter_freq = PROCESSING_MIN_FILTER_CUTOFF;
static float current_threshold = 0.0f;
static bool threshold_paused = false;
static int32_t averaging_sample_count = PROCESSING_DEFAULT_AVERAGED_SAMPLE_COUNT;
static int32_t averaging_trigger_type = 0;
static bool bpm_processing_enabled = false;

// Processor instances (same as in byb-lib.cpp)
class EventListener; 
static EventListener* eventListener = nullptr;
static AmModulationProcessor* amModulationProcessor = nullptr;
static SampleStreamProcessor* sampleStreamProcessor = nullptr;
static ThresholdProcessor* thresholdProcessor = nullptr;
static FftProcessor* fftProcessor = nullptr;
static EventTriggeredAverageAnalysis* eventTriggeredAverageAnalysis = nullptr;
static SpikeAnalysis* spikeAnalysis = nullptr;
static AutocorrelationAnalysis* autocorrelationAnalysis = nullptr;
static IsiAnalysis* isiAnalysis = nullptr;
static AverageSpikeAnalysis* averageSpikeAnalysis = nullptr;
static CrossCorrelationAnalysis* crossCorrelationAnalysis = nullptr;


class HeartbeatListener : public backyardbrains::utils::OnHeartbeatListener {
public:
    HeartbeatListener() = default;

    ~HeartbeatListener() = default;

    void onHeartbeat(int bmp) override {
      //   backyardbrains::utils::JniHelper::invokeStaticVoid(vm, "onHeartbeat", "(I)V", bmp);
    }
};

class EventListener : public backyardbrains::utils::OnEventListenerListener {
public:
    EventListener() {
 
    }

    ~EventListener() = default;



    void onSpikerBoxHardwareTypeDetected(int hardwareType) override {
      //   backyardbrains::utils::JniHelper::invokeVoid(vm, sampleSourceObj, "setHardwareType", "(I)V",
      //                                                hardwareType);
    };

    void onHumanSpikerBoardState(int boardState) override {
      //   backyardbrains::utils::JniHelper::invokeVoid(vm, sampleSourceObj,
      //                                                "setHumanSpikerBoardState", "(I)V",
      //                                                boardState);
    };

    void onHumanSpikerBoardAudioState(int boardState) override {
      //   backyardbrains::utils::JniHelper::invokeVoid(vm, sampleSourceObj,
      //                                                "setHumanSpikerBoardAudioState", "(I)V",
      //                                                boardState);
    };

    void onMaxSampleRateAndNumOfChannelsReply(int maxSampleRate, int channelCount) override {
      //   backyardbrains::utils::JniHelper::invokeVoid(vm, sampleSourceObj, "setSampleRate", "(I)V",
      //                                                maxSampleRate);
      //   backyardbrains::utils::JniHelper::invokeVoid(vm, sampleSourceObj, "setChannelCount", "(I)V",
      //                                                channelCount);
    };

    void onExpansionBoardTypeDetection(int expansionBoardType) override {
      //   backyardbrains::utils::JniHelper::invokeVoid(vm, sampleSourceObj, "setExpansionBoardType",
      //                                                "(I)V",
      //                                                expansionBoardType);
    }

private:

};


// Helper functions
static void initialize_processors() {
    if (!eventListener) {
        eventListener = new EventListener();
    }
    if (!amModulationProcessor) {
        amModulationProcessor = new AmModulationProcessor();
    }
    if (!sampleStreamProcessor) {
        sampleStreamProcessor = new SampleStreamProcessor(eventListener);
    }
    if (!thresholdProcessor) {
        thresholdProcessor = new ThresholdProcessor(new HeartbeatListener());
    }
    if (!fftProcessor) {
        fftProcessor = new FftProcessor();
    }
    if (!eventTriggeredAverageAnalysis) {
        eventTriggeredAverageAnalysis = new EventTriggeredAverageAnalysis();
    }
    if (!spikeAnalysis) {
        spikeAnalysis = new SpikeAnalysis();
    }
    if (!autocorrelationAnalysis) {
        autocorrelationAnalysis = new AutocorrelationAnalysis();
    }
    if (!isiAnalysis) {
        isiAnalysis = new IsiAnalysis();
    }
    if (!averageSpikeAnalysis) {
        averageSpikeAnalysis = new AverageSpikeAnalysis();
    }
    if (!crossCorrelationAnalysis) {
        crossCorrelationAnalysis = new CrossCorrelationAnalysis();
    }
}

static void cleanup_processors() {
    delete eventListener;
    delete amModulationProcessor;
    delete sampleStreamProcessor;
    delete thresholdProcessor;
    delete fftProcessor;
    delete eventTriggeredAverageAnalysis;
    delete spikeAnalysis;
    delete autocorrelationAnalysis;
    delete isiAnalysis;
    delete averageSpikeAnalysis;
    delete crossCorrelationAnalysis;

    eventListener = nullptr;
    amModulationProcessor = nullptr;
    sampleStreamProcessor = nullptr;
    thresholdProcessor = nullptr;
    fftProcessor = nullptr;
    eventTriggeredAverageAnalysis = nullptr;
    spikeAnalysis = nullptr;
    autocorrelationAnalysis = nullptr;
    isiAnalysis = nullptr;
    averageSpikeAnalysis = nullptr;
    crossCorrelationAnalysis = nullptr;
}

// Implementation of the public API
int32_t processing_init() {
    if (initialized) {
        return 0;
    }
    
    try {
        // Initialize default settings
        current_sample_rate = PROCESSING_DEFAULT_SAMPLE_RATE;
        current_channel_count = 1;
        current_bits_per_sample = PROCESSING_DEFAULT_BITS_PER_SAMPLE;
        current_selected_channel = 0;
        current_low_cut_off_freq = PROCESSING_MIN_FILTER_CUTOFF;
        current_high_cut_off_freq = PROCESSING_MAX_FILTER_CUTOFF;
        current_notch_filter_freq = PROCESSING_MIN_FILTER_CUTOFF;
        current_threshold = 0.0f;
        threshold_paused = false;
        averaging_sample_count = PROCESSING_DEFAULT_AVERAGED_SAMPLE_COUNT;
        averaging_trigger_type = 0;
        bpm_processing_enabled = false;

        // Initialize processors
        initialize_processors();
        
        initialized = true;
        return 0;
    } catch (...) {
        return -1;
    }
}

int32_t processing_set_sample_rate(int32_t sample_rate) {
    if (!initialized) {
        return -1;
    }
    
    if (sample_rate <= 0) {
        return -2;
    }
    
    try {
        current_sample_rate = sample_rate;
        sampleStreamProcessor->setSampleRate(sample_rate);
        fftProcessor->setSampleRate(sample_rate);
        return 0;
    } catch (...) {
        return -3;
    }
}

int32_t processing_set_channel_count(int32_t channel_count) {
    if (!initialized) {
        return -1;
    }
    
    if (channel_count <= 0 || channel_count > PROCESSING_MAX_CHANNELS) {
        return -2;
    }
    
    try {
        current_channel_count = channel_count;
        sampleStreamProcessor->setChannelCount(channel_count);
        fftProcessor->setChannelCount(channel_count);
        return 0;
    } catch (...) {
        return -3;
    }
}

int32_t processing_set_bits_per_sample(int32_t bits_per_sample) {
    if (!initialized) {
        return -1;
    }
    
    if (bits_per_sample <= 0) {
        return -2;
    }
    
    try {
        current_bits_per_sample = bits_per_sample;
        sampleStreamProcessor->setBitsPerSample(bits_per_sample);
        return 0;
    } catch (...) {
        return -3;
    }
}

int32_t processing_set_selected_channel(int32_t selected_channel) {
    if (!initialized) {
        return -1;
    }
    
    if (selected_channel < 0 || selected_channel >= current_channel_count) {
        return -2;
    }
    
    try {
        current_selected_channel = selected_channel;
        return 0;
    } catch (...) {
        return -3;
    }
}

int32_t processing_process_sample_stream(int16_t** out_samples, int32_t* out_sample_counts,
                                       const uint8_t* in_data, int32_t length,
                                       int32_t hardware_type) {
    if (!initialized || !out_samples || !out_sample_counts || !in_data || length <= 0) {
        return -1;
    }

    try {
        // Process data using SampleStreamProcessor
        int* event_indices = new int[PROCESSING_MAX_EVENTS];
        std::string* event_labels = new std::string[PROCESSING_MAX_EVENTS];
        int event_count = 0;

        sampleStreamProcessor->process(in_data, length, out_samples, out_sample_counts,
                                     event_indices, event_labels, event_count,
                                     current_channel_count, hardware_type);

        delete[] event_indices;
        delete[] event_labels;
        return 0;
    } catch (...) {
        return -3;
    }
}

int32_t processing_process_microphone_stream(int16_t** out_samples, int32_t* out_sample_counts,
                                           const uint8_t* in_data, int32_t length) {
    // For microphone stream, use hardware type 0 (default)
    return processing_process_sample_stream(out_samples, out_sample_counts, in_data, length, 0);
}

int32_t processing_process_playback_stream(int16_t** out_samples, int32_t* out_sample_counts,
                                         const uint8_t* in_data, int32_t length,
                                         const int32_t* event_indices, const char** event_names,
                                         int32_t event_count, int64_t start, int64_t end,
                                         int32_t prepend_samples) {
    if (!initialized || !out_samples || !out_sample_counts || !in_data || length <= 0) {
        return -1;
    }

    try {
        // Process data using SampleStreamProcessor with events
        int* out_event_indices = new int[PROCESSING_MAX_EVENTS];
        std::string* out_event_labels = new std::string[PROCESSING_MAX_EVENTS];
        int out_event_count = 0;

        sampleStreamProcessor->process(in_data, length, out_samples, out_sample_counts,
                                     out_event_indices, out_event_labels, out_event_count,
                                     current_channel_count, 0);

        delete[] out_event_indices;
        delete[] out_event_labels;
        return 0;
    } catch (...) {
        return -3;
    }
}

float processing_rms(const int16_t* data, int32_t length) {
    if (!initialized || !data || length <= 0) {
        return 0.0f;
    }
    
    try {
        return backyardbrains::utils::AnalysisUtils::RMS(const_cast<short*>(data), length);
    } catch (...) {
        return 0.0f;
    }
}

int32_t processing_normalize_signal(float* out_data, const int16_t* in_data, int32_t length,
                                  float in_min, float in_max, float out_min, float out_max) {
    if (!initialized || !out_data || !in_data || length <= 0) {
        return -1;
    }

    try {
        // First convert int16_t to float
        float* temp_data = new float[length];
        for (int32_t i = 0; i < length; i++) {
            temp_data[i] = static_cast<float>(in_data[i]);
        }

        // Then map to the desired range
        backyardbrains::utils::AnalysisUtils::map(temp_data, out_data, length, in_min, in_max, out_min, out_max);
        
        delete[] temp_data;
        return 0;
    } catch (...) {
        return -3;
    }
}

int32_t processing_process_fft(float** out_fft, int32_t* out_window_count,
                             int32_t* out_window_size, const int16_t** in_samples,
                             const int32_t* in_sample_counts) {
    if (!initialized || !out_fft || !out_window_count || !out_window_size || !in_samples || !in_sample_counts) {
        return -1;
    }

    try {
        fftProcessor->process(
            out_fft,
            PROCESSING_MAX_FFT_WINDOWS,  // Maximum window count
            *out_window_count,
            *out_window_size,
            current_channel_count,
            reinterpret_cast<short**>(const_cast<int16_t**>(in_samples)),
            const_cast<int*>(in_sample_counts)
        );
        return 0;
    } catch (...) {
        return -3;
    }
}

void processing_reset_fft_normalization() {
    if (initialized && fftProcessor) {
        fftProcessor->resetNormalization();
    }
}

int32_t processing_is_audio_stream_am_modulated() {
    if (!initialized) {
        return 0;
    }

    try {
        return amModulationProcessor->isReceivingAmSignal() ? 1 : 0;
    } catch (...) {
        return 0;
    }
}

int32_t processing_get_averaged_sample_count() {
    return averaging_sample_count;
}

void processing_set_averaged_sample_count(int32_t count) {
    if (count > 0) {
        averaging_sample_count = count;
        if (thresholdProcessor) {
            thresholdProcessor->setAveragedSampleCount(count);
        }
    }
}

int32_t processing_get_averaging_trigger_type() {
    return thresholdProcessor ? thresholdProcessor->getTriggerType() : 0;
}

void processing_set_averaging_trigger_type(int32_t type) {
    if (thresholdProcessor) {
        thresholdProcessor->setTriggerType(type);
    }
}

void processing_set_threshold(float threshold) {
    current_threshold = threshold;
    if (thresholdProcessor) {
        thresholdProcessor->setThreshold(threshold);
    }
}

void processing_reset_threshold() {
    current_threshold = 0.0f;
    if (thresholdProcessor) {
        thresholdProcessor->setThreshold(0.0f);
    }
}

void processing_resume_threshold() {
    threshold_paused = false;
    if (thresholdProcessor) {
        thresholdProcessor->setPaused(false);
    }
}

void processing_pause_threshold() {
    threshold_paused = true;
    if (thresholdProcessor) {
        thresholdProcessor->setPaused(true);
    }
}

int32_t processing_process_threshold(int16_t** out_samples, int32_t* out_sample_counts,
                                   const int16_t** in_samples, const int32_t* in_sample_counts,
                                   bool average_samples) {
    if (!initialized || !out_samples || !out_sample_counts || !in_samples || !in_sample_counts) {
        return -1;
    }

    try {
        if (!average_samples) {
            thresholdProcessor->appendIncomingSamples(
                reinterpret_cast<short**>(const_cast<int16_t**>(in_samples)),
                const_cast<int*>(in_sample_counts)
            );
            return 0;
        }

        // For averaging samples, we need to pass empty arrays for events since they're not used
        int* empty_event_indices = nullptr;
        int* empty_events = nullptr;
        int empty_event_count = 0;

        thresholdProcessor->process(
            reinterpret_cast<short**>(const_cast<int16_t**>(out_samples)),
            const_cast<int*>(out_sample_counts),
            reinterpret_cast<short**>(const_cast<int16_t**>(in_samples)),
            const_cast<int*>(in_sample_counts),
            empty_event_indices,
            empty_events,
            empty_event_count
        );
        return 0;
    } catch (...) {
        return -3;
    }
}

void processing_set_bpm_processing(bool process_bpm) {
    bpm_processing_enabled = process_bpm;
    if (thresholdProcessor) {
        thresholdProcessor->setBpmProcessing(process_bpm);
    }
}

int32_t processing_prepare_signal_for_drawing(float** out_samples, int32_t* out_sample_counts,
                                           float* out_event_indices, int32_t* out_event_count,
                                           const int16_t** in_samples, int32_t channel_count,
                                           const int32_t* in_event_indices, int32_t in_event_count,
                                           int32_t from_sample, int32_t to_sample,
                                           int32_t draw_surface_width) {
    if (!initialized || !out_samples || !out_sample_counts || !out_event_indices || !out_event_count ||
        !in_samples || !in_event_indices || channel_count <= 0 || draw_surface_width <= 0) {
        return -1;
    }

    try {
        int outEventCount = 0;
        backyardbrains::utils::DrawingUtils::prepareSignalForDrawing(
            out_samples,
            out_sample_counts,
            out_event_indices,
            outEventCount,
            reinterpret_cast<short**>(const_cast<int16_t**>(in_samples)),
            channel_count,
            const_cast<int*>(in_event_indices),
            in_event_count,
            from_sample,
            to_sample,
            draw_surface_width
        );
        *out_event_count = outEventCount;
        return 0;
    } catch (...) {
        return -3;
    }
}

int32_t processing_prepare_fft_for_drawing(float* out_vertices, int16_t* out_indices,
                                         float* out_colors, int32_t* out_vertex_count,
                                         int32_t* out_index_count, int32_t* out_color_count,
                                         float** fft_data, int32_t window_count,
                                         int32_t window_size, float width, float height) {
    if (!initialized || !out_vertices || !out_indices || !out_colors ||
        !out_vertex_count || !out_index_count || !out_color_count ||
        !fft_data || window_count <= 0 || window_size <= 0) {
        return -1;
    }

    try {
        int vertexCount = 0;
        int indexCount = 0;
        int colorCount = 0;
        backyardbrains::utils::DrawingUtils::prepareFftForDrawing(
            out_vertices,
            reinterpret_cast<short*>(out_indices),
            out_colors,
            vertexCount,
            indexCount,
            colorCount,
            fft_data,
            window_count,
            window_size,
            width,
            height
        );
        *out_vertex_count = vertexCount;
        *out_index_count = indexCount;
        *out_color_count = colorCount;
        return 0;
    } catch (...) {
        return -3;
    }
}

int32_t processing_prepare_spikes_for_drawing(float* out_vertices, float* out_colors,
                                            int32_t* out_vertex_count, int32_t* out_color_count,
                                            const float* in_spike_vertices,
                                            const int32_t* in_spike_indices,
                                            int32_t spike_count,
                                            const float* color_in_range,
                                            const float* color_out_of_range,
                                            int32_t range_start_index,
                                            int32_t range_end_index,
                                            float sample_start,
                                            int32_t sample_end,
                                            int32_t draw_start,
                                            int32_t draw_end,
                                            int32_t sample_count,
                                            int32_t width) {
    if (!initialized || !out_vertices || !out_colors || !out_vertex_count || !out_color_count ||
        !in_spike_vertices || !in_spike_indices || spike_count <= 0 ||
        !color_in_range || !color_out_of_range || width <= 0) {
        return -1;
    }

    try {
        int vertexCount = 0;
        int colorCount = 0;
        backyardbrains::utils::DrawingUtils::prepareSpikesForDrawing(
            out_vertices,
            out_colors,
            vertexCount,
            colorCount,
            const_cast<float*>(in_spike_vertices),
            const_cast<int*>(in_spike_indices),
            spike_count,
            const_cast<float*>(color_in_range),
            const_cast<float*>(color_out_of_range),
            range_start_index,
            range_end_index,
            sample_start,
            sample_end,
            draw_start,
            draw_end,
            sample_count,
            width
        );
        *out_vertex_count = vertexCount;
        *out_color_count = colorCount;
        return 0;
    } catch (...) {
        return -3;
    }
}

int32_t processing_parse_events(const char* file_path, float sample_rate,
                              int32_t* event_indices, char** event_names) {
    if (!initialized || !file_path || !event_indices || !event_names) {
        return -1;
    }
    
    try {
        // Pre-allocate a reasonably large buffer for events
        const int MAX_EVENTS = 1000; // Adjust this based on your needs
        auto* event_times = new float[MAX_EVENTS];
        auto* event_names_temp = new std::string[MAX_EVENTS];
        int32_t event_count = 0;
        
        // Call parseEvents with raw arrays instead of vectors
        backyardbrains::utils::EventUtils::parseEvents(file_path, event_times, event_names_temp, event_count);
        
        // Convert the results
        for (int32_t i = 0; i < event_count; i++) {
            event_indices[i] = static_cast<int32_t>(event_times[i] * sample_rate);
            strcpy(event_names[i], event_names_temp[i].c_str());
        }
        
        // Cleanup
        delete[] event_times;
        delete[] event_names_temp;
        
        return event_count;
    } catch (...) {
        return -3;
    }
}

int32_t processing_check_events(const char* file_path, char** event_names) {
    if (!initialized || !file_path || !event_names) {
        return -1;
    }
    
    try {
        // Pre-allocate a reasonably large buffer for events
        const int MAX_EVENTS = 1000; // Adjust this based on your needs
        auto* event_names_temp = new std::string[MAX_EVENTS];
        int32_t event_count = 0;
        
        // Call checkEvents with raw array instead of vector
        backyardbrains::utils::EventUtils::checkEvents(file_path, event_names_temp, event_count);
        
        // Copy results to output array
        for (int32_t i = 0; i < event_count; i++) {
            strcpy(event_names[i], event_names_temp[i].c_str());
        }
        
        // Cleanup
        delete[] event_names_temp;
        
        return event_count;
    } catch (...) {
        return -3;
    }
}

void processing_event_triggered_average_analysis(const char* file_path,
                                               const char* events_file_path,
                                               const char** events,
                                               int32_t event_count,
                                               float** averages,
                                               float** norm_averages,
                                               float** norm_mc_averages,
                                               float** norm_mc_top,
                                               float** norm_mc_bottom,
                                               float* min_max,
                                               int32_t channel_count,
                                               int32_t frame_count,
                                               bool remove_noise_intervals,
                                               const char* confidence_intervals_event) {
    if (!initialized || !eventTriggeredAverageAnalysis) {
        return;
    }
    
    try {
        // Convert char** to string array
        auto* event_names = new std::string[event_count];
        for (int32_t i = 0; i < event_count; i++) {
            event_names[i] = std::string(events[i]);
        }
        
        float*** averages_ptr = &averages;
        float*** norm_averages_ptr = &norm_averages;
        
        eventTriggeredAverageAnalysis->process(
            file_path,                    // signalFilePath
            events_file_path,             // eventsFilePath
            event_names,                  // processedEvents
            event_count,                  // processedEventCount
            remove_noise_intervals,       // removeNoiseIntervals
            confidence_intervals_event,   // confidenceIntervalsEvent
            averages_ptr,                 // averages
            norm_averages_ptr,            // normAverages
            norm_mc_averages,            // normMcAverages
            norm_mc_top,                 // normMcTop
            norm_mc_bottom,              // normMcBottom
            &min_max[0],                 // min
            &min_max[1]                  // max
        );

        delete[] event_names;
    } catch (...) {
        // Handle errors
    }
}

int32_t** processing_find_spikes(const char* file_path,
                                int16_t** values_pos,
                                int32_t** indices_pos,
                                float** times_pos,
                                int16_t** values_neg,
                                int32_t** indices_neg,
                                float** times_neg,
                                int32_t channel_count,
                                int32_t max_spikes) {
    if (!initialized || !spikeAnalysis) {
        return nullptr;
    }
    
    try {
        // Allocate arrays for counts
        auto* pos_counts = new int[channel_count];
        auto* neg_counts = new int[channel_count];
        
        spikeAnalysis->findSpikes(
            file_path,
            values_pos, indices_pos, times_pos,
            values_neg, indices_neg, times_neg,
            pos_counts, neg_counts
        );

        // Convert the counts to the return format
        auto** result = new int32_t*[channel_count];
        for (int32_t i = 0; i < channel_count; i++) {
            result[i] = new int32_t[2];
            result[i][0] = pos_counts[i];
            result[i][1] = neg_counts[i];
        }

        delete[] pos_counts;
        delete[] neg_counts;
        
        return result;
    } catch (...) {
        return nullptr;
    }
}

void processing_autocorrelation_analysis(float** spike_trains,
                                       int32_t spike_train_count,
                                       int32_t* spike_counts,
                                       int32_t** analysis,
                                       int32_t analysis_bin_count) {
    if (!initialized || !autocorrelationAnalysis) {
        return;
    }
    
    try {
        autocorrelationAnalysis->process(
            spike_trains, spike_train_count,
            spike_counts, analysis, analysis_bin_count
        );
    } catch (...) {
        // Handle errors
    }
}

void processing_isi_analysis(float** spike_trains,
                           int32_t spike_train_count,
                           int32_t* spike_counts,
                           int32_t** analysis,
                           int32_t analysis_bin_count) {
    if (!initialized || !isiAnalysis) {
        return;
    }
    
    try {
        isiAnalysis->process(
            spike_trains, spike_train_count,
            spike_counts, analysis, analysis_bin_count
        );
    } catch (...) {
        // Handle errors
    }
}

void processing_cross_correlation_analysis(float** spike_trains,
                                         int32_t spike_train_count,
                                         int32_t* spike_counts,
                                         int32_t** analysis,
                                         int32_t analysis_bin_count) {
    if (!initialized || !crossCorrelationAnalysis) {
        return;
    }
    
    try {
        crossCorrelationAnalysis->process(
            spike_trains, spike_train_count,
            spike_counts, analysis,
            analysis_bin_count  // Removed analysis_count parameter
        );
    } catch (...) {
        // Handle errors
    }
}

void processing_average_spike_analysis(const char* file_path,
                                     int32_t** spike_trains,
                                     int32_t spike_train_count,
                                     int32_t* spike_counts,
                                     float** average_spike,
                                     float** norm_average_spike,
                                     float** norm_top_std_line,
                                     float** norm_bottom_std_line,
                                     int32_t batch_spike_count) {
    if (!initialized || !averageSpikeAnalysis) {
        return;
    }
    
    try {
        averageSpikeAnalysis->process(
            file_path, spike_trains,
            spike_train_count, spike_counts,
            average_spike, norm_average_spike,
            norm_top_std_line, norm_bottom_std_line,
            batch_spike_count
        );
    } catch (...) {
        // Handle errors
    }
}

void processing_cleanup() {
    cleanup_processors();
    initialized = false;
}

int32_t processing_set_band_filter(float low_cut_off_freq, float high_cut_off_freq) {
    if (!initialized) {
        return -1;  // Not initialized
    }
    
    try {
        // Store values in internal state
        current_low_cut_off_freq = low_cut_off_freq;
        current_high_cut_off_freq = high_cut_off_freq;
        
        // Apply to all processors (same as in byb-lib.cpp)
        if (amModulationProcessor) {
            amModulationProcessor->setBandFilter(low_cut_off_freq, high_cut_off_freq);
        }
        
        if (sampleStreamProcessor) {
            sampleStreamProcessor->setBandFilter(low_cut_off_freq, high_cut_off_freq);
        }
        
        if (thresholdProcessor) {
            thresholdProcessor->setBandFilter(low_cut_off_freq, high_cut_off_freq);
        }
        
        if (fftProcessor) {
            fftProcessor->setBandFilter(low_cut_off_freq, high_cut_off_freq);
        }
        
        return 0;  // Success
    } catch (...) {
        return -3;  // Processing error
    }
}

int32_t processing_set_notch_filter(float center_freq) {
    if (!initialized) {
        return -1;  // Not initialized
    }
    
    try {
        // Store value in internal state
        current_notch_filter_freq = center_freq;
        
        // Apply to all processors (same as in byb-lib.cpp)
        if (amModulationProcessor) {
            amModulationProcessor->setNotchFilter(center_freq);
        }
        
        if (sampleStreamProcessor) {
            sampleStreamProcessor->setNotchFilter(center_freq);
        }
        
        if (thresholdProcessor) {
            thresholdProcessor->setNotchFilter(center_freq);
        }
        
        if (fftProcessor) {
            fftProcessor->setNotchFilter(center_freq);
        }
        
        return 0;  // Success
    } catch (...) {
        return -3;  // Processing error
    }
}

int32_t processing_map(float* out_data, const float* in_data, int32_t length,
                      float in_min, float in_max, float out_min, float out_max) {
    if (!initialized || !out_data || !in_data || length <= 0) {
        return -1;
    }
    
    try {
        backyardbrains::utils::AnalysisUtils::map(const_cast<float*>(in_data), out_data, length, in_min, in_max, out_min, out_max);
        return 0;
    } catch (...) {
        return -3;
    }
}

int32_t processing_prepare_for_signal_drawing(float* out_signal,
                                            int32_t* out_events,
                                            float** in_signal,
                                            int32_t in_frame_count,
                                            int32_t* in_event_indices,
                                            int32_t in_event_count,
                                            int32_t draw_start_index,
                                            int32_t draw_end_index,
                                            int32_t draw_surface_width) {
    if (!initialized || !out_signal || !out_events || !in_signal || 
        in_frame_count <= 0 || draw_surface_width <= 0) {
        return -1;
    }

    try {
        // Calculate maximum sample count (same as in JNI implementation)
        int32_t max_sample_count = draw_surface_width * 5;  // x5 when enveloping (from testing)
        int32_t max_event_count = 100;

        // Convert float samples to short for DrawingUtils
        auto** in_samples = new short*[1];  // Assuming 1 channel for now
        in_samples[0] = new short[in_frame_count];
        for (int i = 0; i < in_frame_count; i++) {
            in_samples[0][i] = static_cast<short>(in_signal[0][i]);
        }

        // Prepare arrays for drawing
        float* out_vertices = new float[max_sample_count];
        int32_t out_vertex_count = 0;
        float* out_event_indices = new float[max_event_count];
        int32_t out_event_count = 0;

        // Call DrawingUtils to prepare the signal for drawing
        backyardbrains::utils::DrawingUtils::prepareSignalForDrawing(
            &out_vertices,  // Output vertices array
            &out_vertex_count,  // Output vertex count
            out_event_indices,  // Output event indices array
            out_event_count,  // Output event count
            in_samples,  // Input samples array
            1,  // Channel count (assuming 1 channel for now)
            in_event_indices,  // Input event indices
            in_event_count,  // Input event count
            draw_start_index,  // Draw start index
            draw_end_index,  // Draw end index
            draw_surface_width  // Draw surface width
        );

        // Copy results to output arrays
        std::memcpy(out_signal, out_vertices, out_vertex_count * sizeof(float));
        std::memcpy(out_events, out_event_indices, out_event_count * sizeof(float));

        // Clean up
        delete[] out_vertices;
        delete[] out_event_indices;
        delete[] in_samples[0];
        delete[] in_samples;

        return 0;
    } catch (...) {
        return -3;
    }
}
