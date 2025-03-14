#include "includes/dr_wav.h"

drwav* drwav_open_file(const char* filename) {
    return nullptr;
}

void drwav_close(drwav* pWav) {
}

drwav_uint64 drwav_read_s16(drwav* pWav, drwav_uint64 samplesToRead, drwav_int16* pBufferOut) {
    return 0;
}

bool drwav_seek_to_sample(drwav* pWav, drwav_uint64 sample) {
    return true;
} 