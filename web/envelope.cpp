#include "envelope.h"

SampleBuffer sampleBuffer;

EXTERNC FUNCTION_ATTRIBUTE double addDataToSampleBuffer(int16_t *src, int len)
{
    // int64_t offset, int64_t len  required parameter
    sampleBuffer.addData(src, len);
    return 1.0;
}

static int64_t snapTo(int64_t val, int64_t increments)
{
    if (increments > 1)
    {
        val /= increments;
        val *= increments;
    }
    return val;
}

EXTERNC FUNCTION_ATTRIBUTE double getDataFromSampleBuffer(int offset, int len, int skip, int16_t *src)
{
    // std::cout << "get data is calling" << std::endl;
    // int64_t offset, int64_t len, int skip   *required  parameter
    const int64_t pos2 = offset + len;

    const int64_t pos1 = snapTo(offset, skip);

    // std::cout << "pos1 " << pos1 << std::endl;
    // std::cout << "pos2 " << pos2 << std::endl;
    // std::cout << "skip" << skip << std::endl;

    int64_t newLengthOfData = pos2 - pos1;

    // int sampleSkip = len ~ / 4000;
    // std::cout << " skip sample is " << sampleSkip << std::endl;

    std::vector<std::pair<int16_t, int16_t>>
        dataAfterEnvelop = sampleBuffer.getDataEnvelope(pos1, newLengthOfData, skip);

    // std::cout << "Data after envelop " << std::endl;
    size_t dataSize = dataAfterEnvelop.size() * 2; // Two int16_t elements per pair

    // Allocate memory for the int16_t array
    // src = int16_t[dataSize];

    // Copy data from vector to array
    // std::cout << "dataAfterEnvelop size " << dataAfterEnvelop.size() << std::endl;

    for (size_t i = 0; i < dataAfterEnvelop.size(); ++i)
    {
        size_t startIndex = 2 * i;
        int minValue = src[2 * i] = dataAfterEnvelop[i].first;
        int maxValue = src[(2 * i) + 1] = dataAfterEnvelop[i].second;
        // std::cout << " minValue is " << minValue << std::endl;
        // std::cout << "MaxValue at index " << startIndex + 1 << ": " << maxValue << std::endl;
    }

    return 1.0;
}