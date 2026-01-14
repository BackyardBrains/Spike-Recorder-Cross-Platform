#define BUILDING_DLL
#include "processing.h"
#include <cmath>
#include <vector>
#include <cstring>
#include <algorithm>
#include <string>
#ifdef __ANDROID__
#include <android/log.h>
#endif


#define IS_WIN32 defined(WIN32) || defined(_WIN32) || defined(__WIN32)
void platform_log_processing(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
#ifdef __ANDROID__
    __android_log_vprint(ANDROID_LOG_VERBOSE, "ndk", fmt, args);
#else
    vprintf(fmt, args);
#endif
    va_end(args);
}

#ifdef _WIN32
    #include <windows.h>
    #include <time.h>

    // Windows implementation of timeval if not already defined
  /*  #ifndef _TIMEVAL_DEFINED
    #define _TIMEVAL_DEFINED
    struct timeval {
        long tv_sec;
        long tv_usec;
    };
    #endif*/

    // Windows implementation of timezone if not already defined
    #ifndef _TIMEZONE_DEFINED
    #define _TIMEZONE_DEFINED
    struct timezone {
        int tz_minuteswest;
        int tz_dsttime;
    };
    #endif

    // Implementation of gettimeofday for Windows
    int gettimeofday(struct timeval* tp, struct timezone* tzp);
#else
    #include <sys/time.h>
#endif
#include "DebuggingLogBYB.h"

using namespace backyardbrains::filters;
using namespace backyardbrains::processing;
using namespace backyardbrains::analysis;
using namespace backyardbrains::utils;

// Constants
static constexpr int32_t PROCESSING_MAX_EVENTS = 100;  // Same as MAX_EVENTS in SampleStreamProcessor
static constexpr int32_t MAX_NUMBER_OF_SECONDS = 10;  // 10 seconds of buffer
static constexpr int32_t BUFFER_MULTIPLIER = 1;
static constexpr int32_t MAX_DRAW_SURFACE_WIDTH = 4096;  // Cap to prevent OOM on high-DPI devices

// Internal state variables
static bool isProcessThresholding = false;
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

static int max_fft_windows_count = 1;
static constexpr float FFT_PROCESSING_TIME = 10.0f;
static constexpr float FFT_SAMPLE_RATE = 128; // 2^7
static constexpr int FFT_WINDOW_TIME_LENGTH = 4; // 2^2
static constexpr int FFT_WINDOW_OVERLAP_PERCENT = 99;


#ifdef _WIN32
// Windows implementation of gettimeofday
int gettimeofday(struct timeval* tp, struct timezone* tzp) {
    // Note: some broken versions only have 8 trailing zero's, the correct epoch has 9 trailing zero's
    // This magic number is the number of 100 nanosecond intervals since January 1, 1601 (UTC)
    // until 00:00:00 January 1, 1970
    static const uint64_t EPOCH = ((uint64_t)116444736000000000ULL);

    SYSTEMTIME system_time;
    FILETIME file_time;
    uint64_t time;

    GetSystemTime(&system_time);
    SystemTimeToFileTime(&system_time, &file_time);
    time = ((uint64_t)file_time.dwLowDateTime);
    time += ((uint64_t)file_time.dwHighDateTime) << 32;

    tp->tv_sec = (long)((time - EPOCH) / 10000000L);
    tp->tv_usec = (long)(system_time.wMilliseconds * 1000);
    return 0;
}
#endif


//Class for multichannel circular buffer with int16_t samples
//It has headIndex and tailIndex
//it has setup function that initialize channel buffers based on sample rate and channel count
//number of samples for each channel is sample rate * MAX_NUMBER_OF_SECONDS (default is 10 seconds)
class CircularBuffer {
      public:
            CircularBuffer(int sampleRate, int channelCount) {
                  this->sampleRate = sampleRate;
                  this->channelCount = channelCount;
                  this->buffer = nullptr; // Initialize to nullptr before setup
                  
                  // Call setup directly in the constructor
                  this->setup(sampleRate, channelCount);
            }
            
            void setup(int sampleRate, int channelCount) {
                  //check if buffer is already initialized, if yes release the memory
                  if (this->buffer != nullptr) {
                        for (int i = 0; i < this->channelCount; i++) {
                              delete[] this->buffer[i];
                        }
                        delete[] this->buffer;
                  }
                  
                  //check if sample rate is valid
                  
                  this->sampleRate = sampleRate;
                  this->channelCount = channelCount;
                  this->bufferSize = sampleRate * MAX_NUMBER_OF_SECONDS * BUFFER_MULTIPLIER;
                  this->buffer = new int16_t*[channelCount];
                  this->headIndex = new int32_t[channelCount];
                  this->tailIndex = new int32_t[channelCount];

                  for (int i = 0; i < channelCount; i++) {
                        this->buffer[i] = new int16_t[bufferSize];
                        
                        for (int j = 0; j < bufferSize; j++) {
                              this->buffer[i][j] = 0;
                        }
                        headIndex[i] = 0;
                        tailIndex[i] = 0;
                  }
            }

