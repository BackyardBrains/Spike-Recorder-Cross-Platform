#ifndef MY_AUDIO_SINK
#define MY_AUDIO_SINK

class MacAudioSink
{
public:
    MacAudioSink()
    {
        sinkData = new int16_t[bufferLength]; // Allocate memory for 16384 16-bit integers
        writeIndex = 0;
        readIndex = 0;
        dataCount = 0;
    }

    ~MacAudioSink()
    {
        delete[] sinkData;
    }

    int CopyData(Float32 *pData, uint32_t numFramesAvailable, bool *bDone)
    {
        isCopyingData = true;
        // Cast pData to a float pointer for easier access to the samples
        // Float32 *pFloatData = (Float32 *)pData;

        for (uint32_t i = 0; i < numFramesAvailable; i++)
        {
            // Directly access the ith sample
            Float32 sample = pData[i];

            // Convert the float sample to a 16-bit integer
            int16_t intSample = static_cast<int16_t>(sample * 32767.0f);

            sinkData[writeIndex] = intSample;
            writeIndex = (writeIndex + 1) % (bufferLength);
            dataCount++;
        }
        isCopyingData = false;
        return 1; // Return a status code (1 for success in this case)
    }

    double DisplayData(int16_t *outData)
    {
        if(isCopyingData) return -5;
        if (dataCount >= packetReadSize && outData)
        {
            if (readIndex + packetReadSize >= bufferLength)
            {
                int samplesTillEnd = (bufferLength - 1) - readIndex;
                int samplesAtBeginning = packetReadSize - samplesTillEnd;

                // Copy the data from readIndex + 1 to start of outData
                if (samplesTillEnd != 0)
                {
                    memcpy(outData, sinkData + readIndex + 1, samplesTillEnd * sizeof(int16_t));
                }

                // Copy the data from start of sinkData to the remaining outData
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
    const uint32_t bufferLength = 384000 * 2;

    size_t data_chunk_pos;
    size_t file_length;

    int16_t *sinkData;
    uint32_t writeIndex;
    uint32_t readIndex;
    uint32_t dataCount; // To track how much data we have in the buffer

    // change in dart also
    // unit - samples of int16
    // i.e. bytes 4096
    int packetReadSize = 2048;

    bool isCopyingData = false;
};

#endif