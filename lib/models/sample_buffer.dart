import 'dart:math';

// typedef outside the class
typedef int16_t = int;

class SampleBuffer {
  static const int NUMBER_OF_SEGMENTS = 120;
  static const int SEGMENT_SIZE = 44100;

  static const int SIZE = NUMBER_OF_SEGMENTS * SEGMENT_SIZE;
  static const int SIZE_LOG2 = 21;

  int _pos;
  int _head;
  List<int> _buffer;
  late List<List<Point<int>>> _envelopes;
  bool _notEmpty;
  List<int> segmentsState = List<int>.filled(NUMBER_OF_SEGMENTS, 0);

  SampleBuffer({int pos = 0})
      : _pos = pos,
        _head = 0,
        _buffer = List<int>.filled(SIZE, 0),
        _notEmpty = false {
    _envelopes = List.generate(
      SIZE_LOG2,
      (i) => List<Point<int>>.generate(
        SIZE ~/ pow(2, i + 1) + 1,
        (j) => Point<int>(0, 0),
      ),
    );
  }

  SampleBuffer copy() {
    SampleBuffer copy = SampleBuffer();
    copy._pos = _pos;
    copy._head = _head;
    copy._buffer = List<int>.from(_buffer);
    copy.segmentsState = List<int>.from(segmentsState);
    copy._envelopes = List.generate(
      SIZE_LOG2,
      (i) => List<Point<int>>.from(_envelopes[i]),
    );
    copy._notEmpty = _notEmpty;
    return copy;
  }

  void addData(List<int> src, int len) {
    if (len > 0) _notEmpty = true;
    for (int i = 0; i < len; i++) {
      for (int j = 1; j <= SIZE_LOG2; j++) {
        final skipCount = pow(2, j);
        final envelopeIndex = j - 1;
        final envelopeSampleIndex = _head ~/ skipCount;

        if (envelopeSampleIndex >= _envelopes[envelopeIndex].length) {
          continue;
        }

        var dst = _envelopes[envelopeIndex][envelopeSampleIndex];
        if (_head % skipCount == 0) {
          dst = Point(src[0], src[0]);
        } else {
          dst = Point(min(dst.x, src[0]), max(dst.y, src[0]));
        }
      }

      _buffer[_head++] = src[0];
      if (_head == SIZE) _head = 0;
      src.removeAt(0);
    }
    _pos += len;
  }

  void simpleAddData(List<int> src, int len, int stride) {
    if (len > 0) _notEmpty = true;
    for (int i = 0; i < len; i++) {
      _buffer[_head++] = src[0];
      src.removeAt(0);
      if (_head == SIZE) _head = 0;
    }
    _pos += len;
  }

  void getData(List<int> dst, int offset, int len, int skip) {
    final lllleft = offset - _pos;
    final rrrright = offset - _pos + len;
    int j = 0;
    for (int i = lllleft; i < rrrright; j++) {
      if (i < -SIZE || i >= _pos) {
        dst[j] = 0;
      } else if (i >= 0) {
        dst[j] = _buffer[(_head + -1 + SIZE) % SIZE];
      } else {
        dst[j] = _buffer[(_head + i + SIZE) % SIZE];
      }
      i += skip;
    }
  }

  List<int> getDataWithoutDst(int offset, int len, int skip) {
    final result = List<int>.filled(len ~/ skip, 0);
    getData(result, offset, len, skip);
    return result;
  }

  int at(int pos) {
    if (pos <= _pos - SIZE || pos >= _pos) return 0;
    return _buffer[(_head + pos - _pos + SIZE) % SIZE];
  }

  int pos() => _pos;

  void setPos(int pos) {
    _pos = pos;
  }

  int head() => _head;

  void setHead(int head) {
    _head = head % SIZE;
  }

  void reset() {
    _pos = 0;
    _head = 0;
    segmentsState.fillRange(0, NUMBER_OF_SEGMENTS, 0);
    if (_notEmpty) {
      _notEmpty = false;
      _buffer.fillRange(0, SIZE, 0);

      for (int i = 0, size = SIZE ~/ 2; i < SIZE_LOG2; i++, size ~/= 2) {
        _envelopes[i] = List<Point<int>>.filled(size + 1, Point<int>(0, 0));
      }
    }
  }

  bool empty() => !_notEmpty;
}
