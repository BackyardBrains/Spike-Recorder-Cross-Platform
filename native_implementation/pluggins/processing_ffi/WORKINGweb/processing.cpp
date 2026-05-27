#ifdef __EMSCRIPTEN__
    #include <emscripten/bind.h>
    using namespace emscripten;
    #include <emscripten.h>
    #include <wasm_simd128.h>
#endif
#define BUILDING_DLL
#include "processing.h"
#include "DrawingUtils.h"
#include <cmath>
#include <vector>
#include <cstring>
#include <algorithm>
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

// #ifdef __EMSCRIPTEN__
//   EMSCRIPTEN_KEEPALIVE
// #endif

using namespace backyardbrains::filters;
using namespace backyardbrains::processing;
using namespace backyardbrains::analysis;
using namespace backyardbrains::utils;


// Passed Pointers
short* _ptrExpBoardType;


// Constants
static constexpr int32_t PROCESSING_MAX_EVENTS = 100;  // Same as MAX_EVENTS in SampleStreamProcessor
static constexpr int32_t MAX_NUMBER_OF_SECONDS = 10;  // 10 seconds of buffer
static constexpr int32_t BUFFER_MULTIPLIER = 1;
static constexpr int32_t MAX_DRAW_SURFACE_WIDTH = 4096; 
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

static int PROCESSING_MAX_FFT_WINDOWS_COUNT = 1;
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
            // EM_ASM({
            //     console.log("START");
            // }, channelCount);
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
    
    
    int32_t* headIndex; // Position to write next sample
    int32_t* tailIndex; // Oldest valid sample position
    private:
        int sampleRate;
        int channelCount;
        int bufferSize;
        int16_t** buffer;
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

    void onEventFound(int sampleIndex, int eventLabel) {

        EM_ASM({
            postMessage({
                "message": "EVENT_FOUND",
                "sampleIndex": $0,
                "eventLabel": $1,
            });
            console.log( $0, $1 );
        }, sampleIndex, eventLabel);        
    }

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
        // _ptrExpBoardType[0] = static_cast<short>(expansionBoardType);
        _ptrExpBoardType[0] = expansionBoardType;

        EM_ASM({
            setExpansionBoardType( $0, $1 );
            console.log( "EMASM EXPANSION BOARD TYPE: ", $0, $1 );
        }, _ptrExpBoardType, expansionBoardType);        
    }

private:

};


// Helper functions
EXTERNC FUNCTION_ATTRIBUTE void initialize_processors() {

    //   log_debug("initialize_processors");
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

EXTERNC FUNCTION_ATTRIBUTE void cleanup_processors() {
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
EXTERNC FUNCTION_ATTRIBUTE int32_t processing_init() {

    if (initialized) {
        return 0;
    }
    EM_ASM({
        console.log("---- Processing init C++");
    });
    // log_debug("Processing init");
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
        processing_set_channel_count(1);
        processing_set_channel_filter_enabled(0, true);
        return 0;
    } catch (...) {
        return -1;
    }
}

int32_t* outInfo;
int32_t processing_get_information(int32_t* _outInfo) {
    outInfo = _outInfo;
    outInfo[0] = current_sample_rate;
    outInfo[1] = current_channel_count;
    outInfo[2] = current_bits_per_sample;
    outInfo[3] = current_selected_channel;
    return 0;
}

#ifdef __EMSCRIPTEN__
  EMSCRIPTEN_KEEPALIVE
#endif
EXTERNC FUNCTION_ATTRIBUTE int32_t processing_set_sample_rate(int32_t sample_rate) {
    EM_ASM({
        console.log("---- sample_rate C++: ", $0);
    }, sample_rate);        
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
        amModulationProcessor->setSampleRate(static_cast<float>(sample_rate));
        thresholdProcessor->setSampleRate( sample_rate );
        sampleStreamProcessor->setSampleRate(sample_rate);
        fftProcessor->setSampleRate(sample_rate);
        PROCESSING_MAX_FFT_WINDOWS_COUNT = (int) ((FFT_PROCESSING_TIME * FFT_SAMPLE_RATE) / FFT_WINDOW_SAMPLE_DIFF_COUNT);

        // Re-setup the circular buffer when sample rate changes
        if (circularBuffer != nullptr) {
            circularBuffer->setup(current_sample_rate, current_channel_count);
            circularBufferThreshold->setup(current_sample_rate, current_channel_count);
        }

        // Rebuild filter coefficients at the new sample rate (notch/band may have been set earlier).
        if (current_notch_filter_freq != PROCESSING_MIN_FILTER_CUTOFF) {
            processing_set_notch_filter(current_notch_filter_freq);
        }
        if (current_low_cut_off_freq != PROCESSING_MIN_FILTER_CUTOFF ||
            current_high_cut_off_freq != PROCESSING_MAX_FILTER_CUTOFF) {
            processing_set_band_filter(-1, current_low_cut_off_freq, current_high_cut_off_freq);
        }
        
        return 0;
    } catch (...) {
        return -3;
    }
}

#ifdef __EMSCRIPTEN__
  EMSCRIPTEN_KEEPALIVE
