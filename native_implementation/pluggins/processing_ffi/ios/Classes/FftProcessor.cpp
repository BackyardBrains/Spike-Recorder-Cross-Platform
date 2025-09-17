//
// Created by Tihomir Leka <tihomir at backyardbrains.com>
//

#include <FftProcessor.h>
#include <cstdlib>
#include <cstring>
#include <string>
#define IS_WIN32 defined(WIN32) || defined(_WIN32) || defined(__WIN32)
void platform_log_fftp(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
    vprintf(fmt, args);
    va_end(args);
}

namespace backyardbrains {

    namespace processing {

        const char *FftProcessor::TAG = "FftProcessor";

        FftProcessor::FftProcessor() {
            input.resize(FFT_WINDOW_SAMPLE_COUNT, 0.0f);
            outReal.resize(audiofft::AudioFFT::ComplexSize(FFT_WINDOW_SAMPLE_COUNT));
            outImaginary.resize(audiofft::AudioFFT::ComplexSize(FFT_WINDOW_SAMPLE_COUNT));

            // initialize object that's doing actual FFT analysis
            fft.init(FFT_WINDOW_SAMPLE_COUNT);
            
            init(getSampleRate());
        }

        FftProcessor::~FftProcessor() {
            std::vector<float>().swap(input);
            std::vector<float>().swap(outReal);
            std::vector<float>().swap(outReal);

            delete[] unanalyzedSamples;
            delete[] sampleBuffer;
        }

        void FftProcessor::setSampleRate(float sampleRate) {
            //__android_log_print(ANDROID_LOG_DEBUG, TAG, "setSampleRate(%f)", sampleRate);
            // platform_log("\n SET SAMPLE RATE : \n");
            
            Processor::setSampleRate(sampleRate);

            resetOnNextCycle = true;
            resetNormalizationOnNextCycle = true;

        }

        void FftProcessor::resetNormalization() {
            resetNormalizationOnNextCycle = true;
        }

