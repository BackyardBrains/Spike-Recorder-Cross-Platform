// #pragma once

// #include "MyAudioSink.h"
// #include <string.h>

// namespace little_endian_io
// {
//     template <typename Word>
//     std::ostream &write_word(std::ostream &outs, Word value, unsigned size = sizeof(Word))
//     {

//         for (; size; --size, value >>= 8)
//             outs.put(static_cast<char>(value & 0xFF));
//         return outs;
//     }
// }
// using namespace little_endian_io;

// HRESULT MyAudioSink::SetFormat(WAVEFORMATEX *pwfx)
// {

//     // Update our format variables
//     wFormatTag = pwfx->WAVE_FORMAT_PCM;
//     nChannels = pwfx->nChannels;
//     nSamplesPerSec = pwfx->nSamplesPerSec;
//     nAvgBytesPerSec = pwfx->nAvgBytesPerSec;
//     nBlockAlign = pwfx->nBlockAlign;
//     wBitsPerSample = pwfx->wBitsPerSample;
//     cbSize = pwfx->cbSize;

//     return S_OK;
// }

// HRESULT MyAudioSink::CopyData(BYTE *pData, UINT32 numFramesAvailable, BOOL *bDone)
// {
//     // TODO

//     // forgot how to do this part, figure it out
//     for (int i = 0; i < numFramesAvailable; i++)
//     {
//         mainFile.write((const char *)pData + (i * nBlockAlign), nBlockAlign);
//     }

//     // test
//     test++;
//     if (test >= nBlockAlign * 120)
//         bComplete = true;

//     // check if our main function is done to finish capture
//     if (bComplete)
//         *bDone = true;

//     return S_OK;
// }
