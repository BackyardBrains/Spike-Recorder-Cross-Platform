#include "envelope.h"

SampleBuffer sampleBuffer;

EXTERNC FUNCTION_ATTRIBUTE double addDataToSampleBuffer(int16_t *src, int len)
{
    // int64_t offset, int64_t len  required parameter
    sampleBuffer.addData(src, len);
    return 1.0;
}

EXTERNC FUNCTION_ATTRIBUTE double getDataFromSampleBuffer(int offset, int len, int skip, int16_t *src)
{
    std::cout << "get data is calling" << std::endl;
    // int64_t offset, int64_t len, int skip   *required  parameter
    std::vector<std::pair<int16_t, int16_t>> dataAfterEnvelop = sampleBuffer.getDataEnvelope(offset, len, skip);

    size_t dataSize = dataAfterEnvelop.size() * 2; // Two int16_t elements per pair

    // Allocate memory for the int16_t array
    src = new int16_t[dataSize];

    // Copy data from vector to array
    for (size_t i = 0; i < dataAfterEnvelop.size(); ++i)
    {
        src[2 * i] = dataAfterEnvelop[i].first;
        src[2 * i + 1] = dataAfterEnvelop[i].second;
    }

    return 1.0;
}