        void
        FftProcessor::process(float **outData, int windowCount, int &windowCounter, int &frequencyCounter,
                              int channelCount, short **inSamples, const int *inSampleCount) {
//            long long start = currentTimeInMilliseconds();
//            //__android_log_print(ANDROID_LOG_DEBUG, TAG, "%ld - AFTER CLEAN AND INIT -> %d",
//                                static_cast<long>(currentTimeInMilliseconds() - start), oWindowSampleCount);


            float sampleRate = getSampleRate();
            

            // if (sampleRate != this.sampleRate) {
            //     resetOnNextCycle = true;
            //     resetNormalizationOnNextCycle = true;
                // platform_log("\n CHANGE SAMPLE RATE XAAA : \n");
                // platform_log(std::to_string(sampleRate).c_str());
            //     platform_log("\n CURRENT SAMPLE RATE : \n");
            //     platform_log(std::to_string(currentSampleRate).c_str());
            // }
            auto selectedChannel = getSelectedChannel();
            // check if data for existing channel exists

            if (selectedChannel >= channelCount) {
                windowCounter = 0;
                frequencyCounter = 0;
                return;
            }
            auto sampleCount = inSampleCount[selectedChannel];
            // if max number of samples is sent it means we are seeking
            
            if (sampleCount == oMaxWindowsSampleCount) {
                // platform_log_fftp("\n SEEK RETURN sampleCount == oMaxWindowsSampleCount: \n");
                processSeek(outData, windowCount, windowCounter, frequencyCounter, channelCount, inSamples,
                            inSampleCount);
                return;
            }

            if (resetOnNextCycle) {
                // platform_log("\n INI RESET NEXT CYCLE : \n");
                clean();
                init(sampleRate);

                resetOnNextCycle = false;
            }
            if (resetNormalizationOnNextCycle) {
                // platform_log("\n RESET NORMALIZATION NEXT CYCLE : \n");
                initNormalizationParams();
                resetNormalizationOnNextCycle = false;
            }


            auto *samples = inSamples[selectedChannel];

            const int newUnanalyzedSampleCount = unanalyzedSampleCount + sampleCount;
            auto addWindowsCount = static_cast<uint16_t>(newUnanalyzedSampleCount / oWindowSampleDiffCount);
            // platform_log_fftp("\n unanalyzedSampleCount : \n");
            // platform_log_fftp(std::to_string(unanalyzedSampleCount).c_str());
            // platform_log("\n oWindowSampleDiffCount : \n");
            // platform_log(std::to_string(oWindowSampleDiffCount).c_str());
            // platform_log("\n oWindowSampleCount : \n");
            // platform_log(std::to_string(oWindowSampleCount).c_str());
            // platform_log("\n maxMagnitude : \n");
            // platform_log(std::to_string(maxMagnitude).c_str());
            // platform_log("\n half maxMagnitude : \n");
            // platform_log(std::to_string(halfMaxMagnitude).c_str());
            // platform_log_fftp("\n addWindowsCount : \n");
            // platform_log_fftp(std::to_string(addWindowsCount).c_str());
            
            if (addWindowsCount == 0) {
                std::copy(samples, samples + sampleCount, unanalyzedSamples + unanalyzedSampleCount);
                unanalyzedSampleCount += sampleCount;
                // platform_log_fftp("\n addWindowsCount: \n");
                // platform_log_fftp(std::to_string(unanalyzedSampleCount).c_str());
                // platform_log_fftp("\n oWindowSampleDiffCount: \n");
                // platform_log_fftp(std::to_string(oWindowSampleDiffCount).c_str());

                windowCounter = addWindowsCount;
                frequencyCounter = FFT_WINDOW_30HZ_DATA_SIZE;

                return;
            } else if (addWindowsCount >= windowCount) {
                platform_log_fftp("\n addWindowsCount >= windowCount : \n");

                processSeek(outData, windowCount, windowCounter, frequencyCounter, channelCount, inSamples,
                            inSampleCount);
                return;
            }

            auto *samplesToAnalyze = new float[newUnanalyzedSampleCount];
            if (unanalyzedSampleCount > 0)
                std::copy(unanalyzedSamples, unanalyzedSamples + unanalyzedSampleCount, samplesToAnalyze);
            std::copy(samples, samples + sampleCount, samplesToAnalyze + unanalyzedSampleCount);

            int offset = 0;
            auto *in = new short[oWindowSampleCount]{0};
            auto dsSamples = new float[dsIndexCount]{0};
            int counter = 0;
            for (int i = 0; i < addWindowsCount; i++) {
                // construct next window of data for analysis
                offset = oWindowSampleDiffCount * i;
                std::copy(sampleBuffer + oWindowSampleDiffCount, sampleBuffer + oWindowSampleCount, in);
                std::copy(samplesToAnalyze + offset, samplesToAnalyze + offset + oWindowSampleDiffCount,
                          in + oWindowSampleCount - oWindowSampleDiffCount);

                // simple downsampling because only low frequencies are required
                for (int j = 0; j < dsIndexCount; j++)
                    dsSamples[j] = in[dsIndices[j]];

                // perform FFT analysis
                input.assign(dsSamples, dsSamples + dsIndexCount);

                // Safety check: ensure FFT is properly initialized and vectors are correct size
                if (input.size() == dsIndexCount && 
                    outReal.size() == audiofft::AudioFFT::ComplexSize(dsIndexCount) &&
                    outImaginary.size() == audiofft::AudioFFT::ComplexSize(dsIndexCount)) {
                    fft.fft(input.data(), outReal.data(), outImaginary.data());
                } else {
                    // Skip FFT processing if sizes don't match
                    continue;
                }

                // calculate DC component
                outData[counter][0] = static_cast<float>(sqrtf(outReal[0] * outReal[0]) / halfMaxMagnitude - 1.0);
                // calculate magnitude for all freq.
                for (int j = 1; j < FFT_WINDOW_30HZ_DATA_SIZE; j++) {
                    outData[counter][j] = sqrtf(outReal[j] * outReal[j] + outImaginary[j] * outImaginary[j]);
                    if (outData[counter][j] > maxMagnitude) {
                        maxMagnitude = outData[counter][j];
                        halfMaxMagnitude = maxMagnitude * 0.5f;
                    }
                    outData[counter][j] = static_cast<float>(outData[counter][j] / halfMaxMagnitude - 1.0);
                    // outData[counter][j] = static_cast <float> (rand()) / static_cast <float> (RAND_MAX);;
                }
                counter++;

                std::move(sampleBuffer + oWindowSampleDiffCount, sampleBuffer + oWindowSampleCount, sampleBuffer);
                std::copy(samplesToAnalyze + offset, samplesToAnalyze + offset + oWindowSampleDiffCount,
                          sampleBuffer + oWindowSampleCount - oWindowSampleDiffCount);
            }

            std::copy(samplesToAnalyze + oWindowSampleDiffCount * addWindowsCount,
                      samplesToAnalyze + newUnanalyzedSampleCount, unanalyzedSamples);
            unanalyzedSampleCount = newUnanalyzedSampleCount - oWindowSampleDiffCount * addWindowsCount;

            windowCounter = counter;
            frequencyCounter = FFT_WINDOW_30HZ_DATA_SIZE;
            // platform_log_fftp("\nwindowCounter : \n");
            // platform_log_fftp(std::to_string(counter).c_str());

            delete[] dsSamples;
            delete[] in;
            delete[] samplesToAnalyze;
        }