            // Add data to circular buffer
            void addData(int16_t** samples, int32_t* sampleCount) {
                  if (buffer == nullptr) {
                        return;
                  }
                 
                  // Add samples to buffer for each channel
                  try {
                        for (int chan = 0; chan < channelCount; chan++) {
                
                              
                              for (int i = 0; i < sampleCount[chan]; i++) {
                                    try {
                                        // Store sample at current head position
                                        int16_t temp_sample = samples[chan][i];
                                        buffer[chan][headIndex[chan]] = temp_sample;
                                        
                                        // Move head forward, wrapping around if needed
                                        headIndex[chan] = (headIndex[chan] + 1) % bufferSize;
                                        
                                        // If head catches up to tail, move tail forward
                                        if (headIndex[chan] == tailIndex[chan]) {
                                            
                                            tailIndex[chan] = (tailIndex[chan] + 1) % bufferSize;
                                        }
                                    } catch (const std::exception& e) {
                                        log_debug("Error processing sample %d in channel %d: %s", i, chan, e.what());
                                        throw; // Re-throw to be caught by outer catch
                                    }
                              }
                        }

                  } catch (const std::exception& e) {
                        log_debug("Critical error in buffer processing: %s", e.what());
                        log_debug("State: headIndex=%d, tailIndex=%d, bufferSize=%d", headIndex, tailIndex, bufferSize);
                        throw; // Re-throw if you want the error to propagate up
                  }
            }
            
            // Get the most recent N samples
            void getRecentSamples(int16_t** outputBuffer, int32_t numSamples) {
                  if (buffer == nullptr || numSamples <= 0) {
                        return;
                  }
                  
                  // Calculate starting position (going backward from head)
                  
                  // Copy samples to output buffer
                  for (int chan = 0; chan < channelCount; chan++) {
                    int32_t startPos = (headIndex[chan] - numSamples + bufferSize) % bufferSize;
                    for (int i = 0; i < numSamples; i++) {
                        int32_t bufferPos = (startPos + i) % bufferSize;
                        outputBuffer[chan][i] = buffer[chan][bufferPos];
                    }
                  }
            }

            // Add this method to the CircularBuffer class
            void getDataForDrawing(int16_t** outputBuffer, int32_t fromSample, int32_t toSample) {
                  if (buffer == nullptr || outputBuffer == nullptr) {
                        return;
                  }
                  
                  // Calculate number of samples requested
                  int32_t sampleCount = toSample - fromSample + 1;
                  if (sampleCount <= 0) {
                        return;
                  }

                            
                  // Prepare the data (either from the actual position or wrapping around)
                  for (int chan = 0; chan < channelCount; chan++) {
                        if (outputBuffer[chan] == nullptr) {
                              continue; // Skip invalid channel buffer
                        }
                        // Check if buffer[chan] is valid before accessing it
                        // This prevents crash when USB device is disconnected and buffer is deallocated
                        if (buffer[chan] == nullptr) {
                              // Fill with zeros if buffer is invalid (device disconnected)
                              for (int i = 0; i < sampleCount; i++) {
                                    outputBuffer[chan][i] = 0;
                              }
                              continue;
                        }
                        for (int i = 0; i < sampleCount; i++) {
                              int32_t bufferPos = (headIndex[chan] - (toSample - i) + bufferSize) % bufferSize;
                            //   if (fromSample > 0) {
                            //       platform_log("HEAD\n");
                            //       platform_log(std::to_string(headIndex[chan]).c_str());
                            //       platform_log("\nTOSAMPLE-i\n");
                            //       platform_log(std::to_string(toSample - i).c_str());
                            //       platform_log("\nBUFFERSIZE\n");
                            //       platform_log(std::to_string(bufferSize).c_str());
                            //       platform_log("===========\n");
                            //   }

                              outputBuffer[chan][i] = buffer[chan][bufferPos];
                        }
                  }

            }
      private:
            int sampleRate;
            int channelCount;
            int bufferSize;
            int16_t** buffer;
            int32_t* headIndex; // Position to write next sample
            int32_t* tailIndex; // Oldest valid sample position
};

//create a new static instance of CircularBuffer
static CircularBuffer* circularBuffer = nullptr;
static CircularBuffer* circularBufferThreshold = nullptr;


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


    void onEventFound(int sampleIndex, int eventLabel) override {
        // platform_log("EVENT FOUND\n");
        // platform_log(std::to_string(sampleIndex).c_str());
        // platform_log("EVENT LABLE\n");
        // platform_log(std::to_string(eventLabel).c_str());
        // EM_ASM({
        //     postMessage({
        //         "message": "EVENT_FOUND",
        //         "sampleIndex": sampleIndex,
        //         "eventLabel": eventLabel,
        //     });
        //     console.log( $0, $1 );
        // }, sampleIndex, eventLabel);        
    }
    void onSpikerBoxHardwareTypeDetected(int hardwareType) override {
      //   backyardbrains::utils::JniHelper::invokeVoid(vm, sampleSourceObj, "setHardwareType", "(I)V",
      //                                                hardwareType);
    };

    void onMaxSampleRateAndNumOfChannelsReply(int maxSampleRate, int channelCount) override {
        // Implementation for max sample rate and channel count reply
    }

    void onExpansionBoardTypeDetection(int expansionBoardType) override {
        // Implementation for expansion board type detection
    }

    void onHumanSpikerBoardState(int boardState) override {
        // Implementation for human spiker board state
    }

    void onHumanSpikerBoardAudioState(int boardState) override {
        // Implementation for human spiker board audio state
    }


