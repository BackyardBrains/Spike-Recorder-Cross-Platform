//
// Created by  Tihomir Leka <tihomir at backyardbrains.com>
//
#include "Processor.h"
#ifdef __EMSCRIPTEN__
#include <emscripten.h>
#endif
// #include <string>
// #define IS_WIN32 defined(WIN32) || defined(_WIN32) || defined(__WIN32)
// void platform_log_filtering(const char *fmt, ...) {
//     va_list args;
//     va_start(args, fmt);
//     vprintf(fmt, args);
//     va_end(args);
// }

namespace backyardbrains {

    namespace processing {

        Processor::Processor(float sampleRate, int channelCount, int bitsPerSample) {
            Processor::sampleRate = sampleRate;
            Processor::channelCount = channelCount;
            Processor::bitsPerSample = bitsPerSample;
            channelFilterEnabled = new bool[channelCount];
            for (int i = 0; i < channelCount; i++) {
                channelFilterEnabled[i] = true;
            }

            lowPassFilter = new LowPassFilterPtr[channelCount];
            highPassFilter = new HighPassFilterPtr[channelCount];
            notchFilter = new NotchFilterPtr[channelCount];
            channelFilterEnabled = new bool[channelCount];

            createFilters(0, channelCount, -1, lowCutOff, highCutOff, centerFrequency);

            initialized = true;
        }

        Processor::~Processor() = default;

        float Processor::getSampleRate() {
            return sampleRate;
        }

        void Processor::setSampleRate(float sampleRate) {
            if (initialized) deleteFilters(channelCount, -1);
            Processor::sampleRate = sampleRate;
            // platform_log_filtering("SET SAMPLE RATE \n");

            lowPassFilter = new LowPassFilterPtr[channelCount];
            highPassFilter = new HighPassFilterPtr[channelCount];
            notchFilter = new NotchFilterPtr[channelCount];
            channelFilterEnabled = new bool[channelCount];

            createFilters(sampleRate, channelCount, -1, lowCutOff, highCutOff, centerFrequency);
        }

        int Processor::getChannelCount() {
            return channelCount;
        }

        void Processor::setChannelCount(int channelCount) {
            if (initialized) deleteFilters(Processor::channelCount, -1);
            Processor::channelCount = channelCount;
            // platform_log_filtering("SET CHANNEL COUNT \n");

            lowPassFilter = new LowPassFilterPtr[channelCount];
            highPassFilter = new HighPassFilterPtr[channelCount];
            notchFilter = new NotchFilterPtr[channelCount];
            channelFilterEnabled = new bool[channelCount];

            createFilters(Processor::sampleRate, channelCount, -1, lowCutOff, highCutOff, centerFrequency);

        }

        int Processor::getBitsPerSample() {
            return bitsPerSample;
        }

        void Processor::setBitsPerSample(int bitsPerSample) {
            if (initialized) deleteFilters(Processor::channelCount, -1);
            Processor::bitsPerSample = bitsPerSample;
            // platform_log_filtering("SET BITS PER SAMPLE \n");

            lowPassFilter = new LowPassFilterPtr[channelCount];
            highPassFilter = new HighPassFilterPtr[channelCount];
            notchFilter = new NotchFilterPtr[channelCount];
            channelFilterEnabled = new bool[channelCount];

            createFilters(Processor::sampleRate, channelCount, -1, lowCutOff, highCutOff, centerFrequency);
        }

        int Processor::getSelectedChannel() {
            return selectedChannel;
        }

        void Processor::setSelectedChannel(int selectedChannel) {
            Processor::selectedChannel = selectedChannel;
        }

        void Processor::setSampleRateAndChannelCount(float sampleRate, int channelCount) {
            if (initialized) deleteFilters(Processor::channelCount, -1);
            Processor::channelCount = channelCount;
            // platform_log_filtering("SET SAMPLE RATE AND CHANNEL COUNT \n");

            lowPassFilter = new LowPassFilterPtr[channelCount];
            highPassFilter = new HighPassFilterPtr[channelCount];
            notchFilter = new NotchFilterPtr[channelCount];
            channelFilterEnabled = new bool[channelCount];

            createFilters(Processor::sampleRate, channelCount, -1, lowCutOff, highCutOff, centerFrequency);        
        }