        void FftProcessor::processSeek(float **outData, int windowCount, int &windowCounter, int &frequencyCounter,
                                       int channelCount, short **inSamples, const int *inSampleCount) {
            float sampleRate = getSampleRate();
            auto selectedChannel = getSelectedChannel();
            // check if data for existing channel exists
            if (selectedChannel >= channelCount) {
                windowCounter = 0;
                frequencyCounter = 0;
                return;
            }

            if (resetOnNextCycle) {
                clean();
                init(sampleRate);
                resetOnNextCycle = false;
            }
            if (resetNormalizationOnNextCycle) {
                initNormalizationParams();
                resetNormalizationOnNextCycle = false;
            }

            auto sampleCount = inSampleCount[selectedChannel];
            auto *samples = inSamples[selectedChannel];

            // just take exact number of samples that we need not all that came in
            auto *tmpSamples = new short[oMaxWindowsSampleCount]{0};
            int start1 = std::max(0, sampleCount - oMaxWindowsSampleCount);
            int start2 = std::max(0, oMaxWindowsSampleCount - sampleCount);
            std::copy(samples + start1, samples + sampleCount, tmpSamples + start2);


            int offset = 0;
            auto *in = new short[oWindowSampleCount]{0};
            auto dsSamples = new float[dsIndexCount]{0};
            int counter = 0;
            for (int i = 0; i < windowCount; i++) {
                // construct next window of data for analysis
                offset = oWindowSampleDiffCount * i;
                std::copy(tmpSamples + offset, tmpSamples + offset + oWindowSampleCount, in);

                // simple downsampling because only low frequencies are required
                for (int j = 0; j < dsIndexCount; j++)
                    dsSamples[j] = in[dsIndices[j]];

                // perform FFT analysis
                input.assign(dsSamples, dsSamples + dsIndexCount);
                
                // Safety check: ensure FFT is properly initialized and vectors are correct size
                if (input.size() == dsIndexCount && 
                    outReal.size() == audiofft::AudioFFT::ComplexSize(dsIndexCount) &&
                    outImaginary.size() == audiofft::AudioFFT::ComplexSize(dsIndexCount)) {
                    fft.fft(input.data(), outReal.data(), outImaginary.data());
                } else {
                    // Skip FFT processing if sizes don't match
                    continue;
                }

                // calculate DC component
                outData[counter][0] = static_cast<float>(sqrtf(outReal[0] * outReal[0]) / halfMaxMagnitude -
                                                         1.0);
                // calculate magnitude for all freq.
                for (int j = 1; j < FFT_WINDOW_30HZ_DATA_SIZE; j++) {
                    outData[counter][j] = sqrtf(outReal[j] * outReal[j] + outImaginary[j] * outImaginary[j]);
                    if (outData[counter][j] > maxMagnitude) {
                        maxMagnitude = outData[counter][j];
                        halfMaxMagnitude = maxMagnitude * 0.5f;
                    }
                    outData[counter][j] = static_cast<float>(outData[counter][j] / halfMaxMagnitude - 1.0);
                    // outData[counter][j] = static_cast <float> (rand()) / static_cast <float> (RAND_MAX);;
                }
                counter++;

            }

            std::copy(tmpSamples + oMaxWindowsSampleCount - oWindowSampleCount, tmpSamples + oMaxWindowsSampleCount,
                      sampleBuffer);

            windowCounter = counter;
            frequencyCounter = FFT_WINDOW_30HZ_DATA_SIZE;
            // platform_log_fftp("\n windowCounter : \n");
            // platform_log_fftp(std::to_string(windowCounter).c_str());

            delete[] dsSamples;
            delete[] tmpSamples;
            delete[] in;
        }

//        long long FftProcessor::currentTimeInMilliseconds() {
//            struct timeval tv{};
//            gettimeofday(&tv, nullptr);
//            return ((tv.tv_sec * 1000) + (tv.tv_usec / 1000));
//        }

