//
// Created by Stanislav Mircic  <stanislav at backyardbrains.com>
//

#ifndef SPIKE_RECORDER_ANDROID_LOWPASSFILTER
#define SPIKE_RECORDER_ANDROID_LOWPASSFILTER

#include "filter_base.h"

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
    LowPassFilter() = default;
    double myCreateLowPassFilter(int16_t channelCount, double sampleRate, double cutOff, double q);
    void calculateCoefficients();
    void setCornerFrequency(double newCornerFrequency);
    void setQ(double newQ);
    double cornerFrequency = 0;
    double Q = 0;

protected:
private:
};



// EXTERNC FUNCTION_ATTRIBUTE double createLowPassFilter(int16_t channelCount, double sampleRate, double cutOff, double q);

EXTERNC FUNCTION_ATTRIBUTE double initLowPassFilter(int channelCount, double sampleRate, double cutOff, double q);

EXTERNC FUNCTION_ATTRIBUTE double applyLowPassFilter(int16_t channelIdx, int16_t *data, int32_t sampleCount);

#endif
