//
// Created by Tihomir Leka <tihomir at backyardbrains.com>
//
#ifdef __EMSCRIPTEN__
    #include <emscripten/bind.h>
    using namespace emscripten;
    #include <emscripten.h>
    #include <wasm_simd128.h>
#endif
#include <DrawingUtils.h>
#ifdef __ANDROID__
#include <android/log.h>
#endif

#include <cstring>
#include <string>
#include <cstdarg>
#define IS_WIN32 defined(WIN32) || defined(_WIN32) || defined(__WIN32)

// Resolve byte ambiguity for Windows
#ifdef _WIN32
    #ifdef byte
    #undef byte
    #endif
    typedef unsigned char byte;
#endif
void platform_log(const char *fmt, ...) {
    va_list args;
    va_start(args, fmt);
#ifdef __ANDROID__
    __android_log_vprint(ANDROID_LOG_VERBOSE, "ndk", fmt, args);
#else
    vprintf(fmt, args);
#endif
    va_end(args);
}

namespace backyardbrains {

    namespace utils {

        void DrawingUtils::prepareSignalForDrawing(float **outSamples, int *outSampleCounts, float *outEventIndices,
                                                   int &outEventCount, short **inSamples, int channelCount,
                                                   const int *inEventIndices, int inEventCount, int fromSample,
                                                   int toSample, int drawSurfaceWidth) {
            auto **envelopedSamples = new short *[channelCount];
            for (int i = 0; i < channelCount; i++) {
                envelopedSamples[i] = new short[drawSurfaceWidth * 5];
            }
            envelope(envelopedSamples, outSampleCounts, outEventIndices, outEventCount, inSamples, channelCount,
                     inEventIndices, inEventCount, fromSample, toSample, drawSurfaceWidth);

            float xStep = (float) drawSurfaceWidth / (outSampleCounts[0] - 1);
            int sampleIndex = 0;
            for (int i = 0; i < inEventCount; i++)
                outEventIndices[i] *= xStep;
            for (int i = 0; i < channelCount; i++) {
                for (int j = 0; j < outSampleCounts[i]; j++) {
                    //outSamples[i][sampleIndex++] = xStep * j;
                    outSamples[i][sampleIndex++] = (float) envelopedSamples[i][j];
                }
                outSampleCounts[i] = sampleIndex;
                sampleIndex = 0;
            }

            for (int i = 0; i < channelCount; i++) {
                delete[] envelopedSamples[i];
            }
            delete[] envelopedSamples;
        }

