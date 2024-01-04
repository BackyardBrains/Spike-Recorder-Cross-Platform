#ifndef BACKYARDBRAINS_TIMINGBUFFER_H
#define BACKYARDBRAINS_TIMINGBUFFER_H

#include <iostream>
#include <vector>
#include <queue>
#include <windows.h>
#include <audioclient.h>
#include <mmdeviceapi.h>
#include <fstream>
#include <iostream>
#include <cmath>
#include <thread>
#include <algorithm>
#include <cstdint>

#include <chrono>
#include "capture_audio.h"

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

class TimingDebug
{
public:
    long long totalElapsedTime = 0;
    void noteTime();
    // Getter functions
    int getMaxTime() const { return maxTime; }
    int getMinTime() const { return minTime; }
    int getAvg() const
    {
        return averageTime;
    }
    // int getElapsedTime() const { return elapsedTime; } // Getter for elapsed time

private:
    long long maxTime = LLONG_MAX;
    long long minTime = LLONG_MIN;
    long long averageTime = 0;
    long long previousTimeStamp = 0;
    long long count = 0;

    long long fetchTime();
    void setMinTime(long long latestTime); // Updated: Added parameter to setMinTime
    void setMaxTime(long long latestTime);
    void setAvgTime(long long latestTime);
};

// EXTERNC FUNCTION_ATTRIBUTE int getTimeMic();

// EXTERNC FUNCTION_ATTRIBUTE int getMin();

// EXTERNC FUNCTION_ATTRIBUTE int getMax();
#endif
