#include <emscripten/bind.h>
#include <emscripten/val.h>
#include <emscripten.h>
using namespace emscripten;

//
// Created by Stanislav Mircic  <stanislav at backyardbrains.com>
//
#ifndef SPIKE_RECORDER_ANDROID_LOWPASSFILTER
#define SPIKE_RECORDER_ANDROID_LOWPASSFILTER

#include "filter_base.cpp"

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <math.h>
#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <stdint.h>

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

class LowPassFilter : public FilterBase
{
public:
    // LowPassFilter(){};
    LowPassFilter() = default;
    void calculateCoefficients()
    {
        if ((cornerFrequency != 0.0f) && (Q != 0.0f))
        {
            intermediateVariables(cornerFrequency, Q);

            a0 = 1 + alpha;
            b0 = ((1 - omegaC) / 2) / a0;
            b1 = ((1 - omegaC)) / a0;
            b2 = ((1 - omegaC) / 2) / a0;
            a1 = (-2 * omegaC) / a0;
            a2 = (1 - alpha) / a0;

            setCoefficients();
        }
    }

    void setCornerFrequency(double newCornerFrequency)
    {
        cornerFrequency = newCornerFrequency;
        calculateCoefficients();
    }

    void setQ(double newQ)
    {
        Q = newQ;
        calculateCoefficients();
    }

protected:
    double cornerFrequency;
    double Q;

private:
};

// LowPassFilter* lowPassFilters;
LowPassFilter lowPassFilters[6];
EXTERNC FUNCTION_ATTRIBUTE double createLowPassFilter(short channelCount, double sampleRate, double lowCutOff, double q)
{
    // lowPassFilters = new LowPassFilter[channelCount];
    for (int32_t i = 0; i < channelCount; i++)
    {
        // LowPassFilter lowPassFilter = LowPassFilter();
        lowPassFilters[i].initWithSamplingRate(sampleRate);
        if (lowCutOff > sampleRate / 2.0f)
            lowCutOff = sampleRate / 2.0f;
        lowPassFilters[i].setCornerFrequency(lowCutOff);
        lowPassFilters[i].setQ(q);
        // lowPassFilters[i] = lowPassFilter;
    }
    return 1;
}

EXTERNC FUNCTION_ATTRIBUTE double initLowPassFilter(short channelCount, double sampleRate, double lowCutOff, double q)
{
    for (int32_t i = 0; i < channelCount; i++)
    {
        // HighPassFilter highPassFilter = highPassFilters[i];
        lowPassFilters[i].initWithSamplingRate(sampleRate);
        if (lowCutOff > sampleRate / 2.0f)
            lowCutOff = sampleRate / 2.0f;
        lowPassFilters[i].setCornerFrequency(lowCutOff);
        lowPassFilters[i].setQ(q);
    }
    return 100;
}

EXTERNC FUNCTION_ATTRIBUTE double applyLowPassFilter(int16_t channelIdx, int16_t *data, int32_t sampleCount)
{
    if (lowPassFilters[channelIdx].omega != 0)
    {
        lowPassFilters[channelIdx].filter(data, sampleCount, false);
        uintptr_t addr = reinterpret_cast<uintptr_t>(&data[0]);
        return (double)addr;
    }
    return -100;
}

#endif

// EMSCRIPTEN_BINDINGS(my_module)
// {
//     class_<LowPassFilter>("LowPassFilter")
//         .constructor()
//         .function("calculateCoefficients", &LowPassFilter::calculateCoefficients)
//         .function("setCornerFrequency", &LowPassFilter::setCornerFrequency)
//         .function("setQ", &LowPassFilter::setQ);
//     function("createLowPassFilter", &createLowPassFilter);
//     function("initLowPassFilter", &initLowPassFilter);
//     function("applyLowPassFilter", &applyLowPassFilter);
// }