#endif
EXTERNC FUNCTION_ATTRIBUTE int32_t processing_set_channel_count(int32_t channel_count) {
    EM_ASM({
        console.log("---- Processing set channel count C++:", $0);
    }, channel_count);

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

#ifdef __EMSCRIPTEN__
  EMSCRIPTEN_KEEPALIVE
#endif
EXTERNC FUNCTION_ATTRIBUTE int32_t processing_set_bits_per_sample(int32_t bits_per_sample) {
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

EXTERNC FUNCTION_ATTRIBUTE int32_t processing_set_selected_channel(int32_t selected_channel) {
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

int totalSamples1 = 0;
int totalSamples2 = 0;
EXTERNC FUNCTION_ATTRIBUTE 
int32_t processing_process_sample_stream(int16_t* _out_samples, int32_t* out_sample_counts,
                                       const uint8_t* in_data, int32_t length,
                                       int32_t hardware_type) {
    if (!initialized || !_out_samples || !out_sample_counts || !in_data || length <= 0) {
        return -1;
    }

    try {
        // Process data using SampleStreamProcessor
        int16_t** out_samples = new int16_t*[current_channel_count];
        int32_t sampleCount = out_sample_counts[0];
        for (int cu = 0; cu < current_channel_count; cu++) {
            out_samples[cu] = &_out_samples[cu * out_sample_counts[cu]];
        }
        // CHECKING IF THE DATA FROM serial is the same with this current buffer data ==> THE SAME
        // EM_ASM({
        //     console.log("Buffer 0 ptr : ", $0, $1, $2, $3);
        // }, in_data[0], in_data[1], in_data[2], in_data[3]);

        int* event_indices = new int[PROCESSING_MAX_EVENTS];
        std::string* event_labels = new std::string[PROCESSING_MAX_EVENTS];
        int event_count = 0;

        // STEVE NEED TO FIX THIS
        // create new outsamples variable, copy it to the real out_samples, with out_sample_counts
        // int16_t** tempSamples = new int16_t*[channelCount];
        // for (int i = 0; i < channelCount; i++) {
        //       tempSamples[i] = new int16_t[length];              
        //       for (int j = 0; j < length; j++) {
        //             tempSamples[i][j] = 0;
        //       }
        // }

        sampleStreamProcessor->process(in_data, length, (out_samples), out_sample_counts,
                                     event_indices, event_labels, event_count,
                                     current_channel_count, hardware_type);       
        // Add processed data to circular buffer
        if (circularBuffer != nullptr) {
            // if (out_sample_counts[0]>0 || ) {
            // indicating that the serial data 
                // totalSamples1 += out_sample_counts[0];
                // totalSamples2 += out_sample_counts[1];

                // std::fill(out_samples[1], out_samples[1] + out_sample_counts[1], 307);
                circularBuffer->addData(out_samples, out_sample_counts);
                // EM_ASM({
                //     // if ($0 !== $1) {
                //         console.log("Sample Countz : ", $0, $1, $2, $3);
                //     // }
                // }, out_samples[0][0], out_samples[0][1], out_sample_counts[0], out_sample_counts[1]);

            // }
        } else {
            delete[] event_indices;
            delete[] event_labels;
            return -100;
        }
        


        delete[] event_indices;
        delete[] event_labels;
        return out_sample_counts[0];
        // int16_t** samples = new int16_t*[current_channel_count];
        // for (int i = 0; i < current_channel_count; i++) {
        //     samples[i] = new int16_t[frame_count]{0};
        // }

        // circularBuffer->getRecentSamples(samples, 100);
        

        // THE RESULT IS 0
        // for (int cu = 0; cu < current_channel_count; cu++) {
        //     delete[] out_samples[cu];
        // }
        // delete[] out_samples;

        // out_samples = new int16_t*[current_channel_count];
        // for (int cu = 0; cu < current_channel_count; cu++) {
        //     out_sample_counts[cu] = current_sample_rate * MAX_NUMBER_OF_SECONDS;
        //     // out_samples[cu] = &_out_samples[cu * current_sample_rate * MAX_NUMBER_OF_SECONDS];            
        //     out_samples[cu] = new int16_t[current_sample_rate * MAX_NUMBER_OF_SECONDS];
        // }

        // // int16_t** out_samples2 = new int16_t*[current_channel_count];
        // // for (int cu = 0; cu < current_channel_count; cu++) {
        // //     out_samples2[cu] = new int16_t[current_sample_rate * MAX_NUMBER_OF_SECONDS];
        // // }

        // circularBuffer->getDataForDrawing(out_samples, 0, current_sample_rate * MAX_NUMBER_OF_SECONDS);
        // // for (int cu = 0; cu < current_channel_count; cu++) {
        // //     delete[] out_samples2[cu];
        // // }
        // EM_ASM({
        //     console.log("Buffer 0 ptr : ", $0, $1, $2, $3);
        // }, out_samples[0][0], out_samples[0][1], out_samples[0][2], out_samples[0][3]);

        // // delete[] out_samples2;
                             
        // for (int cu = 0; cu < current_channel_count; cu++) {
        //     delete[] out_samples[cu];
        // }
        // delete[] out_samples;

        // delete[] event_indices;
        // delete[] event_labels;
        // return 0;
    } catch (...) {
        return -3;
    }
}

#ifdef __EMSCRIPTEN__
  EMSCRIPTEN_KEEPALIVE
#endif
EXTERNC FUNCTION_ATTRIBUTE int32_t processing_process_microphone_stream(int16_t* _out_samples, int32_t* out_sample_counts,
                                           const uint8_t* in_data, int32_t length) {
      if (!initialized || !_out_samples || !out_sample_counts || !in_data || length <= 0) {
            return -1;
      }
    //   EM_ASM({
    //     console.log("---- Processing process microphone stream C++");
    //   });
      //log_debug("Processing microphone data: length=%d", length);

      try {
            // STEVE NEED JS WRAP
            int16_t** out_samples = new int16_t*[current_channel_count];
            for (int cu = 0; cu < current_channel_count; cu++) {  
                out_samples[cu] = &_out_samples[cu * out_sample_counts[cu]];
                // std::fill(arr[cu], arr[cu] + out_sample_counts[cu], 57);
                // out_samples[cu][1] = -100;
                // out_samples[cu][3] = -300;
            }

            // Calculate sample count based on bits per sample
            int32_t sample_count = length * 8 / current_bits_per_sample;
            int32_t frame_count = sample_count / current_channel_count;
            // EM_ASM({
            //     console.log("Buffer 0 ptr : ", $0, $1, $2, $3);
            // }, _out_samples[1], out_samples[0][1], sample_count, frame_count);
            // // for (int cu = 0; cu < current_channel_count; cu++) {
            // //     delete[] out_samples[cu];
            // // }
            // // delete[] out_samples;
            // return 100;
    
  
            // Store the AM modulation state before processing
            bool is_receiving_am_signal_before = amModulationProcessor->isReceivingAmSignal();
            
            // Process the audio data through AM modulation processor
            // Note: amModulationProcessor expects interleaved samples as input 
            // and will handle deinterleaving internally

            // Allocate array of pointers for each channel (like in byb-lib.cpp)
            int16_t** channel_samples = new int16_t*[current_channel_count];
            for (int i = 0; i < current_channel_count; i++) {
                channel_samples[i] = new int16_t[frame_count]{0};
                out_sample_counts[i] = frame_count;
            }
            
            // Pass channel_samples to amModulationProcessor, not out_samples
            amModulationProcessor->process(
                reinterpret_cast<short*>(const_cast<uint8_t*>(in_data)),
                channel_samples,  // Use channel_samples instead of out_samples
                sample_count,
                frame_count
            );

            // Add processed data to circular buffer
            if (circularBuffer != nullptr) {
                int32_t* frame_counts = new int32_t[1];
                frame_counts[0] = frame_count;
                circularBuffer->addData(channel_samples, frame_counts);
                delete[] frame_counts;
            }

            /*
            // int16_t** samples = new int16_t*[current_channel_count];
            // for (int i = 0; i < current_channel_count; i++) {
            //     samples[i] = new int16_t[frame_count]{0};
            // }

            // circularBuffer->getRecentSamples(samples, 100);
            */
           
            // Copy processed data from channel_samples to out_samples
            for (int i = 0; i < current_channel_count; i++) {
                if (out_samples[i] != nullptr && channel_samples[i] != nullptr) {
                    // for (short j = 0; j < frame_count; j++) {
                    //     EM_ASM({
                    //         console.log("---- Copy processed data from channel_samples to out_samples", $0, $1);
                    //     }, i, j );
                    //     out_samples[i][j] = channel_samples[i][j];
                    // }
                    std::copy(channel_samples[i], channel_samples[i] + frame_count, out_samples[i]);
                }
            }
            
            // Clean up channel_samples to avoid memory leaks
            for (int i = 0; i < current_channel_count; i++) {
                delete[] channel_samples[i];
            }
            delete[] channel_samples;
            
            // Check if AM modulation state changed (for potential callbacks)
            // bool is_receiving_am_signal_after = amModulationProcessor->isReceivingAmSignal();

            // // Set output sample counts for all channels
            for (int i = 0; i < current_channel_count; i++) {
                out_sample_counts[i] = frame_count;
            }
            // delete[] out_samples;

            return 0;
      } catch (...) {
            // log_debug("Exception ");
            return -3;
      }
}


// EXTERNC FUNCTION_ATTRIBUTE int32_t processing_process_threshold_stream(int16_t** out_samples, int32_t* out_sample_counts,
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


EXTERNC FUNCTION_ATTRIBUTE int32_t processing_process_playback_stream(int16_t* out_samples, int32_t* out_sample_counts,
                                         const uint8_t* in_data, int32_t length,
                                         const int32_t* event_indices, const char* event_names,
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
        // STEVE NEED TO FIX THIS
        // sampleStreamProcessor->process(in_data, length, out_samples, out_sample_counts,
        //                              out_event_indices, out_event_labels, out_event_count,
        //                              current_channel_count, 0);

        delete[] out_event_indices;
        delete[] out_event_labels;
        return 0;
    } catch (...) {
        return -3;
    }
}

EXTERNC FUNCTION_ATTRIBUTE float processing_rms(const int16_t* data, int32_t length) {
    if (!initialized || !data || length <= 0) {
        return 0.0f;
    }
    
    try {
        // STEVE FIX THIS
        return 1.0f;
        // return backyardbrains::utils::AnalysisUtils::RMS(const_cast<short*>(data), length);
    } catch (...) {
        return 0.0f;
    }
}

EXTERNC FUNCTION_ATTRIBUTE int32_t processing_normalize_signal(float* out_data, const int16_t* in_data, int32_t length,
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
        // STEVE change this
        // backyardbrains::utils::AnalysisUtils::map(temp_data, out_data, length, in_min, in_max, out_min, out_max);
        
        delete[] temp_data;
        return 0;
    } catch (...) {
        return -3;
    }
}

// FFT processing
// STEVE COMMENTED THIS OUT
EXTERNC FUNCTION_ATTRIBUTE int32_t processing_process_fft(float* _out_fft, int32_t* out_window_count,
                             int32_t* out_window_size, int32_t* out_frequency_counter, int16_t* _in_samples,
                             const int32_t* in_sample_counts) {
    if (!initialized || !_out_fft || !out_window_count || !out_window_size || !_in_samples || !in_sample_counts) {
        return -1;
    }
    float** out_fft = new float*[out_window_count[0]];
    for (int cu = 0; cu < out_window_count[0]; cu++) {
        out_fft[cu] = &_out_fft[cu * out_window_size[0]];
    }
    int16_t** in_samples = new int16_t*[out_window_count[0]];
    for (int cu = 0; cu < out_window_count[0]; cu++) {
        in_samples[cu] = &_in_samples[cu * out_window_size[0]];
    }

    try {
        fftProcessor->process(
            out_fft,
            PROCESSING_MAX_FFT_WINDOWS,  // Maximum window count
            *out_window_count,
            *out_window_size,
            current_channel_count,
            // reinterpret_cast<short**>(const_cast<int16_t**>(in_samples)),
            in_samples,
            const_cast<int*>(in_sample_counts)
        );
        return 0;
    } catch (...) {
        return -3;
    }
}

EXTERNC FUNCTION_ATTRIBUTE void processing_reset_fft_normalization() {
    if (initialized && fftProcessor) {
        fftProcessor->resetNormalization();
    }
}

EXTERNC FUNCTION_ATTRIBUTE int32_t processing_is_audio_stream_am_modulated() {
    if (!initialized) {
        return 0;
    }

    try {
        return amModulationProcessor->isReceivingAmSignal() ? 1 : 0;
    } catch (...) {
        return 0;
    }
}

EXTERNC FUNCTION_ATTRIBUTE int32_t processing_get_averaged_sample_count() {
    return averaging_sample_count;
}

EXTERNC FUNCTION_ATTRIBUTE void processing_set_averaged_sample_count(int32_t count) {
    if (count > 0) {
        averaging_sample_count = count;
        if (thresholdProcessor) {
            thresholdProcessor->setAveragedSampleCount(count);
        }
    }
}

EXTERNC FUNCTION_ATTRIBUTE int32_t processing_get_averaging_trigger_type() {
    return thresholdProcessor ? thresholdProcessor->getTriggerType() : 0;
}

EXTERNC FUNCTION_ATTRIBUTE void processing_set_averaging_trigger_type(int32_t type) {
    if (thresholdProcessor) {
        thresholdProcessor->setTriggerType(type);
    }
}

EXTERNC FUNCTION_ATTRIBUTE void processing_set_threshold(float threshold) {
    current_threshold = threshold;
    if (thresholdProcessor) {
        thresholdProcessor->setThreshold(threshold);
    }
}

EXTERNC FUNCTION_ATTRIBUTE void processing_reset_threshold() {
    current_threshold = 0.0f;
    if (thresholdProcessor) {
        thresholdProcessor->setThreshold(0.0f);
    }
}

EXTERNC FUNCTION_ATTRIBUTE void processing_resume_threshold() {
    threshold_paused = false;
    if (thresholdProcessor) {
        thresholdProcessor->setPaused(false);
    }
}

EXTERNC FUNCTION_ATTRIBUTE void processing_pause_threshold() {
    threshold_paused = true;
    if (thresholdProcessor) {
        thresholdProcessor->setPaused(true);
    }
}

// STEVE COMMENTED THIS OUT
EXTERNC FUNCTION_ATTRIBUTE void processing_set_is_thresholding(bool isThresholding) {
    isProcessThresholding = isThresholding;    
}

EXTERNC FUNCTION_ATTRIBUTE int32_t processing_process_threshold(int16_t* _out_samples, int32_t* out_sample_counts,
                                    int16_t* _in_samples,  int32_t* in_sample_counts,
                                    const int32_t* in_event_indices, const int32_t* in_event_labels, int32_t in_event_count,
                                   bool average_samples) {
    if (!initialized || !_out_samples || !out_sample_counts || !_in_samples || !in_sample_counts) {
        return -1;
    }
        int16_t** out_samples = new int16_t*[current_channel_count];
        for (int cu = 0; cu < current_channel_count; cu++) {
            out_samples[cu] = &_out_samples[cu * out_sample_counts[cu]];
        }
        int16_t** in_samples = new int16_t*[current_channel_count];
        for (int cu = 0; cu < current_channel_count; cu++) {
            in_samples[cu] = &_in_samples[cu * in_sample_counts[cu]];
            // in_samples[cu] = new int16_t[in_sample_counts[cu]] {300};
        }
    
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

        if (circularBufferThreshold != nullptr) {
            // EM_ASM({
            //     console.log("THreshold check");
            //     console.log($0, $1, $2); // 2. 1.  -1.
            // }, current_channel_count, thresholdProcessor->getAveragedSampleCount(), thresholdProcessor->getTriggerType(), out_samples[0][0]);

            // EM_ASM({
            //     // console.log("out_sample_counts");
            //     // console.log($0, $1);
            //     console.log("out_sample_Data");
            //     console.log($2, $3);
            // }, out_sample_counts[0], out_sample_counts[1], out_samples[0][0], out_samples[1][0]);

            circularBufferThreshold->addData(out_samples, (out_sample_counts));
        }

        return 0;

}


// EXTERNC FUNCTION_ATTRIBUTE int32_t processing_get_most_right(int chan, int from_sample, int to_sample, int bufferSize) {
//     return circularBuffer->getMostRight(chan, from_sample, to_sample, bufferSize);
// }
EXTERNC FUNCTION_ATTRIBUTE void processing_set_bpm_processing(bool process_bpm) {
    bpm_processing_enabled = process_bpm;
    if (thresholdProcessor) {
        thresholdProcessor->setBpmProcessing(process_bpm);
    }
}


int isEventNotEmpty = -1;
#ifdef __EMSCRIPTEN__
  EMSCRIPTEN_KEEPALIVE
#endif
EXTERNC FUNCTION_ATTRIBUTE int32_t processing_prepare_for_signal_drawing(int16_t* _out_samples, int32_t* out_sample_counts,
                                           float* out_event_indices, int32_t* out_event_count,
                                           const int32_t* in_event_indices, int32_t in_event_count,
                                           int32_t from_sample, int32_t to_sample,
                                           int32_t draw_surface_width) {


    if (!initialized || !_out_samples || !out_sample_counts || !out_event_indices || !out_event_count ||
        !in_event_indices || draw_surface_width <= 0) {
        return -1;
    }
    // EM_ASM({
    //     console.log("---- Processing prepare for signal drawing C++");
    // });

    try {
        // STEVE NEED JS WRAP
        int16_t** out_samples = new int16_t*[current_channel_count];
        for (int cu = 0; cu < current_channel_count; cu++) {
            out_samples[cu] = &_out_samples[cu * out_sample_counts[cu]];
            // out_samples[cu][1] = -100;
            // out_samples[cu][3] = -300;
        }

        // int32_t* raw_in_event_indices = new int32_t[in_event_count];
        // int32_t* temp_in_event_indices = new int32_t[in_event_count];
        // int32_t bufferSize = 48000 * MAX_NUMBER_OF_SECONDS;
        // short chan = 0;
        // for (int eIdx = 0; eIdx < in_event_count; eIdx++) {
        //     // int32_t tempIndex = 480000 - in_event_indices[eIdx];
        //     // int32_t tempIndex = 0;
        //     // temp_in_event_indices[eIdx] = (circularBuffer->headIndex[chan] - (to_sample - tempIndex) ) % bufferSize;
        //     if (isEventNotEmpty == -1) {
        //         int32_t sampleCount = to_sample - from_sample;
        //         int32_t mostRight = (circularBuffer->headIndex[chan] - (to_sample - sampleCount) ) % bufferSize;
        //         isEventNotEmpty = mostRight;
        //         raw_in_event_indices[eIdx] = circularBuffer->headIndex[chan];
        //     } else {
        //         raw_in_event_indices[eIdx] = isEventNotEmpty;

        //     }
        // }

        // circularBuffer->getDataForDrawing(out_samples, from_sample, to_sample);
        // EM_ASM({
        //     console.log("in_event_count 0 ptr : ", $0);
        // }, in_event_count);

        // return 0;

        // Get the channel count from our global state
        int32_t channel_count = current_channel_count;
        // Cap draw_surface_width to prevent OOM on high-DPI devices (e.g., Pixel Tablet)
        if (draw_surface_width > MAX_DRAW_SURFACE_WIDTH) {
            draw_surface_width = MAX_DRAW_SURFACE_WIDTH;
        }
        // Calculate sample count
        int32_t sample_count = current_sample_rate * MAX_NUMBER_OF_SECONDS;
        // getDataForDrawing uses inclusive range: sampleCount = toSample - fromSample + 1
        // So we need to allocate sample_count + 1 elements to avoid buffer overflow
        int32_t temp_buffer_size = sample_count + 1;
        int32_t sample_out_count= draw_surface_width * 5;//experimentally found
        
        // Create temporary buffers
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
        // Stev: From_sample is index in the circular buffer
       
        if (isProcessThresholding) {
            circularBufferThreshold->getDataForDrawing(temp_samples, 0, current_sample_rate * MAX_NUMBER_OF_SECONDS);
            // circularBuffer->getDataForDrawing(temp_samples, 0, current_sample_rate * MAX_NUMBER_OF_SECONDS);
        } else
        if (circularBuffer != nullptr) {
            circularBuffer->getDataForDrawing(temp_samples, 0, current_sample_rate * MAX_NUMBER_OF_SECONDS);
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
        // int outEventCount = 0;
        int samplesCount = to_sample - from_sample;
        int maxSamples = current_sample_rate * MAX_NUMBER_OF_SECONDS;
        int startIndex = maxSamples - samplesCount;
        int endIndex = maxSamples;
        if (from_sample != 0) {
            startIndex = from_sample;
            endIndex = to_sample;
        }
            // EM_ASM({
            //     // ===== PREPARE SIGNAL from:  0 to:  91612 91612 480000  -  388388 480000 XSTEP: 
            //     // ===== PREPARE SIGNAL from:  5759 to:  109440 103681 480000  -  5759 109440 XSTEP: 
            //     console.log( "===== PREPARE SIGNAL from: ", $0, "to: ", $1, $2, $3, " - ", $4, $5, "XSTEP: ", );
            // }, from_sample, to_sample, samplesCount, maxSamples, startIndex, endIndex);


        backyardbrains::utils::DrawingUtils::prepareSignalForDrawing(
            float_samples,
            out_sample_counts,
            out_event_indices,
            out_event_count,
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
        
        // Copy float data back to output samples
        for (int i = 0; i < channel_count; i++) {
            for (int j = 0; j < out_sample_counts[i]; j++) {
                out_samples[i][j] = static_cast<int16_t>(float_samples[i][j]);
            }
        }

        // EM_ASM({
        //     console.log("---- Processing prepare for signal drawing C++", $0 , $1);
        // }, out_sample_counts[0], out_samples[0][1700]);
    

        // if (in_event_count > 0) {
        //     EM_ASM({
        //         // outEventIndices[eventIndex++]:  45760 1.4001774255533572e-41 1655 1285  -  0 50000 XSTEP:  1439
        //         // outEventIndices[eventIndex++]:  -11272118 NaN 0 0  -  0 480000 XSTEP:  1.0015649795532227
        //         console.log( "===== PREPARE SIGNAL outEventIndices[eventIndex++]: ", $0, $1, $2, $3, " - ", $4, $5, "XSTEP: ", );
        //     }, temp_in_event_indices[0], out_event_indices[0], out_event_count[0], in_event_count, from_sample, to_sample);
        // }
        
        // Clean up temporary buffers
        for (int i = 0; i < channel_count; i++) {
            delete[] temp_samples[i];
            delete[] float_samples[i];
        }
        delete[] temp_samples;
        delete[] float_samples;
        // delete[] temp_in_event_indices;
        // delete[] raw_in_event_indices;
        
        // *out_event_count = outEventCount;
        // EM_ASM({
        //     // console.log("Buffer DRAW ptr : ", $0, $1, $2, $3, $4);
        //     console.log("current_channel_count : ", $0);
        // }, current_channel_count);
        // }, _out_samples[0], out_samples[0][0], sample_count, sample_out_count, out_sample_counts[0]);
        // return -100;
        // out_event_count[0] = outEventCount;
        
        return 0;
    } catch (...) {
        return -3;
    }
}

EXTERNC FUNCTION_ATTRIBUTE int32_t processing_prepare_fft_for_drawing(float* out_vertices, int16_t* out_indices,
                                         float* out_colors, int32_t* out_vertex_count,
                                         int32_t* out_index_count, int32_t* out_color_count,
                                         float* _fft_data, int32_t window_count,
                                         int32_t window_size, float width, float height) {
    if (!initialized || !out_vertices || !out_indices || !out_colors ||
        !out_vertex_count || !out_index_count || !out_color_count ||
        !_fft_data || window_count <= 0 || window_size <= 0) {
        return -1;
    }
    float** fft_data = new float*[window_count];
    for (int cu = 0; cu < window_count; cu++) {
        fft_data[cu] = &_fft_data[cu * window_size];
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

// EXTERNC FUNCTION_ATTRIBUTE int32_t processing_prepare_spikes_for_drawing(float* out_vertices, float* out_colors,
//                                             int32_t* out_vertex_count, int32_t* out_color_count,
//                                             const float* in_spike_vertices,
//                                             const int32_t* in_spike_indices,
//                                             int32_t spike_count,
//                                             const float* color_in_range,
//                                             const float* color_out_of_range,
//                                             int32_t range_start_index,
//                                             int32_t range_end_index,
//                                             float sample_start,
//                                             int32_t sample_end,
//                                             int32_t draw_start,
//                                             int32_t draw_end,
//                                             int32_t sample_count,
//                                             int32_t width) {
//     if (!initialized || !out_vertices || !out_colors || !out_vertex_count || !out_color_count ||
//         !in_spike_vertices || !in_spike_indices || spike_count <= 0 ||
//         !color_in_range || !color_out_of_range || width <= 0) {
//         return -1;
//     }

//     try {
//         int vertexCount = 0;
//         int colorCount = 0;
//         backyardbrains::utils::DrawingUtils::prepareSpikesForDrawing(
//             out_vertices,
//             out_colors,
//             vertexCount,
//             colorCount,
//             const_cast<float*>(in_spike_vertices),
//             const_cast<int*>(in_spike_indices),
//             spike_count,
//             const_cast<float*>(color_in_range),
//             const_cast<float*>(color_out_of_range),
//             range_start_index,
//             range_end_index,
//             sample_start,
//             sample_end,
//             draw_start,
//             draw_end,
//             sample_count,
//             width
//         );
//         *out_vertex_count = vertexCount;
//         *out_color_count = colorCount;
//         return 0;
//     } catch (...) {
//         return -3;
//     }
// }

// STEVE COMMENTED THIS OUT
/*
EXTERNC FUNCTION_ATTRIBUTE int32_t processing_parse_events(const char* file_path, float sample_rate,
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

EXTERNC FUNCTION_ATTRIBUTE int32_t processing_check_events(const char* file_path, char** event_names) {
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

EXTERNC FUNCTION_ATTRIBUTE void processing_event_triggered_average_analysis(const char* file_path,
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

EXTERNC FUNCTION_ATTRIBUTE int32_t** processing_find_spikes(const char* file_path,
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

EXTERNC FUNCTION_ATTRIBUTE void processing_autocorrelation_analysis(float** spike_trains,
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

EXTERNC FUNCTION_ATTRIBUTE void processing_isi_analysis(float** spike_trains,
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

EXTERNC FUNCTION_ATTRIBUTE void processing_cross_correlation_analysis(float** spike_trains,
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

EXTERNC FUNCTION_ATTRIBUTE void processing_average_spike_analysis(const char* file_path,
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
*/

EXTERNC FUNCTION_ATTRIBUTE void processing_cleanup() {
    cleanup_processors();
    
    // Clean up the circular buffer
    if (circularBuffer != nullptr) {
        delete circularBuffer;
        circularBuffer = nullptr;
    }
    
    initialized = false;
}

EXTERNC FUNCTION_ATTRIBUTE int32_t processing_set_band_filter(int channel_idx, float low_cut_off_freq, float high_cut_off_freq) {
    if (!initialized) {
        return -1;  // Not initialized
    }
    
    try {
        // Store values in internal state
        current_low_cut_off_freq = low_cut_off_freq;
        current_high_cut_off_freq = high_cut_off_freq;
        
        // Apply to all processors (same as in byb-lib.cpp)
        if (amModulationProcessor) {
            amModulationProcessor->setBandFilter(channel_idx, low_cut_off_freq, high_cut_off_freq);
        }
        
        if (sampleStreamProcessor) {
            sampleStreamProcessor->setBandFilter(channel_idx, low_cut_off_freq, high_cut_off_freq);
        }
        
        if (thresholdProcessor) {
            thresholdProcessor->setBandFilter(channel_idx, low_cut_off_freq, high_cut_off_freq);
        }
        
        if (fftProcessor) {
            fftProcessor->setBandFilter(channel_idx, low_cut_off_freq, high_cut_off_freq);
        }
        
        return 0;  // Success
    } catch (...) {
        return -3;  // Processing error
    }
}

EXTERNC FUNCTION_ATTRIBUTE int32_t processing_set_notch_filter(float center_freq) {
   
    if (!initialized) {
        return -1;  // Not initialized
    }

    
    try {
        // Store value in internal state
        current_notch_filter_freq = center_freq;
        
        // Apply to all processors (same as in byb-lib.cpp)
        if (amModulationProcessor) {
            // EM_ASM({
            //     console.log("setNotchFilter: ", $0);
            // }, center_freq);
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

EXTERNC FUNCTION_ATTRIBUTE int32_t processing_set_channel_filter_enabled(int32_t channel, bool enabled) {
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

EXTERNC FUNCTION_ATTRIBUTE int32_t processing_map(float* out_data, const float* in_data, int32_t length,
                      float in_min, float in_max, float out_min, float out_max) {
    if (!initialized || !out_data || !in_data || length <= 0) {
        return -1;
    }
    
    try {
        // STEVE change this
        // backyardbrains::utils::AnalysisUtils::map(const_cast<float*>(in_data), out_data, length, in_min, in_max, out_min, out_max);
        return 0;
    } catch (...) {
        return -3;
    }
}

int main() {
    return 0;
}

// #ifdef __EMSCRIPTEN__
// EMSCRIPTEN_BINDINGS(my_module) {
//     emscripten::function("initialize_processors", &initialize_processors);
//     emscripten::function("cleanup_processors", &cleanup_processors);
//     emscripten::function("processing_init", &processing_init);
//     emscripten::function("processing_set_sample_rate", &processing_set_sample_rate);
//     emscripten::function("processing_set_channel_count", &processing_set_channel_count);
//     emscripten::function("processing_set_bits_per_sample", &processing_set_bits_per_sample);
//     emscripten::function("processing_set_selected_channel", &processing_set_selected_channel);
//     // emscripten::function("processing_process_sample_stream", &processing_process_sample_stream);
//     emscripten::function("processing_process_microphone_stream", &processing_process_microphone_stream);
//     emscripten::function("processing_process_playback_stream", &processing_process_playback_stream);
//     // emscripten::function("processing_rms", &processing_rms);
//     // emscripten::function("processing_normalize_signal", &processing_normalize_signal);

//     // emscripten::function("processing_process_fft", &processing_process_fft);
//     emscripten::function("processing_reset_fft_normalization", &processing_reset_fft_normalization);
//     emscripten::function("processing_init", &processing_init);
//     emscripten::function("processing_is_audio_stream_am_modulated", &processing_is_audio_stream_am_modulated);
//     emscripten::function("processing_get_averaged_sample_count", &processing_get_averaged_sample_count);
//     emscripten::function("processing_set_averaged_sample_count", &processing_set_averaged_sample_count);
//     emscripten::function("processing_get_averaging_trigger_type", &processing_get_averaging_trigger_type);
//     emscripten::function("processing_set_averaging_trigger_type", &processing_set_averaging_trigger_type);
//     // emscripten::function("processing_set_threshold", &processing_set_threshold);
//     // emscripten::function("processing_reset_threshold", &processing_reset_threshold);
//     // emscripten::function("processing_resume_threshold", &processing_resume_threshold);

//     // emscripten::function("processing_pause_threshold", &processing_pause_threshold);
//     // emscripten::function("processing_process_threshold", &processing_process_threshold);
//     emscripten::function("processing_set_bpm_processing", &processing_set_bpm_processing);
//     emscripten::function("processing_prepare_for_signal_drawing", &processing_prepare_for_signal_drawing);
//     // emscripten::function("processing_prepare_fft_for_drawing", &processing_prepare_fft_for_drawing);
//     // emscripten::function("processing_prepare_spikes_for_drawing", &processing_prepare_spikes_for_drawing);
//     // emscripten::function("processing_parse_events", &processing_parse_events);
//     // emscripten::function("processing_check_events", &processing_check_events);
//     // emscripten::function("processing_event_triggered_average_analysis", &processing_event_triggered_average_analysis);
//     // emscripten::function("processing_find_spikes", &processing_find_spikes);
//     // emscripten::function("processing_autocorrelation_analysis", &processing_autocorrelation_analysis);    

//     // emscripten::function("processing_isi_analysis", &processing_isi_analysis);    
//     // emscripten::function("processing_cross_correlation_analysis", &processing_cross_correlation_analysis, emscripten::allow_raw_pointers());    
//     // emscripten::function("processing_average_spike_analysis", &processing_average_spike_analysis);    
//     emscripten::function("processing_cleanup", &processing_cleanup);    
//     emscripten::function("processing_set_band_filter", &processing_set_band_filter);    
//     emscripten::function("processing_set_notch_filter", &processing_set_notch_filter);    
//     // emscripten::function("processing_map", &processing_map);    
//     //     function("changeNeuronSimulatorProcess", &changeNeuronSimulatorProcess);
// //     // function("getCanvasBuffer", &getCanvasBuffer);
// //     // function("getCurrentPosition", &getCurrentPosition);
// //     // function("getNeuronCircles", &getNeuronCircles);
//     // function("stopThreadProcess", &stopThreadProcess);
//     // function("changeIdxSelectedProcess", &changeIdxSelectedProcess);
// //     // function("applyLowPassFilter", &applyLowPassFilter);
// //     // register_vector<short>("vector<short>");
// //     // register_vector<short>("LowPassList");
// }
// #endif


EXTERNC FUNCTION_ATTRIBUTE short processing_pass_pointers(short* ptrExpBoardType) {
    _ptrExpBoardType = ptrExpBoardType;
    return 1;
}

EXTERNC FUNCTION_ATTRIBUTE int32_t processing_nwbfile_inject_data_result(short* inSamplesRaw, int* samplesCountRaw, int selectedChannel, int channelCount) {
    if (!initialized || !circularBuffer) {
        return -1;
    }

    short** inSamples = new short*[channelCount];
    for (int i = 0; i < channelCount; i++) {
        inSamples[i] = new short[samplesCountRaw[i]];
        std::copy(inSamplesRaw + i * samplesCountRaw[i], inSamplesRaw + (i + 1) * samplesCountRaw[i], inSamples[i]);
    }


    try {
        circularBuffer->setup(current_sample_rate, current_channel_count);
        circularBuffer->addData(inSamples, samplesCountRaw);
        return 0;
    } catch (...) {
        return -3;
    }
}



EXTERNC FUNCTION_ATTRIBUTE int32_t processing_serial_data_result(short* inSamplesRaw, int* samplesCountRaw, int channelCount) {
    if (!initialized || !circularBuffer) {
        return -1;
    }
    
    short** inSamples = new short*[channelCount];
    for (int i = 0; i < channelCount; i++) {
        inSamples[i] = new short[samplesCountRaw[i]];
        std::copy(inSamplesRaw + i * samplesCountRaw[i], inSamplesRaw + (i + 1) * samplesCountRaw[i], inSamples[i]);
    }
    // platform_log_processing("Channel 1 Length - %d | Channel 2 Length %d\n", samplesCountRaw[0], samplesCountRaw[1]);
    // platform_log_processing("Channel 1 Value - %d | Channel 2 Value %d\n", inSamples[0][0], inSamples[1][0]);
    try {
        circularBuffer->addData(inSamples, samplesCountRaw);

        return 0;
    } catch (...) {
        return -3;
    }
}
