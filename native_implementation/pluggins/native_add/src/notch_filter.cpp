#include "notch_filter.h"

//
NotchFilter NotchFilters50[6];
NotchFilter NotchFilters60[6];
int isNotch50 = 0;
int isNotch60 = 0;
void NotchFilter::calculateCoefficients()
{
    if ((centerFrequency != 0.0f) && (Q != 0.0f))
    {
        intermediateVariables(centerFrequency, Q);

        a0 = (1 + alpha);
        b0 = 1 / a0;
        b1 = (-2 * omegaC) / a0;
        b2 = 1 / a0;
        a1 = (-2 * omegaC) / a0;
        a2 = (1 - alpha) / a0;
        setCoefficients();
    }
}

void NotchFilter::setCenterFrequency(double newCenterFrequency)
{
    centerFrequency = newCenterFrequency;
    calculateCoefficients();
}

void NotchFilter::setQ(double newQ)
{
    Q = newQ;
    calculateCoefficients();
}
double centerFrequency = 0;
double Q = 0;

EXTERNC FUNCTION_ATTRIBUTE double setNotch(int16_t _isNotch50, int16_t _isNotch60)
{
    isNotch50 = _isNotch50;
    isNotch60 = _isNotch60;
    return 1;
}

// EXTERNC FUNCTION_ATTRIBUTE double createNotchPassFilter(int16_t _isNotch50, int16_t channelCount, double sampleRate, double cutOff, double q)
// {
//     // NotchFilters = new NotchFilter[channelCount];
//     // int sum = 0;
//     for (int i = 0; i < channelCount; i++)
//     {
//         if (_isNotch50 == 1)
//         {
//             NotchFilters50[i] = NotchFilter();
//             // NotchFilter NotchFilter = NotchFilters[i];
//             NotchFilters50[i].initWithSamplingRate(sampleRate);
//             if (cutOff > sampleRate / 2.0f)
//                 cutOff = sampleRate / 2.0f;
//             NotchFilters50[i].setCenterFrequency(cutOff);
//             NotchFilters50[i].setQ(q);
//         }
//         else
//         {
//             NotchFilters60[i] = NotchFilter();
//             // NotchFilter NotchFilter = NotchFilters[i];
//             NotchFilters60[i].initWithSamplingRate(sampleRate);
//             if (cutOff > sampleRate / 2.0f)
//                 cutOff = sampleRate / 2.0f;
//             NotchFilters60[i].setCenterFrequency(cutOff);
//             NotchFilters60[i].setQ(q);
//         }
//         // NotchFilter NotchFilter = NotchFilter();
//     }
//     return 1;
// }

EXTERNC FUNCTION_ATTRIBUTE double initNotchPassFilter(int16_t _isNotch50, int16_t channelCount, double sampleRate, double cutOff, double q)
{
    for (int32_t i = 0; i < channelCount; i++)
    {

        // NotchFilter NotchFilter = NotchFilters[i];
        if (_isNotch50 == 1)
        {
            // std::cout << "init notchFilter : " << std::endl;

            NotchFilters50[i].initWithSamplingRate(sampleRate);
            if (cutOff > sampleRate / 2.0f)
                cutOff = sampleRate / 2.0f;
            NotchFilters50[i].setCenterFrequency(cutOff);
            NotchFilters50[i].setQ(q);
        }
        else
        {
            NotchFilters60[i].initWithSamplingRate(sampleRate);
            if (cutOff > sampleRate / 2.0f)
                cutOff = sampleRate / 2.0f;
            NotchFilters60[i].setCenterFrequency(cutOff);
            NotchFilters60[i].setQ(q);
        }
    }
    return NotchFilters50[0].omega;
}

EXTERNC FUNCTION_ATTRIBUTE double applyNotchPassFilter(int16_t _isNotch50, int16_t channelIdx, int16_t *data, int32_t sampleCount)
{
    if (_isNotch50 == 1)
    {
        if (NotchFilters50[channelIdx].omega != 0)
        {
            NotchFilters50[channelIdx].filter(data, sampleCount, false);
            return 1;
        }
        else
        {
            // return -1;
            return NotchFilters50[channelIdx].omega;
        }
    }
    else
    {
        if (NotchFilters60[channelIdx].omega != 0)
        {
            NotchFilters60[channelIdx].filter(data, sampleCount, false);
            return 1;
        }
        else
        {
            // return -1;
            return NotchFilters60[channelIdx].omega;
        }
    }
}
