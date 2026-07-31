#ifndef WINDOWS_COMPAT_H
#define WINDOWS_COMPAT_H

// Windows compatibility fixes
#ifdef _WIN32
    // Prevent byte ambiguity with Windows API - must be first
    #ifndef NOMINMAX
    #define NOMINMAX
    #endif
    #ifndef WIN32_LEAN_AND_MEAN
    #define WIN32_LEAN_AND_MEAN
    #endif
    // Prevent std::byte conflicts
    #ifndef _HAS_STD_BYTE
    #define _HAS_STD_BYTE 0
    #endif
    
    // Include Windows headers
    #include <windows.h>
    #include <time.h>
    
    // Aggressive byte conflict resolution
    #ifdef byte
    #undef byte
    #endif
    #ifdef _BYTE_DEFINED
    #undef _BYTE_DEFINED
    #endif
    typedef unsigned char byte;
    #define _BYTE_DEFINED
    
    // Force resolution of any remaining byte conflicts
    #pragma push_macro("byte")
    #undef byte
    typedef unsigned char byte;
    #pragma pop_macro("byte")
    
    // Windows implementation of timeval if not already defined
    #ifndef _TIMEVAL_DEFINED
    #define _TIMEVAL_DEFINED
    struct timeval {
        long tv_sec;
        long tv_usec;
    };
    #endif
    
    // Windows implementation of timezone if not already defined
    #ifndef _TIMEZONE_DEFINED
    #define _TIMEZONE_DEFINED
    struct timezone {
        int tz_minuteswest;
        int tz_dsttime;
    };
    #endif
    
    // Implementation of gettimeofday for Windows
    inline int gettimeofday(struct timeval* tp, struct timezone* tzp) {
        // Note: this implementation does not handle timezone, but it's not used in this context
        FILETIME ft;
        ULARGE_INTEGER uli;
        GetSystemTimeAsFileTime(&ft);
        uli.LowPart = ft.dwLowDateTime;
        uli.HighPart = ft.dwHighDateTime;
        uli.QuadPart /= 10; // Convert to microseconds
        tp->tv_sec = (long)(uli.QuadPart / 1000000);
        tp->tv_usec = (long)(uli.QuadPart % 1000000);
        return 0;
    }
#endif

#endif // WINDOWS_COMPAT_H
