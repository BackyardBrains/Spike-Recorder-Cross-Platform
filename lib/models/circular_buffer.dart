import 'dart:typed_data';

import 'package:spikerbox_architecture/models/debugging.dart';

class CircularBuffer {
  final Uint8List _buffer;
  int _readIndex = 0;
  int _writeIndex = 0;

  CircularBuffer(int bufferSize) : _buffer = Uint8List(bufferSize);

  void write(Uint8List data) {
    // Debugging.printing("_writeIndex before writing: $_writeIndex");
    for (int i = 0; i < data.length; i++) {
      int indexToFill = _writeIndex + 1;
      if (indexToFill >= _buffer.length) {
        indexToFill = 0;
      }
      _writeIndex = indexToFill;
      _buffer[_writeIndex] = data[i];
    }
    // Debugging.printing("_writeIndex after writing: $_writeIndex");
    // Debugging.printing("Buffer after adding data: $_buffer");
  }

  Uint8List read(int length) {
    Uint8List dataRead = Uint8List(length);
    for (int i = 0; i < length; i++) {
      int indexToRead = _readIndex + 1;
      if (indexToRead >= _buffer.length) {
        indexToRead = 0;
      }
      _readIndex = indexToRead;
      dataRead[i] = _buffer[_readIndex];
    }
    // Debugging.printing("_readIndex: $_readIndex");
    return dataRead;
  }

  int get readableBytes {
    if (_writeIndex >= _readIndex) {
      return _writeIndex - _readIndex;
    } else {
      return ((_buffer.length - 1) - _readIndex) + _writeIndex;
    }
  }
}

class BufferHandler {
  final CircularBuffer _buffer;
  final void Function(Uint8List)? onDataAvailable;

  /// In bytes
  final int chunkReadSize;

  /// [chunkReadSize] - Number of bytes returned by the the buffer
  ///
  /// [bufferSize] - Total buffer length in bytes
  ///
  /// [onDataAvailable] - Callback function when next chunk of [chunkReadSize] is available
  BufferHandler(
      {required this.onDataAvailable,
      int bufferSize = 327680,
      this.chunkReadSize = 16})
      : _buffer = CircularBuffer(bufferSize),
        assert(chunkReadSize < bufferSize);

  void addBytes(Uint8List inputBytes) {
    _buffer.write(inputBytes);

    while (_buffer.readableBytes >= chunkReadSize) {
      Uint8List dtRead = _buffer.read(chunkReadSize);
      onDataAvailable?.call(dtRead);
    }
  }
}

class BufferHandlerOnDemand {
  BufferHandlerOnDemand(
      {required this.onDataAvailable,
      int bufferSize = 327680,
      this.chunkReadSize = 16})
      : _buffer = CircularBuffer(bufferSize),
        assert(chunkReadSize < bufferSize);

  final CircularBuffer _buffer;
  final void Function(Uint8List)? onDataAvailable;

  /// In bytes
  final int chunkReadSize;

  bool toFetchBytes = true;

  void addBytes(Uint8List inputBytes) {
    _buffer.write(inputBytes);
    if (toFetchBytes) requestData();
  }

  /// Request for next packet
  void requestData([int? chunkSize]) {
    int cl = chunkSize ?? chunkReadSize;
    if (_buffer.readableBytes >= cl) {
      Uint8List dtRead = _buffer.read(cl);
      onDataAvailable?.call(dtRead);
    }
  }
}

void checkCircularBuffer() {
  void onDataAvailable(Uint8List chunk) {
    print('Received chunk: $chunk');
  }

  BufferHandler buffer = BufferHandler(onDataAvailable: onDataAvailable);

  // Example input data
  Uint8List input1 =
      Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]);
  Uint8List input2 = Uint8List.fromList([13, 14, 15, 16, 17, 18, 19]);
  Uint8List input3 =
      Uint8List.fromList([20, 21, 22, 23, 24, 25, 26, 27, 28, 29]);
  Uint8List input4 = Uint8List.fromList(List.generate(15, (i) => i + 30));
  Uint8List input5 = Uint8List.fromList(List.generate(10, (i) => i + 45));

  List<Uint8List> exampleData = [input1, input2, input3, input4, input5];

  for (int i = 0; i < exampleData.length; i++) {
    Debugging.printing("input ${i + 1}: ${exampleData[i]}");
    buffer.addBytes(exampleData[i]);
  }
}
