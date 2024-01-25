#include "capture_audio.h"
#include "timing_debug.h"

// // Constants for audio configuration
// const int SAMPLE_RATE = 44100;
// const int FRAMES_PER_BUFFER = 256;
// const int CIRCULAR_BUFFER_SIZE = 8192;
#define REFTIMES_PER_SEC 10000000
#define REFTIMES_PER_MILLISEC 10000

#define EXIT_ON_ERROR(hres) \
    if (FAILED(hres))       \
    {                       \
        goto Exit;          \
    }
#define SAFE_RELEASE(punk) \
    if ((punk) != NULL)    \
    {                      \
        (punk)->Release(); \
        (punk) = NULL;     \
    }

// MicCallback globalMicCallback = nullptr;
// FUNCTION_ATTRIBUTE int32_t onMicCallback(int32_t bar, MicCallback callback)
// {
//     std::cout << "Callback run" << std::endl;
//     return callback(nullptr, bar);
// }

TimingDebug timing_Debug;

const CLSID CLSID_MMDeviceEnumerator = __uuidof(MMDeviceEnumerator);
const IID IID_IMMDeviceEnumerator = __uuidof(IMMDeviceEnumerator);
const IID IID_IAudioClient = __uuidof(IAudioClient);
const IID IID_IAudioCaptureClient = __uuidof(IAudioCaptureClient);
HRESULT RecordAudioStream(MyAudioSink *pMySink)

{
    HRESULT hr;
    REFERENCE_TIME hnsRequestedDuration = REFTIMES_PER_SEC;
    REFERENCE_TIME hnsActualDuration;
    UINT32 bufferFrameCount;
    UINT32 numFramesAvailable;
    IMMDeviceEnumerator *pEnumerator = NULL;
    IMMDevice *pDevice = NULL;
    IAudioClient *pAudioClient = NULL;
    IAudioCaptureClient *pCaptureClient = NULL;
    WAVEFORMATEX *pwfx = NULL;
    UINT32 packetLength = 0;
    int totalTime = 0;

    BOOL bDone = FALSE;
    BYTE *pData;
    DWORD flags;

    UINT64 mCount = 0;
    long long oldTs = 0;

    hr = CoCreateInstance(
        CLSID_MMDeviceEnumerator, NULL,
        CLSCTX_ALL, IID_IMMDeviceEnumerator,
        (void **)&pEnumerator);
    EXIT_ON_ERROR(hr)

    hr = pEnumerator->GetDefaultAudioEndpoint(
        eCapture, eConsole, &pDevice);
    EXIT_ON_ERROR(hr)

    hr = pDevice->Activate(
        IID_IAudioClient, CLSCTX_ALL,
        NULL, (void **)&pAudioClient);
    EXIT_ON_ERROR(hr)

    hr = pAudioClient->GetMixFormat(&pwfx);
    hr = pwfx->nSamplesPerSec;
    std::cout << "sampling rate : " << hr << std::endl;

    hr = pwfx->cbSize;
    std::cout << "cb Size : " << hr << std::endl;

    hr = pwfx->nAvgBytesPerSec;
    std::cout << "Average byte per second : " << hr << std::endl;

    hr = pwfx->nChannels;
    std::cout << "no.of channel : " << hr << std::endl;

    hr = pwfx->wBitsPerSample;
    std::cout << "bits per Sample : " << hr << std::endl;

    hr = pwfx->nBlockAlign;
    std::cout << "n block Align : " << hr << std::endl;

    hr = pwfx->wFormatTag;
    std::cout << "format tag : " << hr << std::endl;

    switch (pwfx->wFormatTag)
    {
    case WAVE_FORMAT_PCM:
        std::cout << "WAVE_FORMAT_PCM" << std::endl;
        break;

    case WAVE_FORMAT_IEEE_FLOAT:
        std::cout << "WAVE_FORMAT_IEEE_FLOAT" << std::endl;
        break;

    case WAVE_FORMAT_EXTENSIBLE:
        std::cout << "WAVE_FORMAT_EXTENSIBLE" << std::endl;

        WAVEFORMATEXTENSIBLE *pWaveFormatExtensible = reinterpret_cast<WAVEFORMATEXTENSIBLE *>(pwfx);

        if (pWaveFormatExtensible->SubFormat == KSDATAFORMAT_SUBTYPE_PCM)
        {
            std::cout << "KSDATAFORMAT_SUBTYPE_PCM" << std::endl;
        }
        else if (pWaveFormatExtensible->SubFormat == KSDATAFORMAT_SUBTYPE_IEEE_FLOAT)
        {
            std::cout << "KSDATAFORMAT_SUBTYPE_IEEE_FLOAT" << std::endl;
        }
        break;
    }
    EXIT_ON_ERROR(hr)

    hr = pAudioClient->Initialize(
        AUDCLNT_SHAREMODE_SHARED,
        0,
        hnsRequestedDuration,
        0,
        pwfx,
        NULL);
    EXIT_ON_ERROR(hr)

    // Get the size of the allocated buffer.
    hr = pAudioClient->GetBufferSize(&bufferFrameCount);
    EXIT_ON_ERROR(hr)

    hr = pAudioClient->GetService(
        IID_IAudioCaptureClient,
        (void **)&pCaptureClient);
    EXIT_ON_ERROR(hr)

    // Notify the audio sink which format to use.
    hr = pMySink->SetFormat(pwfx);
    EXIT_ON_ERROR(hr)

    // Calculate the actual duration of the allocated buffer.
    hnsActualDuration = (double)REFTIMES_PER_SEC *
                        bufferFrameCount / pwfx->nSamplesPerSec;
    std::cout << "time taken" << hnsActualDuration << std::endl;

    hr = pAudioClient->Start(); // Start recording.
    EXIT_ON_ERROR(hr)

    // Each loop fills about half of the shared buffer.
    while (bDone == FALSE)
    {
        auto start = std::chrono::high_resolution_clock::now();
        // auto start = std::chrono::duration_cast<std::chrono::microseconds>(end - start);

        // std::cout << "start :" < < < < std::endl;
        // Sleep for half the buffer duration.
        // Sleep(hnsActualDuration / REFTIMES_PER_MILLISEC / 2);

        hr = pCaptureClient->GetNextPacketSize(&packetLength);
        auto end = std::chrono::high_resolution_clock::now();
        auto duration = std::chrono::duration_cast<std::chrono::microseconds>(end - start);

        // totalTime+ =

        // if()
        // std::cout << "Time taken by GetNextPacketSize: " << duration.count() << " microSecond" << std::endl;
        // std::cout << "packet length :" << packetLength << std::endl;
        EXIT_ON_ERROR(hr)

        while (packetLength != 0)
        {
            // Get the available data in the shared buffer.
            hr = pCaptureClient->GetBuffer(
                &pData,
                &numFramesAvailable,
                &flags, NULL, NULL);
            EXIT_ON_ERROR(hr)

            if (flags & AUDCLNT_BUFFERFLAGS_SILENT)
            {
                pData = NULL; // Tell CopyData to write silence.
            }

            // Copy the available capture data to the audio sink.
            hr = pMySink->CopyData(
                pData, numFramesAvailable, &bDone);

            /*
            For timing the loop
            */
            // long long _ts = getTime();
            // std::cout << "Current timestamp in microseconds: " << _ts - oldTs << std::endl;
            // oldTs = _ts;

            EXIT_ON_ERROR(hr)

            hr = pCaptureClient->ReleaseBuffer(numFramesAvailable);
            EXIT_ON_ERROR(hr)

            hr = pCaptureClient->GetNextPacketSize(&packetLength);
            EXIT_ON_ERROR(hr)
        }
    }

    hr = pAudioClient->Stop(); // Stop recording.
    EXIT_ON_ERROR(hr)

Exit:
    CoTaskMemFree(pwfx);
    SAFE_RELEASE(pEnumerator)
    SAFE_RELEASE(pDevice)
    SAFE_RELEASE(pAudioClient)
    SAFE_RELEASE(pCaptureClient)

    return hr;
}

