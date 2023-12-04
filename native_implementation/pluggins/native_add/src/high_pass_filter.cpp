//
// Created by Stanislav Mircic  <stanislav at backyardbrains.com>
//

#include "high_pass_filter.h"

HighPassFilter highPassFilters[6];

void HighPassFilter::calculateCoefficients()
{
    if ((cornerFrequency != 0.0f) && (Q != 0.0f))
    {
        intermediateVariables(cornerFrequency, Q);

        a0 = 1 + alpha;
        b0 = ((1 + omegaC) / 2) / a0;
        b1 = (-1 * (1 + omegaC)) / a0;
        b2 = ((1 + omegaC) / 2) / a0;
        a1 = (-2 * omegaC) / a0;
        a2 = (1 - alpha) / a0;

        setCoefficients();
    }
}

void HighPassFilter::setCornerFrequency(double newCornerFrequency)
{
    cornerFrequency = newCornerFrequency;
    calculateCoefficients();
}

void HighPassFilter::setQ(double newQ)
{
    Q = newQ;
    calculateCoefficients();
}

EXTERNC FUNCTION_ATTRIBUTE double initHighPassFilter(int channelCount, double sampleRate, double highCutOff, double q)
{
    for (int32_t i = 0; i < channelCount; i++)
    {
        // HighPassFilter highPassFilter = highPassFilters[i];
        highPassFilters[i].initWithSamplingRate(sampleRate);
        if (highCutOff > sampleRate / 2.0f)
            highCutOff = sampleRate / 2.0f;
        highPassFilters[i].setCornerFrequency(highCutOff);
        highPassFilters[i].setQ(q);
    }
    return 1;
}

EXTERNC FUNCTION_ATTRIBUTE double applyHighPassFilter(int16_t channelIdx, int16_t *data, int32_t sampleCount)
{
    highPassFilters[channelIdx].filter(data, sampleCount, false);
    return 1;
}
// EXTERNC FUNCTION_ATTRIBUTE double listenMic();
// EXTERNC FUNCTION_ATTRIBUTE double listenMic()
// {
//     double q = 5.0;
//     double r = 5.0;
//     double w;
//     w = q + r;
//     return w;
// }