        void Processor::applyFilters(int channel, short *data, int sampleCount) {
            if (!channelFilterEnabled || channel < 0 || channel >= channelCount || !channelFilterEnabled[channel]) {
                return;
            }

            if (sampleRate <= 0 || lowPassFilter == nullptr || highPassFilter == nullptr || notchFilter == nullptr) {
                return;
            }

            if (lowPassFilteringEnabled && lowPassFilter[channel] != nullptr) {
                lowPassFilter[channel]->filter(data, sampleCount);
            }
            if (highPassFilteringEnabled && highPassFilter[channel] != nullptr) {
                highPassFilter[channel]->filter(data, sampleCount);
            }
            if (notchFilteringEnabled && notchFilter[channel] != nullptr) {
                notchFilter[channel]->filter(data, sampleCount);
            }
        }

        void Processor::setBandFilter(int channelIdx, float lowCutOffFreq, float highCutOffFreq) {
            lowPassFilteringEnabled = highCutOffFreq != -1 && highCutOffFreq != MAX_FILTER_CUT_OFF;
            highPassFilteringEnabled = lowCutOffFreq != -1 && lowCutOffFreq != MIN_FILTER_CUT_OFF;

            if (lowCutOffFreq == -1 || highCutOffFreq == -1) {
                return;
            }

            Processor::lowCutOff = lowCutOffFreq;
            Processor::highCutOff = highCutOffFreq;

            if (initialized) {
                deleteFilters(channelCount, channelIdx);
                if (lowPassFilter == nullptr || highPassFilter == nullptr || notchFilter == nullptr || channelFilterEnabled == nullptr) {
                    lowPassFilter = new LowPassFilterPtr[channelCount];
                    highPassFilter = new HighPassFilterPtr[channelCount];
                    notchFilter = new NotchFilterPtr[channelCount];
                    channelFilterEnabled = new bool[channelCount];
                    for (int i = 0; i < channelCount; i++) {
                        lowPassFilter[i] = nullptr;
                        highPassFilter[i] = nullptr;
                        notchFilter[i] = nullptr;
                        channelFilterEnabled[i] = false;
                    }
                }
            }
            createFilters(Processor::sampleRate, channelCount, channelIdx, lowCutOffFreq, highCutOffFreq, centerFrequency);
        }

        void Processor::setNotchFilter(float centerFreq) {
            notchFilteringEnabled = centerFreq != -1 && centerFreq != MIN_FILTER_CUT_OFF;
            Processor::centerFrequency = centerFreq;

            if (!initialized || notchFilter == nullptr) {
                return;
            }

            for (int i = 0; i < channelCount; i++) {
                if (notchFilter[i] == nullptr) {
                    notchFilter[i] = new NotchFilter();
                    notchFilter[i]->initWithSamplingRate(sampleRate);
                }
                notchFilter[i]->setCenterFrequency(centerFrequency);
                notchFilter[i]->setQ(1.0);
            }
        }

        void Processor::setChannelFilterEnabled(int channel, bool enabled) {
            if (!channelFilterEnabled || channel < 0 || channel >= channelCount) return;
            channelFilterEnabled[channel] = enabled;
        }