private:

};


// Helper functions
static void initialize_processors() {

    log_debug("initialize_processors");
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
PROCESSING_API int32_t processing_init() {
    if (initialized) {
        return 0;
    }
    log_debug("Processing init");
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
        
        // Initialize the circular buffer
        if (circularBuffer == nullptr) {
            circularBuffer = new CircularBuffer(current_sample_rate, current_channel_count);
            circularBufferThreshold = new CircularBuffer(current_sample_rate, current_channel_count);
        }
        
        initialized = true;
        return 0;
    } catch (...) {
        return -1;
    }
}

int32_t* outInfo;
PROCESSING_API int32_t processing_get_information(int32_t* _outInfo) {
    outInfo = _outInfo;
    outInfo[0] = current_sample_rate;
    outInfo[1] = current_channel_count;
    outInfo[2] = current_bits_per_sample;
    outInfo[3] = current_selected_channel;
    return 0;
}

PROCESSING_API int32_t processing_set_sample_rate(int32_t sample_rate) {
    if (!initialized) {
        return -1;
    }
    
    if (sample_rate <= 0) {
        return -2;
    }
    
    try {
        current_sample_rate = sample_rate;

        uint32_t FFT_WINDOW_SAMPLE_COUNT = static_cast<const uint32_t>(FFT_WINDOW_TIME_LENGTH * FFT_SAMPLE_RATE); // 2^9
        int FFT_WINDOW_SAMPLE_DIFF_COUNT = (int) (FFT_WINDOW_SAMPLE_COUNT * (1.0f - (FFT_WINDOW_OVERLAP_PERCENT / 100.0f)));
        amModulationProcessor->setSampleRate( sample_rate );
        thresholdProcessor->setSampleRate( sample_rate );
        sampleStreamProcessor->setSampleRate(sample_rate);
        fftProcessor->setSampleRate(sample_rate);


        max_fft_windows_count = (int) ((FFT_PROCESSING_TIME * FFT_SAMPLE_RATE) / FFT_WINDOW_SAMPLE_DIFF_COUNT);

        // Re-setup the circular buffer when sample rate changes
        if (circularBuffer != nullptr) {
            circularBuffer->setup(current_sample_rate, current_channel_count);
            circularBufferThreshold->setup(current_sample_rate, current_channel_count);
        }
        
        return 0;
    } catch (...) {
        return -3;
    }
}

PROCESSING_API int32_t processing_set_channel_count(int32_t channel_count) {
    if (!initialized) {
        return -1;
    }
    
    if (channel_count <= 0 || channel_count > PROCESSING_MAX_CHANNELS) {
        return -2;
    }
    
    try {
        current_channel_count = channel_count;
        amModulationProcessor->setChannelCount(channel_count);
        thresholdProcessor->setChannelCount( channel_count );
        sampleStreamProcessor->setChannelCount(channel_count);
        fftProcessor->setChannelCount(channel_count);
        
        // Re-setup the circular buffer when channel count changes
        if (circularBuffer != nullptr) {
            circularBuffer->setup(current_sample_rate, current_channel_count);
            circularBufferThreshold->setup(current_sample_rate, current_channel_count);
        }
        
        return 0;
    } catch (...) {
        return -3;
    }
}

PROCESSING_API int32_t processing_set_bits_per_sample(int32_t bits_per_sample) {
    if (!initialized) {
        return -1;
    }
    
    if (bits_per_sample <= 0) {
        return -2;
    }
    
    try {
        current_bits_per_sample = bits_per_sample;
        sampleStreamProcessor->setBitsPerSample(bits_per_sample);
        thresholdProcessor->setBitsPerSample(bits_per_sample);
        return 0;
    } catch (...) {
        return -3;
    }
}

PROCESSING_API int32_t processing_set_selected_channel(int32_t selected_channel) {
    if (!initialized) {
        return -1;
    }
    
    if (selected_channel < 0 || selected_channel >= current_channel_count) {
        return -2;
    }
    
    try {
        current_selected_channel = selected_channel;
        thresholdProcessor->setSelectedChannel(selected_channel);        
        return 0;
    } catch (...) {
        return -3;
    }
}

