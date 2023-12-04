// #pragma once

// //
// #include <audioclient.h>
// #include <Mmdeviceapi.h>
// #include <fstream>
// #include <iostream>
// #include <cmath>

// using namespace std;

// class MyAudioSink
// {

// private:
//     size_t data_chunk_pos;
//     size_t file_length;
//     ofstream mainFile;

//     // sample format
//     WORD wFormatTag;
//     WORD nChannels;
//     DWORD nSamplesPerSec;
//     DWORD nAvgBytesPerSec;
//     WORD nBlockAlign;
//     WORD wBitsPerSample;
//     WORD cbSize;
//     int test;

// public:
//     bool bComplete;

//     HRESULT SetFormat(WAVEFORMATEX *pwfx);
//     HRESULT CopyData(BYTE *pData, UINT32 numFramesAvailable, BOOL *bDone);
// };
