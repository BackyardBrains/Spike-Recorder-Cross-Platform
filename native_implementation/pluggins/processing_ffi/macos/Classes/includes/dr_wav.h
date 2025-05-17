#ifndef DR_WAV_H
#define DR_WAV_H

#include <stdint.h>

// Types
typedef uint64_t drwav_uint64;
typedef uint32_t drwav_uint32;
typedef uint16_t drwav_uint16;
typedef int16_t drwav_int16;

// Main structure
typedef struct {
    drwav_uint32 sampleRate;
    drwav_uint16 channels;
    drwav_uint64 totalSampleCount;
} drwav;

#ifdef __cplusplus
extern "C" {
#endif

// Function declarations only
drwav* drwav_open_file(const char* filename);
void drwav_close(drwav* pWav);
drwav_uint64 drwav_read_s16(drwav* pWav, drwav_uint64 samplesToRead, drwav_int16* pBufferOut);
bool drwav_seek_to_sample(drwav* pWav, drwav_uint64 sample);

#ifdef __cplusplus
}
#endif

#endif  // DR_WAV_H