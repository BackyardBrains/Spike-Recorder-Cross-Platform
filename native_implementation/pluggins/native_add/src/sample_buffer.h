#ifndef BACKYARDBRAINS_SAMPLEBUFFER_H
#define BACKYARDBRAINS_SAMPLEBUFFER_H

#include <vector>
#include <cstring>
#include <cassert>
#include <stdint.h>
#include <iostream>

#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <math.h>
#include <algorithm>
#include <cmath>
#include <cstdlib>
#include <stdint.h>

//==============================================================================
// - This class has circular buffer "_buffer" with raw data for one channel
//   and 21 (SIZE_LOG2) envelopes
// - Each envelope contains subsampled data at different resolution.
// - Each envelope is half the length of previous envelope, namely contains signal at
//   half of the resolution
// - Each envelope contains two arrays. First array contains maximal values of signal and
//   second array contains minimal value of the signal
//
// Values in envelopes are added gradualy as we receive more and more data.
// When circular buffer "_buffer" starts from begining (rewinds) envelopes also start rewriting data
// from the begining
//
// Whole point is to have minimum and maximum on some interval that is phisicaly one pixel
// on the screen so that we can draw vertical line to indicate to user amplitude span of the signal
//
//
//        Look at "AudioView::drawData" it draws vertical lines for each "sample" (subsample)
//        glVertex3i(xc, -data[j].first*_channels[channel].gain*scale+y, 0);
//        glVertex3i(xc, -data[j].second*_channels[channel].gain*scale+y, 0);
//==============================================================================

#define NUMBER_OF_SEGMENTS 120
#define SEGMENT_SIZE 44100

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

class SampleBuffer
{
public:
    static const int64_t SIZE = NUMBER_OF_SEGMENTS * SEGMENT_SIZE;
    static const int SIZE_LOG2 = 21;

    //
    // Set initial values of parameters and create envelopes
    // create SIZE_LOG2 (21) envelope arrays. Every envelope is half the length of previous
    // each envelope has two arrays:
    // First array holds maximum values of signal (just subsampled)
    // Second array holds minimum values of signal (just subsampled)
    //
    SampleBuffer(int64_t pos = 0);
    //
    // Copy envelopes
    //
    SampleBuffer(const SampleBuffer &other);
    //
    // Destructor
    //
    ~SampleBuffer();
    SampleBuffer &operator=(const SampleBuffer &other)
    {
        _pos = other._pos;
        _head = other._head;
        memcpy(_buffer, other._buffer, sizeof(int16_t[SIZE]));
        memcpy(segmentsState, other.segmentsState, sizeof(int[NUMBER_OF_SEGMENTS]));
        for (int i = 0; i < SIZE_LOG2; i++)
        {
            _envelopes[i] = other._envelopes[i];
        }
        _notEmpty = other._notEmpty;
        return *this;
    }

    //
    // Assign (copy) envelope
    //

    //
    // Look at the explanation at the begining of this file
    //
    // Add raw data from src to circular buffer _buffer and
    // Make envelopes. Check for every sample and every envelope
    // do we have new maximum or minimum.
    //
    // Parameters:
    // src - data from one channel (deinterleaved)
    // len - length of data in samples0
    //
    void addData(const int16_t *src, int64_t len);

    //
    // Just copy raw data for one channel from interleaved "src" buffer to
    // non-interleaved circular buffer "_buffer"
    // for "stride" channel
    // (just raw data, ignore envelopes)
    // Move the reading head (tail) also by "len" samples
    //
    // Parameters:
    // src - source buffer
    // len - number of frames (or number of samples for single channel)
    // stride - number of channels in one frame
    //
    void simpleAddData(const int16_t *src, int64_t len, int16_t stride);

    //
    // Parameters:
    //
    //      dst - destination buffer
    //      offset - offset in number of samples since begining of the time
    //      len - number of samples to get
    //
    //   Gets raw data from circular bufer using index "offset" that is given
    //   in number of the samples since begining of the time. Since "_pos" represents
    //   cumulative number of the samples since begining of the time (this buffer has received)
    //   offset must be smaller value (we can't fetch into future)
    void getData(int16_t *dst, int64_t offset, int64_t len) const;

    void getDataEnvelope(std::pair<int16_t, int16_t> *dst, int64_t offset, int64_t len, int skip) const;

    std::vector<int16_t> getData(int64_t offset, int64_t len) const;

    //
    // Parameters:
    //    offset - offset in samples from begining of the time
    //    len - number of samples to get
    //    skip - get every "skip" sample (skip "skip"-1 sample after each sample)
    //
    //
    //     returns len/skip data samples
    //
    std::vector<std::pair<int16_t, int16_t>> getDataEnvelope(int64_t offset, int64_t len, int skip) const;
    int16_t at(int64_t pos) const
    {
        if (pos <= _pos - SIZE || pos >= _pos)
            return 0;
        return _buffer[(_head + pos - _pos + SIZE) % SIZE];
    }
    int64_t pos() const { return _pos; }

    void setPos(int64_t pos)
    {
        // std::cout<< "SampleBuffer: SETPOS CALLED "<<pos<<"\n";
        _pos = pos;
    }

    int head() const { return _head; }

    void setHead(int head)
    {
        _head = head % SIZE;
    }

    void reset()
    {
        //  std::cout<<"!!!!!!!!!!!!!!!!!! RESET buffer!!!!!!!!!!!\n";
        _pos = 0;
        _head = 0;
        memset(segmentsState, 0, sizeof(int[NUMBER_OF_SEGMENTS]));
        if (_notEmpty)
        {
            _notEmpty = false;
            memset(_buffer, 0, SIZE * sizeof(int16_t));

            for (int i = 0, size = SIZE / 2; i < SIZE_LOG2; i++, size /= 2)
                _envelopes[i].assign(size + 1, std::pair<int16_t, int16_t>(0, 0));
        }
    }
    bool empty() const { return !_notEmpty; }
    int segmentsState[NUMBER_OF_SEGMENTS];

private:
    // LOADED number of samples since begining of the time (we have to have that since
    // other parts of the application calculate samples from begining of the time
    // and this class has circular buffer that rewinds all the time)
    int64_t _pos;

    // LOADED number of bytes position of head in "_buffer" circular buffer
    int _head;

    // Circular buffer with raw data. Size is SIZE = 44100*60*1 samples
    int16_t *const _buffer;

    // There are SIZE_LOG2 (21) envelope arrays. Every envelope is half the length of previous
    // each envelope has two arrays:
    // First array holds maximum values of signal (just subsampled)
    // Second array holds minimum values of signal (just subsampled)
    std::vector<std::pair<int16_t, int16_t>> _envelopes[SIZE_LOG2];

    bool _notEmpty;
};

#endif
