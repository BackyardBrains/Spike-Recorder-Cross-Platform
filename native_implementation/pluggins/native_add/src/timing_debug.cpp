
#include "timing_debug.h"

long long TimingDebug::fetchTime()
{
    auto now = std::chrono::system_clock::now();
    auto duration = now.time_since_epoch();
    return std::chrono::duration_cast<std::chrono::milliseconds>(duration).count();
}

void TimingDebug::noteTime()
{

    long long time = fetchTime();
    //
    //
    long long elapsedTime = time - previousTimeStamp; // Calculate elapsed time

    if (previousTimeStamp != 0)
    {
        totalElapsedTime += elapsedTime;
    }
    previousTimeStamp = time;
    // std::cout << "elapsed time: " << elapsedTime << std::endl;
    // std::cout << "fetch time: " << time << std::endl;
    // std::cout << "Elapsed Time: " << totalElapsedTime << std::endl;
    // std::cout << "previous Time: " << previousTimeStamp << std::endl;
    // std::cout << "maxTime: " << getMaxTime() << std::endl;
    // std::cout << "minTime: " << getMinTime() << std::endl;

    setMinTime(elapsedTime);
    setMaxTime(elapsedTime);
    setAvgTime(elapsedTime);
}

void TimingDebug::setMinTime(long long latestTime)
{
    if (latestTime < minTime)
    {
        minTime = latestTime;
    }
}

void TimingDebug::setMaxTime(long long latestTime)
{
    if (latestTime > maxTime)
    {
        maxTime = latestTime;
    }
}

void TimingDebug::setAvgTime(long long latestTime)
{
    count++;
    averageTime = totalElapsedTime / count;
    // std::cout << "Average Time: " << averageTime << std::endl;
}

// void TimingDebug::reset()
// {
//     maxTime = 0;
//     minTime = 0;
//     previousTimeStamp = 0;
// }

// EXTERNC FUNCTION_ATTRIBUTE int getTimeMic()
// {
//     auto current_time = std::chrono::steady_clock::now();
//     auto elapsed_time = std::chrono::duration_cast<std::chrono::milliseconds>(current_time - pMySink.start_time);
//     int seconds = static_cast<int>(elapsed_time.count());
//     // // Now you can use 'seconds' as an integer
//     // // std::cout << "result in seconds: " << seconds << std::endl;
//     timingDebug.noteTime(seconds);
//     std::cout << "Elapsed Time: " << timingDebug.getElapsedTime() << std::endl;
//     // std::cout << "Max Time: " << timing.getMaxTime() << std::endl;
//     // std::cout << "Min Time: " << timing.getMinTime() << std::endl;

//     return timingDebug.getElapsedTime();
// }
