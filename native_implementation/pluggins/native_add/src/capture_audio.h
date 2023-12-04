#ifndef CAPTURE_AUDIO_C
#define CAPTURE_AUDIO_C

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

long long getTime()
{
    auto now = std::chrono::high_resolution_clock::now();
    auto duration = now.time_since_epoch();
    return std::chrono::duration_cast<std::chrono::microseconds>(duration).count();
}

class MyAudioSink
{
public:
    MyAudioSink()
    {
        sinkData = new int16_t[bufferLength]; // Allocate memory for 16384 16-bit integers
        writeIndex = 0;
        readIndex = 0;
        dataCount = 0;
    }

    ~MyAudioSink()
    {
        delete[] sinkData;
    }
    bool isAudioCheck;

    HRESULT CopyData(BYTE *pData, UINT32 numFramesAvailable, BOOL *bDone)
    {
        isCopyingData = true;

        uint32_t numSamples = numFramesAvailable * 2;
        uint32_t numBytes = numSamples * 4;
        int16_t *outputData = new int16_t[numSamples];

        for (uint32_t i = 0; i < numBytes; i += 8)
        {
            float sample1 = ((float *)pData)[i / 4];
            float sample2 = ((float *)pData)[(i / 4) + 1];

            // intSample1 matches with right microphone
            int16_t intSample1 = (int16_t)(sample1 * 32767);

            // intSample2 matches with left microphone
            int16_t intSample2 = (int16_t)(sample2 * 32767);

            // To take average of channels
            // sinkData[writeIndex] = static_cast<INT16>((intSample1 + intSample2) / 2);

            // To take one channel at a time
            sinkData[writeIndex] = intSample2;
            writeIndex = (writeIndex + 1) % (bufferLength);
            dataCount++;
        }

        delete[] outputData;
        // for (UINT32 i = 0; i < numFramesAvailable * 4; i += 8)
        // {
        //     float floatValue;

        //     // Copy 4 bytes of pData to a float variable
        //     memcpy(&floatValue, &pData[i], sizeof(float));

        //     // Convert the float value to a 2-byte int16 value
        //     INT16 int16Value = static_cast<INT16>(floatValue * 32767); // Scaling the float value and casting to int16

        //     // Uncomment to print the microphone values
        //     // std::cout << int16Value << std::endl;

        //     // Increment and wrap the write index
        //     sinkData[writeIndex] = int16Value;
        //     writeIndex = (writeIndex + 1) % (bufferLength);
        //     dataCount++;
        // }
        isCopyingData = false;
        return S_OK;
    }

    HRESULT SetFormat(WAVEFORMATEX *pwfx)
    {
        // Update our format variables
        wFormatTag = pwfx->wFormatTag;
        nChannels = pwfx->nChannels;
        nSamplesPerSec = pwfx->nSamplesPerSec;
        nAvgBytesPerSec = pwfx->nAvgBytesPerSec;
        nBlockAlign = pwfx->nBlockAlign;
        wBitsPerSample = pwfx->wBitsPerSample;
        cbSize = pwfx->cbSize;

        return S_OK;
    }

    double DisplayData(int16_t *outData)
    {
        if (isCopyingData)
            return -5;
        /*
        For timing the Loop
        */
        // long long _ts = getTime();
        // std::cout << "DisplayData timestamp in microseconds: " << _ts - lastTs << std::endl;
        // lastTs = _ts;

        if (dataCount >= packetReadSize && outData)
        {
            if (readIndex + packetReadSize >= bufferLength)
            {
                // index 8
                // Packet read size 5
                int samplesTillEnd = (bufferLength - 1) - readIndex;
                int samplesAtBeginning = packetReadSize - samplesTillEnd;

                // Copy the data from readIndex + 1 to start of outData
                if (samplesTillEnd != 0)
                {
                    memcpy(outData, sinkData + readIndex + 1, samplesTillEnd * sizeof(int16_t));
                }

                // Copy the data from start of sinkData to the remaing outData
                if (samplesAtBeginning != 0)
                {
                    memcpy(outData + samplesTillEnd, sinkData, samplesAtBeginning * sizeof(int16_t));
                }

                readIndex = samplesAtBeginning - 1;
            }
            else
            {
                memcpy(outData, sinkData + readIndex + 1, packetReadSize * sizeof(int16_t));
                readIndex += packetReadSize;
            }
            dataCount -= packetReadSize;
            return 1.0;
        }
        else
        {
            if (outData)
            {
                // std::cout << "Not enough data available." << std::endl;
            }
            else
            {
                // std::cout << "Output data pointer is null." << std::endl;
            }
            return -4.0;
        }

        return -1.0;
    }

protected:
private:
    const UINT32 bufferLength = 384000 * 2;

    size_t data_chunk_pos;
    size_t file_length;

    // sample format
    WORD wFormatTag;
    WORD nChannels;
    DWORD nSamplesPerSec;
    DWORD nAvgBytesPerSec;
    WORD nBlockAlign;
    WORD wBitsPerSample;
    WORD cbSize;
    int test;
    int16_t *sinkData;
    UINT32 writeIndex;
    UINT32 readIndex;
    UINT32 dataCount; // To track how much data we have in the buffer

    UINT64 lastTs;

    // change in dart also
    int packetReadSize = 2048;
    bool isCopyingData = false;
};

#endif