PROCESSING_API int32_t processing_process_sample_stream(int16_t** out_samples, int32_t* out_sample_counts,
                                       const uint8_t* in_data, int32_t length,
                                       int32_t hardware_type) {
    if (!initialized || !out_samples || !out_sample_counts || !in_data || length <= 0) {
        return -1;
    }
    // isProcessThresholding = false;
    
    // Check if sampleStreamProcessor is initialized
    if (sampleStreamProcessor == nullptr) {
        return -2; // Return error code indicating processor not initialized
    }
    
    try {
        // Process data using SampleStreamProcessor
        int* event_indices = new int[PROCESSING_MAX_EVENTS];
        std::string* event_labels = new std::string[PROCESSING_MAX_EVENTS];
        int event_count = 0;
        sampleStreamProcessor->process(in_data, length, out_samples, out_sample_counts,
                                     event_indices, event_labels, event_count,
                                     current_channel_count, hardware_type);
        // Add processed data to circular buffer
        if (circularBuffer != nullptr) {
            // if (out_sample_counts[0]>0) {
                circularBuffer->addData(out_samples, out_sample_counts);
            // }
        } else {
            delete[] event_indices;
            delete[] event_labels;
            return -100;
        }
        



        delete[] event_indices;
        delete[] event_labels;
        return out_sample_counts[0];
    } catch (...) {
        return -3;
    }
}

PROCESSING_API int32_t processing_process_microphone_stream(int16_t** out_samples, int32_t* out_sample_counts,
                                           const uint8_t* in_data, int32_t length) {
      if (!initialized || !out_samples || !out_sample_counts || !in_data || length <= 0) {
            return -1;
      }
      
      // Check if amModulationProcessor is initialized
      if (amModulationProcessor == nullptr) {
          return -2; // Return error code indicating processor not initialized
      }
      
      // Check if all out_samples channel pointers are valid
      for (int i = 0; i < current_channel_count; i++) {
          if (out_samples[i] == nullptr) {
              return -3; // Return error code indicating invalid output buffer
          }
      }
      
    //   isProcessThresholding = false;
      //log_debug("Processing microphone data: length=%d", length);

      try {
            // Calculate sample count based on bits per sample
            int32_t sample_count = length * 8 / current_bits_per_sample;
            int32_t frame_count = sample_count / current_channel_count;

  
            // Store the AM modulation state before processing
            bool is_receiving_am_signal_before = amModulationProcessor->isReceivingAmSignal();
            
            // Process the audio data through AM modulation processor
            // Note: amModulationProcessor expects interleaved samples as input 
            // and will handle deinterleaving internally

            // Allocate array of pointers for each channel (like in byb-lib.cpp)
            int16_t** channel_samples = new int16_t*[current_channel_count];
            for (int i = 0; i < current_channel_count; i++) {
                  channel_samples[i] = new int16_t[frame_count]{0};
            }

            // Pass channel_samples to amModulationProcessor, not out_samples
            amModulationProcessor->process(
                  reinterpret_cast<short*>(const_cast<uint8_t*>(in_data)),
                  channel_samples,  // Use channel_samples instead of out_samples
                  sample_count,
                  frame_count
            );
            // platform_log_processing("\n length 0 0\n");
            // platform_log_processing(std::to_string(length).c_str());
            // platform_log_processing("\n sample_count 0 0\n");
            // platform_log_processing(std::to_string(sample_count).c_str());

            // Add processed data to circular buffer
            if (circularBuffer != nullptr) {
                int32_t* frame_counts = new int32_t[1];
                frame_counts[0] = frame_count;
                circularBuffer->addData(channel_samples, frame_counts);
                delete[] frame_counts;
            }
           
            // Copy processed data from channel_samples to out_samples
            for (int i = 0; i < current_channel_count; i++) {
                  if (out_samples[i] != nullptr && channel_samples[i] != nullptr) {
                      std::copy(channel_samples[i], channel_samples[i] + frame_count, out_samples[i]);
                  }
            }
            
            // Clean up channel_samples to avoid memory leaks
            for (int i = 0; i < current_channel_count; i++) {
                  delete[] channel_samples[i];
            }
            delete[] channel_samples;
            
            // Check if AM modulation state changed (for potential callbacks)
            bool is_receiving_am_signal_after = amModulationProcessor->isReceivingAmSignal();

            // Set output sample counts for all channels
            for (int i = 0; i < current_channel_count; i++) {
                  out_sample_counts[i] = frame_count;
            }

            return 0;
      } catch (...) {
            log_debug("Exception ");
            return -3;
      }
}

// int32_t processing_process_threshold_stream(int16_t** out_samples, int32_t* out_sample_counts,
//                                            const uint8_t* in_data, int32_t length) {
//     if (!initialized || !out_samples || !out_sample_counts || !in_data || length <= 0) {
//         return -1;
//     }

//     try {
//         int32_t sample_count = length * 8 / current_bits_per_sample;
//         int32_t frame_count = sample_count / current_channel_count;

//         // Prepare deinterleaved input buffers for the threshold processor
//         auto** in_samples = new int16_t*[current_channel_count];
//         auto* in_sample_counts = new int[current_channel_count];
//         for (int ch = 0; ch < current_channel_count; ch++) {
//             in_samples[ch] = new int16_t[frame_count];
//             in_sample_counts[ch] = frame_count;
//         }

//         const int16_t* ptr = reinterpret_cast<const int16_t*>(in_data);
//         for (int frame = 0; frame < frame_count; ++frame) {
//             for (int ch = 0; ch < current_channel_count; ++ch) {
//                 in_samples[ch][frame] = ptr[frame * current_channel_count + ch];
//             }
//         }