        void FftProcessor::init(float sampleRate) {
            //__android_log_print(ANDROID_LOG_DEBUG, TAG, "init(%f)", sampleRate);
            // platform_log("\n sampleRate : \n");
            // platform_log(std::to_string(sampleRate).c_str());

            // calculate number of samples that fit in single FFT window before downsampling
            oWindowSampleCount = static_cast<uint32_t>(FFT_WINDOW_TIME_LENGTH * sampleRate);
            // calculate difference between two consecutive FFT windows represented in number of samples
            oWindowSampleDiffCount = static_cast<uint32_t>(oWindowSampleCount *
                                                           (1.0f - (float) FFT_WINDOW_OVERLAP_PERCENT / 100.0f));
            oMaxWindowsSampleCount =
                    FFT_WINDOW_COUNT * oWindowSampleDiffCount + oWindowSampleCount - oWindowSampleDiffCount;

            // cannot hold more then oWindowSampleCount - 1 number of samples
            unanalyzedSamples = new float[oWindowSampleCount]{0};
            unanalyzedSampleCount = 0;

            // always holds oWindowSampleCount number of samples (0s at the begining)
            sampleBuffer = new float[oWindowSampleCount]{0};

            auto dsFactor = static_cast<int>(FFT_WINDOW_TIME_LENGTH * sampleRate / FFT_WINDOW_SAMPLE_COUNT);
            dsIndexCount = oWindowSampleCount / dsFactor;
            dsIndices = new int[dsIndexCount];
            for (int j = 0; j < dsIndexCount; j++)
                dsIndices[j] = dsFactor * j;

            // CRITICAL FIX: Re-initialize FFT with the correct size
            // The FFT was initialized with FFT_WINDOW_SAMPLE_COUNT in constructor,
            // but we need to use dsIndexCount for actual processing
            fft.init(dsIndexCount);
            
            // Resize the output vectors to match the FFT size
            outReal.resize(audiofft::AudioFFT::ComplexSize(dsIndexCount));
            outImaginary.resize(audiofft::AudioFFT::ComplexSize(dsIndexCount));
            input.resize(dsIndexCount);

//            initNormalizationParams();
        }

        void FftProcessor::initNormalizationParams() {
            //__android_log_print(ANDROID_LOG_DEBUG, TAG, "initNormalizationParams()");
            // platform_log("\n init Normalization params : \n");


            maxMagnitude = 4.83;
            halfMaxMagnitude = maxMagnitude * .5f;
        }

        void FftProcessor::clean() {
            delete[] unanalyzedSamples;
            unanalyzedSampleCount = 0;

            delete[] sampleBuffer;

            delete[] dsIndices;
        }
    }
}