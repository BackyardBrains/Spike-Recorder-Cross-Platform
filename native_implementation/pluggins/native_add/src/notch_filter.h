//
// Created by Stanislav Mircic  <stanislav at backyardbrains.com>
//
#ifndef SPIKE_RECORDER_ANDROID_NotchFilter
#define SPIKE_RECORDER_ANDROID_NotchFilter
// https://www.howtogeek.com/297721/how-to-create-and-use-symbolic-links-aka-symlinks-on-a-mac/
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

class NotchFilter : public FilterBase
{
public:
    // NotchFilter(){};
    NotchFilter() = default;
    void calculateCoefficients();
    void setCenterFrequency(double newCenterFrequency);
    void setQ(double newQ);
    double centerFrequency;
    double Q;

protected:
private:
};

EXTERNC FUNCTION_ATTRIBUTE double setNotch(int16_t _isNotch50, int16_t _isNotch60);
EXTERNC FUNCTION_ATTRIBUTE double initNotchPassFilter(int16_t _isNotch50, int16_t channelCount, double sampleRate, double cutOff, double q);
EXTERNC FUNCTION_ATTRIBUTE double applyNotchPassFilter(int16_t _isNotch50, int16_t channelIdx, int16_t *data, int32_t sampleCount);

#endif