//         // Events are not used when processing stream data
//         thresholdProcessor->process(
//             out_samples,
//             out_sample_counts,
//             in_samples,
//             in_sample_counts,
//             nullptr,
//             nullptr,
//             0);

//         if (circularBuffer != nullptr) {
//             circularBuffer->addData(out_samples, out_sample_counts);
//         }

//         for (int ch = 0; ch < current_channel_count; ch++) {
//             delete[] in_samples[ch];
//         }
//         delete[] in_samples;
//         delete[] in_sample_counts;

//         return 0;
//     } catch (...) {
//         return -3;
//     }
// }

PROCESSING_API int32_t processing_process_playback_stream(int16_t** out_samples, int32_t* out_sample_counts,
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

PROCESSING_API float processing_rms(const int16_t* data, int32_t length) {
    if (!initialized || !data || length <= 0) {
        return 0.0f;
    }
    
    try {
        return backyardbrains::utils::AnalysisUtils::RMS(const_cast<short*>(data), length);
    } catch (...) {
        return 0.0f;
    }
}

PROCESSING_API int32_t processing_normalize_signal(float* out_data, const int16_t* in_data, int32_t length,
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

PROCESSING_API int32_t processing_process_fft(float** out_fft, int32_t* out_window_count,
                             int32_t* out_window_size, int32_t* out_frequency_counter, 
                             const int16_t** in_samples,
                             const int32_t* in_sample_counts) {
    if (!initialized || !out_fft || !out_window_count || !out_window_size || !in_samples || !in_sample_counts) {
        return -1;
    }

    try {
        // int frequencyCounter = 0;
        fftProcessor->process(
            out_fft,
            PROCESSING_MAX_FFT_WINDOWS_COUNT,  // Maximum window count
            out_window_count[current_selected_channel],
            // out_window_size[current_selected_channel],
            out_frequency_counter[current_selected_channel],
            current_channel_count,
            reinterpret_cast<short**>(const_cast<int16_t**>(in_samples)),
            const_cast<int*>(in_sample_counts)
        );
        // platform_log_processing("\n out_fft 0 0\n");
        // platform_log_processing(std::to_string(out_fft[0][0]).c_str());
        // platform_log_processing("\n out_fft 0 1\n");
        // platform_log_processing(std::to_string(out_fft[0][1]).c_str());
        // platform_log_processing("\n out_fft 0 2\n");
        // platform_log_processing(std::to_string(out_fft[0][2]).c_str());
        // platform_log("\nout_window_size\n");
        // platform_log(std::to_string(out_window_size[0]).c_str());
        
        return 0;
    } catch (...) {
        return -3;
    }
}

PROCESSING_API void processing_reset_fft_normalization() {
    if (initialized && fftProcessor) {
        fftProcessor->resetNormalization();
    }
}

PROCESSING_API int32_t processing_is_audio_stream_am_modulated() {
    if (!initialized) {
        return 0;
    }

    try {
        return amModulationProcessor->isReceivingAmSignal() ? 1 : 0;
    } catch (...) {
        return 0;
    }
}

PROCESSING_API int32_t processing_get_averaged_sample_count() {
    return averaging_sample_count;
}

PROCESSING_API void processing_set_averaged_sample_count(int32_t count) {
    if (count > 0) {
        averaging_sample_count = count;
        if (thresholdProcessor) {
            thresholdProcessor->setAveragedSampleCount(count);
        }
    }
}

PROCESSING_API int32_t processing_get_averaging_trigger_type() {
    return thresholdProcessor ? thresholdProcessor->getTriggerType() : 0;
}

PROCESSING_API void processing_set_averaging_trigger_type(int32_t type) {
    if (thresholdProcessor) {
        thresholdProcessor->setTriggerType(type);
    }
}

PROCESSING_API void processing_set_threshold(float threshold) {
    current_threshold = threshold;
    if (thresholdProcessor) {
        thresholdProcessor->setThreshold(threshold);
    }
}

PROCESSING_API void processing_reset_threshold() {
    current_threshold = 0.0f;
    if (thresholdProcessor) {
        thresholdProcessor->setThreshold(0.0f);
    }
}

PROCESSING_API void processing_resume_threshold() {
    threshold_paused = false;
    if (thresholdProcessor) {
        thresholdProcessor->setPaused(false);
    }
}

PROCESSING_API void processing_pause_threshold() {
    threshold_paused = true;
    if (thresholdProcessor) {
        thresholdProcessor->setPaused(true);
    }
}

PROCESSING_API void processing_set_is_thresholding(bool isThresholding) {
    isProcessThresholding = isThresholding;    
}

PROCESSING_API int32_t processing_process_threshold(int16_t** out_samples, int32_t* out_sample_counts,
                                    int16_t** in_samples,  int32_t* in_sample_counts,
                                    const int32_t* in_event_indices, const int32_t* in_event_labels, int32_t in_event_count,
                                   bool average_samples) {
    if (!initialized || !out_samples || !out_sample_counts || !in_samples || !in_sample_counts) {
        return -1;
    }
    isProcessThresholding = true;

        // platform_log("FIRST\n");
        // // platform_log(std::to_string(in_samples[0]).c_str());
        // platform_log("\n");
        if (!average_samples) {
            thresholdProcessor->appendIncomingSamples(
                reinterpret_cast<short**>(const_cast<int16_t**>(in_samples)),
                const_cast<int*>(in_sample_counts)
            );
            return 0;
        }

        // For averaging samples, we need to pass empty arrays for events since they're not used
        // int* empty_event_indices = new int[1];
        // int* empty_events = new int[1];
        // int empty_event_count = 0;
        int* empty_event_indices = const_cast<int*>(in_event_indices);
        int* empty_events = const_cast<int*>(in_event_labels);
        int empty_event_count = in_event_count;

        // platform_log("SECOND\n");
        // platform_log(std::to_string(in_event_indices[0]).c_str());
        // platform_log("\n");
        thresholdProcessor->process(
            reinterpret_cast<short**>(const_cast<int16_t**>(out_samples)),
            const_cast<int*>(out_sample_counts),
            reinterpret_cast<short**>(const_cast<int16_t**>(in_samples)),
            const_cast<int*>(in_sample_counts),
            empty_event_indices,
            empty_events,
            empty_event_count
        );
        // thresholdProcessor->process(
        //     (out_samples),
        //     (out_sample_counts),
        //     // reinterpret_cast<short**>(in_samples),
        //     reinterpret_cast<short**>(const_cast<int16_t**>(in_samples)),
        //     const_cast<int*>(in_sample_counts),
        //     const_cast<int*>(empty_event_indices),
        //     const_cast<int*>(empty_events),
        //     empty_event_count
        // );



        // platform_log("LOG\n");
        // for (int i = 0; i < out_sample_counts[0]; i++) {
        //     platform_log( (std::to_string(out_samples[0][i])).c_str());
        //     platform_log( ",");
        // }
        // platform_log("\n===\n");

        // platform_log("THIRD\n");
        // platform_log(std::to_string(out_sample_counts[0]).c_str());
        // platform_log("\n");
        if (circularBufferThreshold != nullptr) {
            // circularBufferThreshold->addData(in_samples, (in_sample_counts));
            circularBufferThreshold->addData(out_samples, (out_sample_counts));
        }

        // platform_log("FOURTH\n");
        // platform_log(std::to_string(out_sample_counts[0]).c_str());
        // platform_log("\n");

        return 0;

}

PROCESSING_API void processing_set_bpm_processing(bool process_bpm) {
    bpm_processing_enabled = process_bpm;
    if (thresholdProcessor) {
        thresholdProcessor->setBpmProcessing(process_bpm);
    }
}

PROCESSING_API int32_t processing_prepare_for_signal_drawing(int16_t** out_samples, int32_t* out_sample_counts,
                                           float* out_event_indices, int32_t* out_event_count,
                                           const int32_t* in_event_indices, int32_t in_event_count,
                                           int32_t from_sample, int32_t to_sample,
                                           int32_t draw_surface_width) {
    if (!initialized || !out_samples || !out_sample_counts || !out_event_indices || !out_event_count ||
        !in_event_indices || draw_surface_width <= 0) {
        return -1;
    }
    try {
        // Get the channel count from our global state
        int32_t channel_count = current_channel_count;
        
        // Cap draw_surface_width to prevent OOM on high-DPI devices (e.g., Pixel Tablet)
        if (draw_surface_width > MAX_DRAW_SURFACE_WIDTH) {
            draw_surface_width = MAX_DRAW_SURFACE_WIDTH;
        }
        
        // Calculate sample count
        // int32_t sample_count = to_sample - from_sample + 1;
        int32_t sample_count = current_sample_rate * MAX_NUMBER_OF_SECONDS;
        // getDataForDrawing uses inclusive range: sampleCount = toSample - fromSample + 1
        // So we need to allocate sample_count + 1 elements to avoid buffer overflow
        // For the hardcoded 441000 case, we need 441001 elements
        int32_t max_requested_samples = std::max(sample_count, 441000);
        int32_t temp_buffer_size = max_requested_samples + 1;
        int32_t sample_out_count= draw_surface_width * 5;//experimentally found
        
        // Create temporary buffers with null checks to prevent OOM crashes
        auto** temp_samples = new (std::nothrow) int16_t*[channel_count];
        auto** float_samples = new (std::nothrow) float*[channel_count];
        if (!temp_samples || !float_samples) {
            delete[] temp_samples;
            delete[] float_samples;
            return -4; // Memory allocation failed
        }
        
        // Initialize pointers to nullptr for safe cleanup on allocation failure
        for (int i = 0; i < channel_count; i++) {
            temp_samples[i] = nullptr;
            float_samples[i] = nullptr;
        }
        
        for (int i = 0; i < channel_count; i++) {
            temp_samples[i] = new (std::nothrow) int16_t[temp_buffer_size];
            float_samples[i] = new (std::nothrow) float[sample_out_count];
            if (!temp_samples[i] || !float_samples[i]) {
                // Allocation failed - clean up and return error
                for (int j = 0; j <= i; j++) {
                    delete[] temp_samples[j];
                    delete[] float_samples[j];
                }
                delete[] temp_samples;
                delete[] float_samples;
                return -4; // Memory allocation failed
            }
        }
        // Retrieve data from the circular buffer
        // Check if circular buffer is valid before accessing it
        // This prevents crash when USB device is disconnected
        if (isProcessThresholding) {
            if (circularBufferThreshold == nullptr) {
                // Clean up and return error if threshold buffer is not available
                for (int i = 0; i < channel_count; i++) {
                    delete[] temp_samples[i];
                    delete[] float_samples[i];
                }
                delete[] temp_samples;
                delete[] float_samples;
                return -2;
            }
            circularBufferThreshold->getDataForDrawing(temp_samples, 0, current_sample_rate * MAX_NUMBER_OF_SECONDS);
        } else
        if (circularBuffer != nullptr) {
            // circularBuffer->getDataForDrawing(temp_samples, 0, current_sample_rate * MAX_NUMBER_OF_SECONDS);
            circularBuffer->getDataForDrawing(temp_samples, 0, 441000);
            // platform_log_processing("GET BUFFER DATA\n");
            // std::string str = std::to_string(temp_samples[0][441000-1]);
            // str += std::to_string(temp_samples[0][441000-2]);
            // str += std::to_string(temp_samples[0][441000-3]);
            // str += std::to_string(temp_samples[0][441000-4]);
            // platform_log_processing(str.c_str());
            
            //log_debug("Circular: from_sample=%d, to_sample=%d", from_sample, to_sample);
        } else {
            // Clean up and return error if no circular buffer is available
            for (int i = 0; i < channel_count; i++) {
                delete[] temp_samples[i];
                delete[] float_samples[i];
            }
            delete[] temp_samples;
            delete[] float_samples;
            return -2;
        }

        // Call DrawingUtils to prepare the signal for drawing
        int outEventCount = 0;
        int samplesCount = to_sample - from_sample;
        int maxSamples = current_sample_rate * MAX_NUMBER_OF_SECONDS;
        int startIndex = maxSamples - samplesCount;
        int endIndex = maxSamples;
        if (from_sample != 0) {
            startIndex = from_sample;
            endIndex = to_sample;
        }
        // platform_log_processing("First\n");
        // platform_log_processing(std::to_string(startIndex).c_str());
        // platform_log_processing("\n");
        // platform_log_processing("End\n");
        // platform_log_processing(std::to_string(endIndex).c_str());
        // platform_log_processing("\n");
        


        backyardbrains::utils::DrawingUtils::prepareSignalForDrawing(
            float_samples,
            out_sample_counts,
            out_event_indices,
            outEventCount,
            reinterpret_cast<short**>(temp_samples),
            channel_count,
            const_cast<int*>(in_event_indices),
            in_event_count,
            startIndex,
            endIndex,
            // 0,
            // maxSamples,
            draw_surface_width
        );
        // platform_log("Second\n");
        // platform_log(std::to_string(out_sample_counts[0]).c_str());
        // platform_log("\n");

        // platform_log("\nSTART\nMaxSamples:");
        // platform_log(std::to_string(maxSamples-1).c_str());
        // platform_log("===========\nSampleCount:");
        // platform_log(std::to_string(samplesCount).c_str());
        // platform_log("===========\nMax-Sample:");
        // platform_log(std::to_string(maxSamples - samplesCount).c_str());
        // platform_log("===========\nStarting:");
        // platform_log(std::to_string(from_sample).c_str());
        // platform_log("===========\nENDING:");
        // platform_log(std::to_string(to_sample).c_str());
        // platform_log("===========\n");
        
        // Copy float data back to output samples
        // circularBuffer->getRecentSamples(out_samples, out_sample_counts[0]*5);
        for (int i = 0; i < channel_count; i++) {
            for (int j = 0; j < out_sample_counts[i]; j++) {
                out_samples[i][j] = static_cast<int16_t>(float_samples[i][j]);
            }
        }
        
        // Clean up temporary buffers
        for (int i = 0; i < channel_count; i++) {
            delete[] temp_samples[i];
            delete[] float_samples[i];
        }
        delete[] temp_samples;
        delete[] float_samples;
        
        out_event_count[0] = outEventCount;
        return 0;
    } catch (...) {
        return -3;
    }
}

PROCESSING_API int32_t processing_prepare_fft_for_drawing(float* out_vertices, int16_t* out_indices,
                                         float* out_colors, int32_t* out_vertex_count,
                                         int32_t* out_index_count, int32_t* out_color_count,
                                         float** fft_data, int32_t window_count,
                                         int32_t window_size, int32_t target_window_count,float width, float height) {
    if (!initialized || !out_vertices || !out_indices || !out_colors ||
        !out_vertex_count || !out_index_count || !out_color_count ||
        !fft_data || window_count <= 0 || window_size <= 0) {
        return -1;
    }

    try {
            
        // int16_t** channel_samples = new int16_t*[current_channel_count];
        // for (int i = 0; i < current_channel_count; i++) {
        //       channel_samples[i] = new int16_t[frame_count]{0};
        // }

        // platform_log_processing("\n CREATING BUFFER 0\n");
        // window_count = window_count * 0.5;
        float** in_fft_data = new float*[target_window_count];
        int index = 0;
        for (int i = 0; i < target_window_count; ++i) {
            index = max_fft_windows_count - target_window_count + i;
            auto tmpSamples = fft_data[index];
            // windowSize = env->GetArrayLength(tmpSamples);
            in_fft_data[i] = new float[window_size]{0};
            std::copy(tmpSamples, tmpSamples + window_size, in_fft_data[i]);
        }
        // platform_log_processing("\n TEMP BUFFER CREATED 0\n");
        // return 0;

        // int windowCount = ( (6.0 * 128) / (512 * 0.01) );
        // int windowSize = ( (32 * 128) );
        // out_vertices = new float(windowCount * windowSize * 2);
        // out_indices = new short(windowCount * windowSize * 6);
        // out_colors = new float(windowCount * windowSize * 4);

        int vertexCount = 0;
        int indexCount = 0;
        int colorCount = 0;


        backyardbrains::utils::DrawingUtils::prepareFftForDrawing(
            out_vertices,
            (out_indices),
            out_colors,
            vertexCount,
            indexCount,
            colorCount,
            in_fft_data,
            target_window_count,
            window_size,
            width,
            height
        );


        // CHANGE IN WEB
        out_vertex_count[current_selected_channel] = vertexCount;
        out_index_count[current_selected_channel] = indexCount;
        out_color_count[current_selected_channel] = colorCount;

        for (int i = 0; i < target_window_count; ++i) {
            delete[] in_fft_data[i];
        }
        delete[] in_fft_data;
        
        // platform_log_processing("\n TEMP BUFFER DELETED 0\n");
        // platform_log("indexCount !!! \n");
        // platform_log(std::to_string(indexCount).c_str());
        // platform_log("\ncolorCount !!! \n");
        // platform_log(std::to_string(colorCount).c_str());
        // platform_log("\nVertex Count !!! \n");
        // platform_log(std::to_string(vertexCount).c_str());
        // platform_log("\n !!! \n");

        // *out_vertex_count = vertexCount;
        // *out_index_count = indexCount;
        // *out_color_count = colorCount;
        return 0;
    } catch (...) {
        return -3;
    }
}

PROCESSING_API int32_t processing_prepare_spikes_for_drawing(float* out_vertices, float* out_colors,
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

PROCESSING_API int32_t processing_parse_events(const char* file_path, float sample_rate,
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

PROCESSING_API int32_t processing_check_events(const char* file_path, char** event_names) {
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

PROCESSING_API void processing_event_triggered_average_analysis(const char* file_path,
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

PROCESSING_API void processing_autocorrelation_analysis(float** spike_trains,
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

PROCESSING_API void processing_isi_analysis(float** spike_trains,
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

PROCESSING_API void processing_cross_correlation_analysis(float** spike_trains,
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

PROCESSING_API void processing_average_spike_analysis(const char* file_path,
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

PROCESSING_API void processing_cleanup() {
    cleanup_processors();
    
    // Clean up the circular buffer
    if (circularBuffer != nullptr) {
        delete circularBuffer;
        delete circularBufferThreshold;
        circularBuffer = nullptr;
        circularBufferThreshold = nullptr;
    }
    
    initialized = false;
}

PROCESSING_API int32_t processing_set_band_filter(float low_cut_off_freq, float high_cut_off_freq) {
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



PROCESSING_API int32_t processing_set_notch_filter(float center_freq) {
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

PROCESSING_API int32_t processing_set_channel_filter_enabled(int32_t channel, bool enabled) {
    if (!initialized) {
        return -1;
    }

    try {
        if (amModulationProcessor) {
            amModulationProcessor->setChannelFilterEnabled(channel, enabled);
        }
        if (sampleStreamProcessor) {
            sampleStreamProcessor->setChannelFilterEnabled(channel, enabled);
        }
        if (thresholdProcessor) {
            thresholdProcessor->setChannelFilterEnabled(channel, enabled);
        }
        if (fftProcessor) {
            fftProcessor->setChannelFilterEnabled(channel, enabled);
        }
        return 0;
    } catch (...) {
        return -3;
    }
}

PROCESSING_API int32_t processing_map(float* out_data, const float* in_data, int32_t length,
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



// typedef void (*DartCallback)(int32_t);

// DartCallback g_dart_callback;
// // C++ function to receive the Dart callback pointer
// extern "C" void set_dart_callback(Dart_NativeFunction callback) {
//   g_dart_callback = reinterpret_cast<DartCallback>(callback);
//   std::cout << "C++: Dart callback received and stored." << std::endl;
// }

// // C++ function that calls the Dart callback
// extern "C" void call_dart_from_cpp(int value) {
//   if (g_dart_callback != nullptr) {
//     std::cout << "C++: Calling Dart callback with value: " << value << std::endl;
//     g_dart_callback(value);
//   } else {
//     std::cerr << "C++: Dart callback not set." << std::endl;
//   }
// }