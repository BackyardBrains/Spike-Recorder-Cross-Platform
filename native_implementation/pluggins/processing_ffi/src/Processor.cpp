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
            //__android_log_print(ANDROID_LOG_DEBUG, typeid(*this).name(), "SAMPLE RATE: %1f, CHANNEL COUNT: %1d",sampleRate, channelCount);

            if (initialized) deleteFilters(Processor::channelCount, -1);
            Processor::channelCount = channelCount;

            lowPassFilter = new LowPassFilterPtr[channelCount];
            highPassFilter = new HighPassFilterPtr[channelCount];
            notchFilter = new NotchFilterPtr[channelCount];
            channelFilterEnabled = new bool[channelCount];

            createFilters(Processor::sampleRate, channelCount, -1, lowCutOff, highCutOff, centerFrequency);
        }

        void Processor::applyFilters(int channel, short *data, int sampleCount) {
            if (channelFilterEnabled && !channelFilterEnabled[channel]) {
                return;
            }

            if (lowPassFilteringEnabled) lowPassFilter[channel]->filter(data, sampleCount);
            if (highPassFilteringEnabled) highPassFilter[channel]->filter(data, sampleCount);
            if (notchFilteringEnabled) {
                notchFilter[channel]->filter(data, sampleCount);
            }
        }

        void Processor::setBandFilter(int channelIdx, float lowCutOffFreq, float highCutOffFreq) {
            lowPassFilteringEnabled = highCutOffFreq != -1 && highCutOffFreq != MAX_FILTER_CUT_OFF;
            highPassFilteringEnabled = lowCutOffFreq != -1 && lowCutOffFreq != MIN_FILTER_CUT_OFF;

            // Processor::lowCutOff = lowCutOffFreq;
            // Processor::highCutOff = highCutOffFreq;
            if (initialized) deleteFilters(channelCount, channelIdx);
            createFilters(Processor::sampleRate, channelCount, channelIdx, lowCutOffFreq, highCutOffFreq, centerFrequency);
        }

        void Processor::setNotchFilter(float centerFreq) {
            notchFilteringEnabled = centerFreq != -1 && centerFreq != MIN_FILTER_CUT_OFF;

            Processor::centerFrequency = centerFreq;
            if (initialized) deleteFilters(channelCount, -1);
            lowPassFilter = new LowPassFilterPtr[channelCount];
            highPassFilter = new HighPassFilterPtr[channelCount];
            notchFilter = new NotchFilterPtr[channelCount];
            channelFilterEnabled = new bool[channelCount];

            createFilters(Processor::sampleRate, channelCount, -1, lowCutOff, highCutOff, centerFrequency);
        }

        void Processor::setChannelFilterEnabled(int channel, bool enabled) {
            if (!channelFilterEnabled || channel < 0 || channel >= channelCount) return;
            channelFilterEnabled[channel] = enabled;
        }

        void Processor::createFilters(float sampleRate, int channelCount, int channelIdx, float lowCutOff, float highCutOff, float centerFrequency) {
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
            }
        }

        void Processor::deleteFilters(int channelCount, int channelIdx) {
            if (channelIdx == -1) {
                for (int i = 0; i < channelCount; i++) {
                    delete lowPassFilter[i];
                    delete highPassFilter[i];
                    delete notchFilter[i];
                }
                delete[] lowPassFilter;
                delete[] highPassFilter;
                delete[] notchFilter;
                delete[] channelFilterEnabled;
            }else {
                delete lowPassFilter[channelIdx];
                delete highPassFilter[channelIdx];
                delete notchFilter[channelIdx];
            }
        }
    }
}