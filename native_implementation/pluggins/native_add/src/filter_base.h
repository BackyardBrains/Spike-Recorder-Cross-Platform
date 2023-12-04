//
// Created by Stanislav Mircic  <stanislav at backyardbrains.com>
//

#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

#ifndef SPIKE_RECORDER_ANDROID_FILTERBASE
#define SPIKE_RECORDER_ANDROID_FILTERBASE

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

class FilterBase
{
public:
    int val;
    FilterBase() = default;

    double getSamplingRate();

    void initWithSamplingRate(double sr);

    void setCoefficients();
    void filter(int16_t *data, int32_t numFrames, bool flush);

    void filterContiguousData(double *data, int32_t numFrames);
    void intermediateVariables(double Fc, double Q);

    double one;
    double samplingRate;
    double gInputKeepBuffer[2];
    double gOutputKeepBuffer[2];
    double omega, omegaS, omegaC, alpha;
    double coefficients[5];
    double a0, a1, a2, b0, b1, b2;

protected:
private:
};

#endif