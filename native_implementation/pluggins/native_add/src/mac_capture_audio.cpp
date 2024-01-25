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
#include "timing_debug.h"

extern "C"
{
#include <CoreAudio/CoreAudio.h>
}
#include <cstdio>
#include <unistd.h> // for sleep function in C++
#include <string>

// Include your other C++ headers
#include "mac_audio_sink.cpp" // Replace with your actual header file

MacAudioSink macAudioSink;
TimingDebug timing_Debug;

// Define a callback function to handle input audio data
OSStatus audioInputCallback(
    AudioObjectID inDevice,
    const AudioTimeStamp *inNow,
    const AudioBufferList *inInputData,
    const AudioTimeStamp *inInputTime,
    AudioBufferList *outOutputData,
    const AudioTimeStamp *inOutputTime,
    void *inClientData)
{
    // if (inNow) {
    //     printf("AudioTimeStamp (inNow): mSampleTime: %f samples, mHostTime: %llu host ticks\n", inNow->mSampleTime, inNow->mHostTime);
    // }

    // if (inInputData) {
    //     printf("AudioBufferList (inInputData): Number of AudioBuffers: %u, Data Byte Size of first buffer: %u bytes\n", inInputData->mNumberBuffers, inInputData->mBuffers[0].mDataByteSize);
    // }

    // if (inInputTime) {
    //     printf("AudioTimeStamp (inInputTime): mSampleTime: %f samples, mHostTime: %llu host ticks\n", inInputTime->mSampleTime, inInputTime->mHostTime);
    // }

    // if (outOutputData) {
    //     printf("AudioBufferList (outOutputData): Number of AudioBuffers: %u\n", outOutputData->mNumberBuffers);
    // }

    // if (inOutputTime) {
    //     printf("AudioTimeStamp (inOutputTime): mSampleTime: %f samples, mHostTime: %llu host ticks\n", inOutputTime->mSampleTime, inOutputTime->mHostTime);
    // }

    // printf("Client Data Pointer: %p\n", inClientData);

    // For simplicity, we'll assume a single float channel and just print out the first sample
    // const Float32 *data = (const Float32 *)inInputData->mBuffers[0].mData;
    UInt32 dataByteSize = inInputData->mBuffers[0].mDataByteSize;

    // printf("Data Byte Size: %u bytes\n", dataByteSize);
    // printf("\n\n\n");

    // Calculate the number of samples in the buffer
    // Assuming that mDataByteSize is the size in bytes of the audio buffer
    // and that each sample is a Float32 (4 bytes)
    UInt32 numSamples = dataByteSize / sizeof(Float32);

    // for(UInt32 i = 0; i< numSamples;i++){
    //     printf("%d : %f\n", i, data[i]);
    // }

    // Create a new float* in heap
    Float32 *myArray = (Float32 *)malloc(sizeof(Float32) * numSamples);
    memcpy((void *)myArray, (void *)inInputData->mBuffers[0].mData, dataByteSize);

    // Call MyAudioSink's method to handle the data
    macAudioSink.CopyData(myArray, numSamples, nullptr);

    // Delete myArray
    free(myArray);

    return noErr;
}

const char *AudioFormatIDToString(AudioFormatID format)
{
    switch (format)
    {
    case kAudioFormatLinearPCM:
        return "lpcm";
    case kAudioFormatAC3:
        return "ac-3";
    // Add cases for each format
    default:
        return "Unknown Format";
    }
}

std::string AudioFormatFlagsToString(AudioFormatFlags flags)
{
    std::string result;
    if (flags & kAudioFormatFlagIsFloat)
        result += "Float, ";
    if (flags & kAudioFormatFlagIsBigEndian)
        result += "BigEndian, ";
    if (flags & kAudioFormatFlagIsSignedInteger)
        result += "SignedInteger, ";
    if (flags & kAudioFormatFlagIsPacked)
        result += "Packed, ";
    if (flags & kAudioFormatFlagIsAlignedHigh)
        result += "AlignedHigh, ";
    if (flags & kAudioFormatFlagIsNonInterleaved)
        result += "NonInterleaved, ";
    if (flags & kAudioFormatFlagIsNonMixable)
        result += "NonMixable, ";
    if (flags == kAudioFormatFlagsAreAllClear)
        return "All Flags Clear";
    if (result.empty())
        return "No Flags Set";
    return result.substr(0, result.size() - 2); // Remove trailing comma and space
}