        void Processor::createFilters(float sampleRate, int channelCount, int channelIdx, float lowCutOff, float highCutOff, float centerFrequency) {
            // createFilters(48000, channelCount, channelIdx, lowCutOffFreq, highCutOffFreq, centerFrequency);

            // if (lowPassFilter == nullptr || highPassFilter == nullptr || notchFilter == nullptr) {
            //     lowPassFilter = new LowPassFilterPtr[channelCount];
            //     highPassFilter = new HighPassFilterPtr[channelCount];
            //     notchFilter = new NotchFilterPtr[channelCount];
            //     channelFilterEnabled = new bool[channelCount];
            // }

            for (int idx = 0; idx < channelCount; idx++) {
                if (channelIdx == -1) {
                    int i = idx;                 
                    // low pass filters
                    lowPassFilter[i] = new LowPassFilter();
                    lowPassFilter[i]->initWithSamplingRate(sampleRate);
                    if (highCutOff > sampleRate / 2.0f) highCutOff = sampleRate / 2.0f;
                    lowPassFilter[i]->setCornerFrequency(highCutOff);
                    lowPassFilter[i]->setQ(0.5f);
                    // high pass filters
                    highPassFilter[i] = new HighPassFilter();
                    highPassFilter[i]->initWithSamplingRate(sampleRate);
                    if (lowCutOff < 0) lowCutOff = 0;
                    highPassFilter[i]->setCornerFrequency(lowCutOff);
                    highPassFilter[i]->setQ(0.5f);
                    // notch filter
                    notchFilter[i] = new NotchFilter();
                    notchFilter[i]->initWithSamplingRate(sampleRate);
                    notchFilter[i]->setCenterFrequency(centerFrequency);
                    notchFilter[i]->setQ(1.0);
                    channelFilterEnabled[i] = true;
                }else {
                    int i = idx;
                    if (i == channelIdx) {
                        // platform_log_filtering("CREATING filters for channel %d  \n", channelIdx);
                        // low pass filters
                        lowPassFilter[i] = new LowPassFilter();
                        lowPassFilter[i]->initWithSamplingRate(sampleRate);
                        if (highCutOff > sampleRate / 2.0f) highCutOff = sampleRate / 2.0f;
                        lowPassFilter[i]->setCornerFrequency(highCutOff);
                        lowPassFilter[i]->setQ(0.5f);
                        // high pass filters
                        highPassFilter[i] = new HighPassFilter();
                        highPassFilter[i]->initWithSamplingRate(sampleRate);
                        if (lowCutOff < 0) lowCutOff = 0;
                        highPassFilter[i]->setCornerFrequency(lowCutOff);
                        highPassFilter[i]->setQ(0.5f);
                        // notch filter
                        notchFilter[i] = new NotchFilter();
                        notchFilter[i]->initWithSamplingRate(sampleRate);
                        notchFilter[i]->setCenterFrequency(centerFrequency);
                        notchFilter[i]->setQ(1.0);
                        channelFilterEnabled[i] = true;
                        break;
                    }
                }
            }
        }

        void Processor::deleteFilters(int channelCount, int channelIdx) {
            if (channelIdx == -1) {
                if (lowPassFilter != nullptr) {
                    for (int i = 0; i < channelCount; i++) {
                        if (lowPassFilter[i] != nullptr) {
                            delete lowPassFilter[i];
                            lowPassFilter[i] = nullptr;
                        }
                    }
                    delete[] lowPassFilter;
                    lowPassFilter = nullptr;
                }
                if (highPassFilter != nullptr) {
                    for (int i = 0; i < channelCount; i++) {
                        if (highPassFilter[i] != nullptr) {
                            delete highPassFilter[i];
                            highPassFilter[i] = nullptr;
                        }
                    }
                    delete[] highPassFilter;
                    highPassFilter = nullptr;
                }
                if (notchFilter != nullptr) {
                    for (int i = 0; i < channelCount; i++) {
                        if (notchFilter[i] != nullptr) {
                            delete notchFilter[i];
                            notchFilter[i] = nullptr;
                        }
                    }
                    delete[] notchFilter;
                    notchFilter = nullptr;
                }
                if (channelFilterEnabled != nullptr) {
                    delete[] channelFilterEnabled;
                    channelFilterEnabled = nullptr;
                }
            } else {
                if (channelIdx < 0 || channelIdx >= channelCount) {
                    return;
                }
                if (lowPassFilter != nullptr && lowPassFilter[channelIdx] != nullptr) {
                    delete lowPassFilter[channelIdx];
                    lowPassFilter[channelIdx] = nullptr;
                }
                if (highPassFilter != nullptr && highPassFilter[channelIdx] != nullptr) {
                    delete highPassFilter[channelIdx];
                    highPassFilter[channelIdx] = nullptr;
                }
                if (notchFilter != nullptr && notchFilter[channelIdx] != nullptr) {
                    delete notchFilter[channelIdx];
                    notchFilter[channelIdx] = nullptr;
                }
            }
        }
    }
}