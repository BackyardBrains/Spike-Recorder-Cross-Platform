#include "sample_buffer.h"

SampleBuffer::SampleBuffer(int64_t pos) : _pos(pos), _head(0), _buffer(new int16_t[SIZE]), _notEmpty(false)
{
    memset(_buffer, 0, sizeof(int16_t[SIZE]));
    memset(segmentsState, 0, sizeof(int[NUMBER_OF_SEGMENTS]));

    int size = SIZE / 2;

    // create SIZE_LOG2 (21) envelope arrays.
    for (int i = 0; i < SIZE_LOG2; i++, size /= 2)
    {
        _envelopes[i].assign(size + 1, std::pair<int16_t, int16_t>(0, 0));
    }
}

//
// Copy envelopes
//
SampleBuffer::SampleBuffer(const SampleBuffer &other) : _pos(other._pos), _head(other._head), _buffer(new int16_t[SIZE]), _notEmpty(false)
{

    // std::cout << "" << pos1 << std::endl;

    memcpy(_buffer, other._buffer, sizeof(int16_t[SIZE]));
    memcpy(segmentsState, other.segmentsState, sizeof(int[NUMBER_OF_SEGMENTS]));
    for (int i = 0; i < static_cast<int>(SIZE_LOG2); i++)
    {
        _envelopes[i] = other._envelopes[i];
    }
}

//
// Destructor
//
SampleBuffer::~SampleBuffer()
{
    delete[] _buffer;
}

//
// Assign (copy) envelope
//

void SampleBuffer::addData(const int16_t *src, int64_t len)
{
    if (len > 0)
        _notEmpty = true;
    for (int i = 0; i < len; i++)
    {
        for (int j = 1; j <= SIZE_LOG2; j++)
        {
            const int skipCount = (1 << j); // this is 2,4,8,....,2^21 = 2097152
            const int envelopeIndex = (j - 1);

            // This envelopeSampleIndex has same value for skipCount consecutive samples.
            // So for every level of envelope resolution (envelopeIndex) we find max and min sample
            // on interval of skipCount consecutive samples and store as one value of envelope
            // at envelopeSampleIndex index
            const unsigned int envelopeSampleIndex = (_head / skipCount); // ROUNDING on division!!!!

            // std::cout << "snvelopSampleIndex " << envelopeIndex << std::endl;

            if (envelopeSampleIndex >= _envelopes[envelopeIndex].size())
            {
                // this is basicaly error situation, should not ever happen
                continue;
            }

            // check if we have new min/max values with this new sample
            std::pair<int16_t, int16_t> &dst = _envelopes[envelopeIndex][envelopeSampleIndex];
            if (_head % skipCount == 0)
            {
                // if it is first in skipCount consecutive samples
                // take this to compare with others
                dst = std::pair<int16_t, int16_t>(*src, *src);
            }
            else
            {
                // if it is not first in skipCount consecutive samples
                //  compare and keep max and min
                dst = std::pair<int16_t, int16_t>(std::min(dst.first, *src), std::max(dst.second, *src));
            }
        }

        // add raw data to simple circular buffer
        // std::cout << "head " << _head << std::endl;

        _buffer[_head++] = *src++;

        if (_head == SIZE)
            _head = 0;
    }
    // std::cout << "Adding inside: _pos = " << _pos << "\n";
    _pos += len; // add to cumulative number of samples (number of samples since begining of the time)
    // std::cout << "After Adding inside: _pos = " << _pos << "\n";
    // std::cout<<"Head: "<<_head<<" Pos: "<<_pos<<"\n";
}

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
void SampleBuffer::simpleAddData(const int16_t *src, int64_t len, int16_t stride)
{
    if (len > 0)
        _notEmpty = true;
    for (int i = 0; i < len; i++)
    {
        // copy data
        _buffer[_head++] = *src;

        // jump to next sample from the same channel
        src = src + stride;

        // wrap around circular buffer
        if (_head == SIZE)
            _head = 0;
    }

    // move reading head (tail) also
    _pos += len;
}

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
void SampleBuffer::getData(int16_t *dst, int64_t offset, int64_t len) const
{
    int64_t j = 0;
    for (int64_t i = offset - _pos; i < (offset - _pos + len); i++, j++)
    {
        //(i < -SIZE) - we already owervrite values
        if (i < -SIZE)
        {
            dst[j] = 0;
            // std::cout<<"Error - asking for data that does not exist\n";
        }
        else if (i >= 0) //(i >= 0) - asking for future values
        {
            // we will provide last value if we are asking for future values
            // in this way we will not have clicking sound in audio
            // as we would if we are sending zeros for signal with offset
            dst[j] = _buffer[(_head + -1 + SIZE) % SIZE];
            // std::cout<<"Old value"<<"\n";
        }
        else
        {

            dst[j] = _buffer[(_head + i + SIZE) % SIZE];
        }
    }
}