        void
        DrawingUtils::prepareFftForDrawing(float *outVertices, short *outIndices, float *outColors, int &outVertexCount,
                                           int &outIndexCount, int &outColorCount, float **fft, const int windowCount,
                                           const int windowSize, const float width, const float height) {
            int widthSegments = windowCount - 1;
            int heightSegments = windowSize - 1;

            outVertexCount = (widthSegments + 1) * (heightSegments + 1) * 2;
            outIndexCount = widthSegments * heightSegments * 6;
            outColorCount = (widthSegments + 1) * (heightSegments + 1) * 4;

            float xOffset = 0;
            float yOffset = 0;
            float xWidth = width / widthSegments;
            float yHeight = height / heightSegments;
            int currentVertex = 0;
            int currentIndex = 0;
            int currentColor = 0;
            auto w = (short) (widthSegments + 1);


            // platform_log("\nWindow Count : \n");
            // platform_log(std::to_string(windowCount).c_str());
            // platform_log("\nWidth Segments : \n");
            // platform_log(std::to_string(xWidth).c_str());
            // platform_log("\nHeight Segments: \n");
            // platform_log(std::to_string(yHeight).c_str());
            for (int y = 0; y < heightSegments + 1; y++) {
                for (int x = 0; x < widthSegments + 1; x++) {

                    outVertices[currentVertex] = xOffset + x * xWidth;
                    outVertices[currentVertex + 1] = yOffset + y * yHeight;
                    currentVertex += 2;

                    int n = y * (widthSegments + 1) + x;

                    if (y < heightSegments && x < widthSegments) {
                        // Face one
                        outIndices[currentIndex] = (short) n;
                        outIndices[currentIndex + 1] = (short) (n + 1);
                        outIndices[currentIndex + 2] = (short) (n + w);
                        // Face two
                        outIndices[currentIndex + 3] = (short) (n + 1);
                        outIndices[currentIndex + 4] = (short) (n + 1 + w);
                        outIndices[currentIndex + 5] = (short) (n + 1 + w - 1);

                        currentIndex += 6;
                    }

                    float gray = fft[x][y];
                    outColors[currentColor] = red(gray);
                    outColors[currentColor + 1] = green(gray);
                    outColors[currentColor + 2] = blue(gray);
                    outColors[currentColor + 3] = 1.0f;
                    // platform_log("\nCurrent FFT: \n");
                    // platform_log(std::to_string(fft[x][y]).c_str());
                    // platform_log("\nCurrent Color RED: \n");
                    // platform_log(std::to_string(outColors[currentColor + 0]).c_str());
                    // platform_log("\nCurrent Color Green: \n");
                    // platform_log(std::to_string(outColors[currentColor + 1]).c_str());
                    // platform_log("\nCurrent Color Blue: \n");
                    // platform_log(std::to_string(outColors[currentColor + 2]).c_str());

                    currentColor += 4;
                }
            }
            // outVertices[0] = -123;
            // outVertices[1] = -456;

            // platform_log("\Current Vertex: \n");
            // platform_log(std::to_string(currentVertex).c_str());
            // platform_log("\Current Color: \n");
            // platform_log(std::to_string(currentColor).c_str());

        }

        void DrawingUtils::prepareSpikesForDrawing(float *outVertices, float *outColors, int &outVertexCount,
                                                   int &outColorCount, float *inSpikeVertices, int *inSpikeIndices,
                                                   int spikeCount, float *colorInRange, float *colorOutOfRange,
                                                   int rangeStartIndex, int rangeEndIndex, float sampleStart,
                                                   int sampleEnd, int drawStart, int drawEnd, int sampleCount,
                                                   int width) {
            int glWindowWidth = drawEnd - drawStart;
            float scale = static_cast<float>(width) / static_cast<float>(sampleCount - 1);
            float index, value;
            for (int i = 0; i < spikeCount; i++) {
                index = static_cast<float>(inSpikeIndices[i]);
                if (sampleStart <= index && index < sampleEnd) {
                    index += static_cast<float>(glWindowWidth - sampleEnd);
                    index = backyardbrains::utils::AnalysisUtils::map(index, 0.0f, static_cast<float>(glWindowWidth), 0.0f, static_cast<float>(sampleCount));
                    index *= scale;
                    value = inSpikeVertices[i];
                    outVertices[outVertexCount++] = index;
                    outVertices[outVertexCount++] = value;
                    if (value >= rangeStartIndex && value < rangeEndIndex) {
                        std::copy(colorInRange, colorInRange + 4, outColors + outColorCount);
                    } else {
                        std::copy(colorOutOfRange, colorOutOfRange + 4, outColors + outColorCount);
                    }
                    outColorCount += 4;
                }
            }
        }

