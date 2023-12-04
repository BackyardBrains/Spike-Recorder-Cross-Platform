//
// Created by Stanislav Mircic  <stanislav at backyardbrains.com>
//
#ifndef SPIKE_RECORDER_ANDROID_HIGHPASSFILTER
#define SPIKE_RECORDER_ANDROID_HIGHPASSFILTER

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

class HighPassFilter : public FilterBase
{
public:
    HighPassFilter() = default;
    void calculateCoefficients();
    void setCornerFrequency(double newCornerFrequency);
    void setQ(double newQ);
    double cornerFrequency;
    double Q;

protected:
private:
};

// EXTERNC FUNCTION_ATTRIBUTE double createHighPassFilter(short channelCount, double sampleRate, double highCutOff, double q);

EXTERNC FUNCTION_ATTRIBUTE double initHighPassFilter(int channelCount, double sampleRate, double highCutOff, double q);

EXTERNC FUNCTION_ATTRIBUTE double applyHighPassFilter(int16_t channelIdx, int16_t *data, int32_t sampleCount);

#endif