void SampleBuffer::getDataEnvelope(std::pair<int16_t, int16_t> *dst, int64_t offset, int64_t len, int skip) const
{

    // std::cout << " Pos is " << _pos << std::endl;
    // int rightValue = _pos + len;
    // std::cout << " right  int value " << rightValue << std::endl;

    // qDebug() << "SampleBuffer: CALLING getDataEnvelope(<dst>," << offset << "," << len << "," << skip << ") w/ force =" << force;
    const int64_t lllleft = (offset - _pos);        //(negative value)
    const int64_t rrrright = (offset - _pos + len); //(usually negative value if we don't ask for future)
    int j = 0;
    for (int64_t i = lllleft; i < rrrright; j++)
    {
        std::pair<int16_t, int16_t> bounding(0, 0);

        // if (i >= -SIZE) we still have that data in circular buffer
        //  (i + skip <= 0) we are not asking for future
        if (i >= -SIZE && i + skip <= 0)
        {
            // qDebug() << "Whole thing...";
            // we can process the whole thing

            // DEBUG: Stanislav

            uint64_t index = (_head + i + SIZE) % SIZE; // transform index "i" into circular buffer reference frame
            unsigned int remaining = skip;
            bounding = std::pair<int16_t, int16_t>(_buffer[index], _buffer[index]);
            while (remaining > 0)
            {
                // qDebug() << "index =" << index;
                int levels = -1;
                uint64_t multiplier = 1;
                while ((index % (multiplier * 2) == 0) && (multiplier * 2) <= remaining)
                {
                    multiplier *= 2;
                    levels++;
                }
                // qDebug() << "levels =" << levels << " multiplier =" << multiplier;
                if (levels >= 0 && levels < SIZE_LOG2 && (index / multiplier) < _envelopes[levels].size())
                {
                    // qDebug() << "A";
                    // qDebug() << "dst[" << j << "] examines Examining _envelopes[" << (levels-1) << "][" << (index/multiplier) << "]" << _envelopes[levels].size();
                    const std::pair<int16_t, int16_t> val = _envelopes[levels][index / multiplier];
                    // qDebug() << "OK";
                    if (val.first < bounding.first)
                        bounding.first = val.first;
                    if (val.second > bounding.second)
                        bounding.second = val.second;
                    index = (index + multiplier) % SIZE;
                    remaining -= multiplier;
                }
                else
                {
                    // qDebug() << "B";
                    const int16_t val = _buffer[index];
                    if (val > bounding.second)
                        bounding.second = val;
                    if (val < bounding.first)
                        bounding.first = val;
                    index = (index + 1) % SIZE;
                    remaining--;
                }
                // qDebug() << "OK2";
            }
            // qDebug() << "OK3";
            i += skip;
        }
        else if ((i < -SIZE && i + skip <= -SIZE) || i >= 0)
        {
            // qDebug() << "None...";
            // none of it
            i += skip;
        }
        else
        {
            // qDebug() << "Some...";
            // TODO some of it...
            i += skip;
        }
        // if (j > 1897) qDebug() << "dst[" << j << "] =" << bounding << (len / skip);
        dst[j] = bounding;
        // qDebug() << "zZz";
    }
    // qDebug() << "SampleBuffer: RETURNING";
}

std::vector<int16_t> SampleBuffer::getData(int64_t offset, int64_t len) const
{
    std::vector<int16_t> result(len);
    getData(result.data(), offset, len);

    return result;
}

//
// Parameters:
//    offset - offset in samples from begining of the time
//    len - number of samples to get
//    skip - get every "skip" sample (skip "skip"-1 sample after each sample)
//
//
//     returns len/skip data samples
//
std::vector<std::pair<int16_t, int16_t>> SampleBuffer::getDataEnvelope(int64_t offset, int64_t len, int skip) const
{
    // std::cout << "In SampleBuffer::getDataEnvelope" << std::endl;

    std::vector<std::pair<int16_t, int16_t>> result(len / skip);
    // std::cout << "len :  " << len << std::endl;
    // std::cout << "offset :  " << offset << std::endl;
    // std::cout << "skip :  " << skip << std::endl;
    // std::cout << "result length :  " << len / skip << std::endl;
    // << std::endl;
    getDataEnvelope(result.data(), offset, len, skip);
    // std::cout << "result from sampleBuffer : " << offset << std::endl;
    return result;
}