// HRESULT RecordAudioStream(MyAudioSink *pMySink);

HRESULT RecordAudioStream(MyAudioSink *pMySink);

#ifdef __cplusplus
extern "C"
{
#endif
    MyAudioSink pMySink;

    void RecordInThread()
    {
        HRESULT hr;
        hr = RecordAudioStream(&pMySink);
        std::cout << "done" << std::endl;
    }

    FUNCTION_ATTRIBUTE double newlistenMic()
    {
        std::thread myThread(RecordInThread);
        myThread.detach(); // Wait for the thread to finish
        return 101;
    }

    FUNCTION_ATTRIBUTE double isCheckData(int16_t *micOutputData)
    {

        double result = pMySink.DisplayData(micOutputData);
        // std::cout <<  "result in cpp : " << result << std::endl;
        if (result >= 0.0)
        {

            timing_Debug.noteTime();
            // auto current_time = std::chrono::steady_clock::now();
            // auto elapsed_time = std::chrono::duration_cast<std::chrono::milliseconds>(current_time - pMySink.start_time);
            // int seconds = static_cast<int>(elapsed_time.count());
            // Now you can use 'seconds' as an integer
            // std::cout << "result in seconds: " << seconds << std::endl;
            // timing.noteTime(seconds);
            // std::cout << "Elapsed Time: " << timing.getElapsedTime() << std::endl;
            // std::cout << "Max Time: " << timing.getMaxTime() << std::endl;
            // std::cout << "Min Time: " << timing.getMinTime() << std::endl;

            // auto elapsed_time = std::chrono::duration_cast<std::chrono::milliseconds>(end_time - pMySink->start_time).count();
            // std::cout << "result in epoch : " << elapsed_time << std::endl;
            return 1.0;
        }
        return 0.0;
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
