#ifndef ENVELOPE
#define ENVELOPE

#ifdef __cplusplus
#define EXTERNC extern "C"
#else
#define EXTERNC
#endif

#include <iostream>
#include <vector>
#include <random>
#include "sample_buffer.h"

EXTERNC FUNCTION_ATTRIBUTE double addDataToSampleBuffer(int16_t *src, int len);

EXTERNC FUNCTION_ATTRIBUTE double getDataFromSampleBuffer(int offset, int len, int skip, int16_t *src);

#endif