// Stub implementations for missing SZ compression functions
// These prevent runtime crashes when HDF5 tries to use SZIP compression

#include <cstddef>
#include <cstring>

extern "C" {
    // SZ compression functions
    int SZ_encoder_enabled() { return 0; }  // Disable SZ encoder
    
    int SZ_BufftoBuffCompress(void* src, size_t srcLen, void* dst, size_t* dstLen, int) {
        // Simple copy without compression
        if (*dstLen < srcLen) return -1;
        memcpy(dst, src, srcLen);
        *dstLen = srcLen;
        return 0;
    }
    
    int SZ_BufftoBuffDecompress(void* src, size_t srcLen, void* dst, size_t* dstLen, int) {
        // Simple copy without decompression
        if (*dstLen < srcLen) return -1;
        memcpy(dst, src, srcLen);
        *dstLen = srcLen;
        return 0;
    }
}