#ifdef __cplusplus
extern "C"
{
#endif

    AudioDeviceID deviceID = kAudioObjectUnknown;
    // Set the input data source to our callback function
    AudioDeviceIOProcID procID = NULL;

    FUNCTION_ATTRIBUTE double newlistenMic()
    {

        UInt32 dataSize = sizeof(deviceID);
        AudioObjectPropertyAddress propertyAddress = {
            kAudioHardwarePropertyDefaultInputDevice,
            kAudioObjectPropertyScopeGlobal,
            kAudioObjectPropertyElementMaster};

        // Get the default input device
        OSStatus status = AudioObjectGetPropertyData(kAudioObjectSystemObject,
                                                     &propertyAddress,
                                                     0,
                                                     NULL,
                                                     &dataSize,
                                                     &deviceID);
        if (status != noErr)
        {
            fprintf(stderr, "Error getting default audio device\n");
            return -1;
        }

        // Get the device name
        CFStringRef deviceName = NULL;
        propertyAddress.mSelector = kAudioObjectPropertyName;
        dataSize = sizeof(deviceName);
        status = AudioObjectGetPropertyData(deviceID,
                                            &propertyAddress,
                                            0, NULL,
                                            &dataSize,
                                            &deviceName);
        if (status != noErr)
        {
            fprintf(stderr, "Error getting device name\n");
            return -1;
        }

        // Convert CFStringRef to C string if needed
        char name[128];
        if (CFStringGetCString(deviceName, name, sizeof(name), kCFStringEncodingUTF8))
        {
            printf("Device Name: %s\n", name);
        }
        else
        {
            fprintf(stderr, "Error converting device name to C string\n");
        }

        // Release the CFStringRef
        if (deviceName)
        {
            CFRelease(deviceName);
        }

        AudioStreamBasicDescription streamFormat;

        // Get the stream format of the default input device
        propertyAddress.mSelector = kAudioDevicePropertyStreamFormat;
        propertyAddress.mScope = kAudioDevicePropertyScopeInput;
        dataSize = sizeof(streamFormat);
        status = AudioObjectGetPropertyData(deviceID,
                                            &propertyAddress,
                                            0,
                                            NULL,
                                            &dataSize,
                                            &streamFormat);

        if (status != noErr)
        {
            fprintf(stderr, "Error getting audio stream format\n");
            return -1;
        }

        // Print the sample rate and bit depth
        printf("Sample Rate: %f Hz\n", streamFormat.mSampleRate);
        printf("Format ID: %u\n", streamFormat.mFormatID);
        printf("Audio Format: %s\n", AudioFormatIDToString(streamFormat.mFormatID));
        printf("Format Flags: %u\n", streamFormat.mFormatFlags);
        printf("Audio Format Flags: %s\n", AudioFormatFlagsToString(streamFormat.mFormatFlags).c_str());
        printf("Bytes Per Packet: %u\n", streamFormat.mBytesPerPacket);
        printf("Frames Per Packet: %u\n", streamFormat.mFramesPerPacket);
        printf("Bytes Per Frame: %u\n", streamFormat.mBytesPerFrame);
        printf("Channels Per Frame: %u\n", streamFormat.mChannelsPerFrame);
        printf("Bits Per Channel: %u bits\n", streamFormat.mBitsPerChannel);

        status = AudioDeviceCreateIOProcID(deviceID,
                                           audioInputCallback,
                                           NULL,
                                           &procID);
        if (status != noErr)
        {
            fprintf(stderr, "Error setting IOProc: OSStatus code = %d\n", status);
            return -1;
        }

        // Start the audio hardware
        status = AudioDeviceStart(deviceID, procID);
        if (status != noErr)
        {
            fprintf(stderr, "Error starting audio device\n");
            return -1;
        }

        return 101;
    }

    FUNCTION_ATTRIBUTE double isCheckData(int16_t *micOutputData)
    {
        double result = macAudioSink.DisplayData(micOutputData);
        // std::cout <<  "result in cpp : " << result << std::endl;
        if (result >= 0.0)
        {
            timing_Debug.noteTime();
            return 1.0;
        }
        return 0.0;
    }

    FUNCTION_ATTRIBUTE double stopMicrophone()
    {
        // Stop the audio hardware
        OSStatus status = AudioDeviceStop(deviceID, procID);
        if (status != noErr)
        {
            fprintf(stderr, "Error stopping audio device\n");
            return -1;
        }

        // Destroy the IO proc after stopping
        status = AudioDeviceDestroyIOProcID(deviceID, procID);
        if (status != noErr)
        {
            fprintf(stderr, "Error destroying IOProc\n");
            return -1;
        }

        return 1;
    }

    EXTERNC FUNCTION_ATTRIBUTE int getAvg()
    {

        return timing_Debug.getAvg();
    }
    EXTERNC FUNCTION_ATTRIBUTE int getMin()
    {

        return timing_Debug.getMinTime();
    }
    EXTERNC FUNCTION_ATTRIBUTE int getMax()
    {

        return timing_Debug.getMaxTime();
    }

#ifdef __cplusplus
}

#endif