        void DrawingUtils::envelope(short **outSamples, int *outSampleCount, float *outEventIndices,
                                    int &outEventIndicesCount, short **inSamples, int channelCount,
                                    const int *inEventIndices, int inEventIndicesCount, int fromSample, int toSample,
                                    int drawSurfaceWidth) {
            int drawSamplesCount = toSample - fromSample;
            if (drawSamplesCount < drawSurfaceWidth) drawSurfaceWidth = drawSamplesCount;

            short sample;
            short min = SHRT_MAX, max = SHRT_MIN;
            int samplesPerPixel = drawSamplesCount / drawSurfaceWidth;
            int samplesPerPixelRest = drawSamplesCount % drawSurfaceWidth;
            int samplesPerEnvelope = samplesPerPixel * 2; // multiply by 2 because we save min and max
            // int samplesPerEnvelope = samplesPerPixel * 2; // multiply by 2 because we save min and max
            int envelopeCounter = 0, sampleIndex = 0, eventCounter = 0, eventIndex = 0;
            bool eventsProcessed = false;

            // for (int i = 0; i < channelCount; i++) {
            //     for (int j = 0; j < drawSurfaceWidth ; j++) {
            //         sample = inSamples[i][j];
            //         if (j % 2 == 0) {
            //             outSamples[i][sampleIndex++] = -1 * 1000;
            //         } else {
            //             outSamples[i][sampleIndex++] = 1 * 100;
            //         }
            //     }
            //     outSampleCount[i] = sampleIndex;
            //     sampleIndex = 0;
            // }

            int from = fromSample;
            int to = fromSample + drawSamplesCount;
            for (int i = 0; i < channelCount; i++) {
                for (int j = from; j < to; j++) {
                    sample = inSamples[i][j];
                    if (!eventsProcessed) {
                        for (int k = 0; k < inEventIndicesCount; k++) {
                            if (j == inEventIndices[k]) {
                                eventCounter++;
                            } else {
                                if (j < inEventIndices[k]) break;
                            }
                        }
                    }

                    if (samplesPerPixel == 1 && samplesPerPixelRest == 0) {
                        if (eventCounter > 0) {
                            for (int k = 0; k < eventCounter; k++) {
                                outEventIndices[eventIndex++] = static_cast<float>(sampleIndex);
                            }
                        }
                        outSamples[i][sampleIndex++] = sample;

                        eventCounter = 0;
                    } else {
                        if (sample > max) max = sample;
                        if (sample < min) min = sample;
                        if (envelopeCounter == samplesPerEnvelope) {
                            if (eventCounter > 0) {
                                for (int k = 0; k < eventCounter; k++) {
                                    outEventIndices[eventIndex++] = static_cast<float>(sampleIndex);
                                }
                            }
                            outSamples[i][sampleIndex++] = max;
                            outSamples[i][sampleIndex++] = min;

                            envelopeCounter = 0;
                            min = SHRT_MAX;
                            max = SHRT_MIN;
                            eventCounter = 0;
                        }

                        envelopeCounter++;
                    }
                }

                outSampleCount[i] = sampleIndex;
                if (!eventsProcessed) outEventIndicesCount = eventIndex;
                // platform_log("\n samplesPerPixel : \n");
                // platform_log(std::to_string(samplesPerPixel).c_str());
                // platform_log("\n");
                // platform_log("\n samplesPerPixelRest : \n");
                // platform_log(std::to_string(samplesPerPixelRest).c_str());
                // platform_log("\n");
                // platform_log("\n drawSamplesCount : \n");
                // platform_log(std::to_string(drawSamplesCount).c_str());
                // platform_log("\n");
                // platform_log("\n drawSurfaceWidth : \n");
                // platform_log(std::to_string(drawSurfaceWidth).c_str());
                // platform_log("\n");
                // platform_log("\n sampleIndex : \n");
                // platform_log(std::to_string(sampleIndex).c_str());
                // platform_log("\n");
    
    
                eventsProcessed = true;
                sampleIndex = 0;
                eventIndex = 0;
                envelopeCounter = 0;
                min = SHRT_MAX;
                max = SHRT_MIN;
            }
        }

        float DrawingUtils::red(float gray) {
            return base(gray - .5f);
        }

        float DrawingUtils::green(float gray) {
            return base(gray);
        }

        float DrawingUtils::blue(float gray) {
            return base(gray + .5f);
        }

        float DrawingUtils::base(float val) {
            if (val <= -.75f) {
                return 0.0f;
            } else if (val <= -.25f) {
                return interpolate(val, 0.0f, -.75f, 1.0f, -.25f);
            } else if (val <= .25f) {
                return 1.0f;
            } else if (val <= .75f) {
                return interpolate(val, 1.0f, .25f, 0.0f, .75f);
            } else {
                return 0.0f;
            }
        }

        float DrawingUtils::interpolate(float val, float y0, float x0, float y1, float x1) {
            return (val - x0) * (y1 - y0) / (x1 - x0) + y0;
        }
    }
}