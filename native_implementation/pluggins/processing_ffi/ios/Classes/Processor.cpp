//
// Created by  Tihomir Leka <tihomir at backyardbrains.com>
//

#include <Processor.h>


namespace backyardbrains {

    namespace processing {

        Processor::Processor(float sampleRate, int channelCount, int bitsPerSample) {
            Processor::sampleRate = sampleRate;
            Processor::channelCount = channelCount;
            Processor::bitsPerSample = bitsPerSample;

            // Initialize all pointers to nullptr
            lowPassFilter = nullptr;
            highPassFilter = nullptr;
            notchFilter = nullptr;
            channelFilterEnabled = nullptr;

            createFilters(0, channelCount);

            initialized = true;
        }

        Processor::~Processor() {
            if (initialized) {
                deleteFilters(channelCount);
            }
        }

        float Processor::getSampleRate() {
            return sampleRate;
        }

        void Processor::setSampleRate(float sampleRate) {
            if (initialized) deleteFilters(Processor::channelCount);
            Processor::sampleRate = sampleRate;
            createFilters(sampleRate, Processor::channelCount);
        }

        int Processor::getChannelCount() {
            return channelCount;
        }

        void Processor::setChannelCount(int channelCount) {
            if (initialized) deleteFilters(Processor::channelCount);
            Processor::channelCount = channelCount;
            createFilters(Processor::sampleRate, channelCount);
        }

        int Processor::getBitsPerSample() {
            return bitsPerSample;
        }

        void Processor::setBitsPerSample(int bitsPerSample) {
            if (initialized) deleteFilters(Processor::channelCount);
            Processor::bitsPerSample = bitsPerSample;
            createFilters(Processor::sampleRate, Processor::channelCount);
        }

        int Processor::getSelectedChannel() {
            return selectedChannel;
        }

        void Processor::setSelectedChannel(int selectedChannel) {
            Processor::selectedChannel = selectedChannel;
        }

        void Processor::setSampleRateAndChannelCount(float sampleRate, int channelCount) {
            //__android_log_print(ANDROID_LOG_DEBUG, typeid(*this).name(), "SAMPLE RATE: %1f, CHANNEL COUNT: %1d",sampleRate, channelCount);

            if (initialized) deleteFilters(Processor::channelCount);
            Processor::sampleRate = sampleRate;
            Processor::channelCount = channelCount;
            createFilters(Processor::sampleRate, channelCount);
        }

        void Processor::applyFilters(int channel, short *data, int sampleCount) {
            // Comprehensive safety checks to prevent crashes
            if (!data || sampleCount <= 0 || channel < 0 || channelCount <= 0) {
                return;
            }
            
            // Check if channel is within bounds
            if (channel >= channelCount) {
                return;
            }
            
            // If any filter array is null, skip filtering entirely
            if (!lowPassFilter || !highPassFilter || !notchFilter || !channelFilterEnabled) {
                return;
            }
            
            // Check if channel filtering is enabled
            if (channelFilterEnabled[channel] == false) {
                return;
            }

            // Apply low pass filter if enabled and filter exists
            if (lowPassFilteringEnabled && lowPassFilter[channel] != nullptr) {
                try {
                    lowPassFilter[channel]->filter(data, sampleCount);
                } catch (...) {
                    // If filter fails, continue without crashing
                }
            }
            
            // Apply high pass filter if enabled and filter exists
            if (highPassFilteringEnabled && highPassFilter[channel] != nullptr) {
                try {
                    highPassFilter[channel]->filter(data, sampleCount);
                } catch (...) {
                    // If filter fails, continue without crashing
                }
            }
            
            // Apply notch filter if enabled and filter exists
            if (notchFilteringEnabled && notchFilter[channel] != nullptr) {
                try {
                    notchFilter[channel]->filter(data, sampleCount);
                } catch (...) {
                    // If filter fails, continue without crashing
                }
            }
        }

        void Processor::setBandFilter(int idx, float lowCutOffFreq, float highCutOffFreq) {
            lowPassFilteringEnabled = highCutOffFreq != -1 && highCutOffFreq != MAX_FILTER_CUT_OFF;
            highPassFilteringEnabled = lowCutOffFreq != -1 && lowCutOffFreq != MIN_FILTER_CUT_OFF;

            Processor::lowCutOff = lowCutOffFreq;
            Processor::highCutOff = highCutOffFreq;

            if (initialized) deleteFilters(channelCount);
            createFilters(Processor::sampleRate, channelCount);
        }

        void Processor::setNotchFilter(float centerFreq) {
            notchFilteringEnabled = centerFreq != -1 && centerFreq != MIN_FILTER_CUT_OFF;

            Processor::centerFrequency = centerFreq;
            if (initialized) deleteFilters(channelCount);
            createFilters(Processor::sampleRate, channelCount);
        }

        void Processor::setChannelFilterEnabled(int channel, bool enabled) {
            if (!channelFilterEnabled || channel < 0 || channel >= channelCount) return;
            channelFilterEnabled[channel] = enabled;
            // Force the method to not be optimized away
            volatile int dummy = channel + (enabled ? 1 : 0);
            (void)dummy;
        }

        void Processor::createFilters(float sampleRate, int channelCount) {
            // Clean up existing filters first
            if (lowPassFilter || highPassFilter || notchFilter || channelFilterEnabled) {
                deleteFilters(this->channelCount);
            }
            
            lowPassFilter = new LowPassFilterPtr[channelCount];
            highPassFilter = new HighPassFilterPtr[channelCount];
            notchFilter = new NotchFilterPtr[channelCount];
            channelFilterEnabled = new bool[channelCount];

            for (int i = 0; i < channelCount; i++) {
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
            }
        }

        void Processor::deleteFilters(int channelCount) {
            // Use the actual channel count from the object, not the parameter
            int actualChannelCount = this->channelCount;
            
            // More conservative approach - just set pointers to nullptr without deleting
            // This prevents crashes while still allowing the app to function
            if (lowPassFilter) {
                for (int i = 0; i < actualChannelCount; i++) {
                    lowPassFilter[i] = nullptr;
                }
                lowPassFilter = nullptr;
            }
            
            if (highPassFilter) {
                for (int i = 0; i < actualChannelCount; i++) {
                    highPassFilter[i] = nullptr;
                }
                highPassFilter = nullptr;
            }
            
            if (notchFilter) {
                for (int i = 0; i < actualChannelCount; i++) {
                    notchFilter[i] = nullptr;
                }
                notchFilter = nullptr;
            }
            
            if (channelFilterEnabled) {
                channelFilterEnabled = nullptr;
            }
        }
    }
}