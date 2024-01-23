import 'dart:ffi' as ffi;
import 'dart:math';
import 'dart:typed_data';

import '../../allocation.dart';

class EnvelopingConfig {
  EnvelopingConfig()
      : _envelopBufferLength = _defaultPixel * 2,
        _pixelCount = _defaultPixel,
        envelopingBuffer = allocate<ffi.Int16>(
          count: _defaultLen * 2,
          sizeOfType: ffi.sizeOf<ffi.Int16>(),
        );

  static const int _defaultLen = 44100 * 120;
  static const int _defaultPixel = 2000;

  int _skipCount = _defaultLen ~/ _defaultPixel;

  int _pixelCount;

  /// Includes both min and max
  /// [_pixelCount] * 2
  int _envelopBufferLength;

  int get envelopBufferLength => _envelopBufferLength;

  int _samplesToFetch = _defaultLen;
  int get sampleLength => _samplesToFetch;

  ffi.Pointer<ffi.Int16> envelopingBuffer;

  /// Returns skip count
  /// [bufferSize] - sample rate * time(in seconds)
  /// [pixelCount] - pixels / graph points
  int setConfig({int? pixelCount, int? bufferSize}) {
    // print("Buffer size is ${bufferSize}");
    if (pixelCount != null) _setPixelCount(pixelCount);
    if (bufferSize != null) _setSampleBufferSize(bufferSize);
    return _setSkipPoints();
  }

  void _setPixelCount(int pxCount) {
    _pixelCount = pxCount;
    _envelopBufferLength = 2 * _pixelCount;

    // Free the existing buffer
    free(envelopingBuffer);

    // Reallocate the existing buffer
    envelopingBuffer = allocate<ffi.Int16>(
      count: _envelopBufferLength,
      sizeOfType: ffi.sizeOf<ffi.Int16>(),
    );
  }

  /// Length as per buffer size give in cpp file
  void _setSampleBufferSize(int buffSize) {
    _samplesToFetch = buffSize;
  }

  int get skipCount => _skipCount;

  int _setSkipPoints() {
    if (_pixelCount == 0) {
      // Handle the case where _pixelCount is zero to avoid division by zero.
      print("Error: Division by zero. _pixelCount cannot be zero.");
      return 0; // or some default value based on your requirements
    }

    _skipCount = _samplesToFetch ~/ _pixelCount;
    print("Configuring for skipCount: $_skipCount");
    return _skipCount;
  }
}
