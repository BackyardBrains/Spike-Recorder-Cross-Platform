//
// Created by Stanislav Mircic  <stanislav at backyardbrains.com>
//

#include "low_pass_filter.h"

int logIdx = -1;
LowPassFilter lowPassFilters[6];

double LowPassFilter::myCreateLowPassFilter(int16_t channelCount, double sampleRate, double cutOff, double q)
{
    return 1;
}

void LowPassFilter::calculateCoefficients()
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

void LowPassFilter::setCornerFrequency(double newCornerFrequency)
{
    cornerFrequency = newCornerFrequency;
    calculateCoefficients();
}

void LowPassFilter::setQ(double newQ)
{
    Q = newQ;
    calculateCoefficients();
}

EXTERNC FUNCTION_ATTRIBUTE double initLowPassFilter(int channelCount, double sampleRate, double cutOff, double q)
{
    for (int32_t i = 0; i < channelCount; i++)
    {
        // LowPassFilter lowPassFilter = lowPassFilters[i];
        lowPassFilters[i].initWithSamplingRate(sampleRate);
        if (cutOff > sampleRate / 2.0f)
            cutOff = sampleRate / 2.0f;
        lowPassFilters[i].setCornerFrequency(cutOff);
        lowPassFilters[i].setQ(q);
    }
    return lowPassFilters[0].omega;
}

EXTERNC FUNCTION_ATTRIBUTE double applyLowPassFilter(int16_t channelIdx, int16_t *data, int32_t sampleCount)
{
    if (lowPassFilters[channelIdx].omega != 0)
    {
        lowPassFilters[channelIdx].filter(data, sampleCount, false);
        return 1;
    }
    return -1;
}
