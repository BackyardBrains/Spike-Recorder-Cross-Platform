import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'dart:math' as math;

class FftDrawBuffer {
  final int windowCount;
  final int windowSize;

  late List<Float32List> buffer;

  FftDrawBuffer(this.windowCount, this.windowSize) {
    buffer = List.generate(
        windowCount, (_) => Float32List(windowSize)..fillRange(0, windowSize, -1));
  }

  /// Returns buffer window size.
  int getWindowSize() {
    return windowSize;
  }

  /// Returns buffer window count.
  int getWindowCount() {
    return windowCount;
  }

  /// Returns window at `position`.
  Float32List getWindow(int position) {
    return position < windowCount ? buffer[position] : Float32List(0);
  }

  /// Returns buffer data.
  List<Float32List> getBuffer() {
    return buffer;
  }

  /// Adds new `incoming` samples to the buffer.
  void add(List<Float32List> incoming, int length) {
    try {
      int counter = 0;
      final int len = windowCount - length;
      if (length < windowCount) {
        // Shift existing data to make space for new data
        for (int i = length; i < windowCount; i++) {
            // System.arraycopy(buffer[i], 0, buffer[counter++], 0, windowSize);
            // buffer[counter++].setAll(0, buffer[i].buffer.asFloat32List(0, windowSize));
            // WRONG IN THIS PART
            // buffer[counter++] = (buffer[i].buffer.asFloat32List(0, windowSize));
            buffer[counter++] = (buffer[i].sublist(0, windowSize));
        }
        counter = 0;
        for (int i = 0; i < length; i++) {
            // System.arraycopy(incoming[i], 0, buffer[len + counter++], 0, windowSize);
            // buffer[len + counter++].setAll(0, incoming[i].buffer.asFloat32List(0, windowSize));
            // buffer[len + counter++] = incoming[i].buffer.asFloat32List(0, windowSize);
            buffer[len + counter++] = incoming[i].sublist(0, windowSize);
        }
        // print("buffer[i].sublist(0, windowSize): ${incoming[0].sublist(0, windowSize)}");
        
        // print("LARGER!! $len --- $windowCount - $length BBBB ${buffer.length}");
        // for (int i = 0; i < shiftCount; i++) {
        //   buffer[i].setAll(0, buffer[i + length]);
        // }
        
        // // Add new incoming data
        // for (int i = 0; i < length; i++) {
        //   buffer[i + shiftCount].setAll(0, incoming[i]);
        // }
      } else {
        // The incoming data is larger than or equal to the buffer size,
        // so we just copy the last `windowCount` elements.
        for (int i = length - windowCount; i < length; i++) {
            // System.arraycopy(incoming[i], 0, buffer[counter++], 0, windowSize);
            // buffer[counter++].setAll(0, incoming[i].buffer.asFloat32List(0, windowSize));
            buffer[counter++].setAll(0, incoming[i].sublist(0, windowSize));
        }

        // for (int i = 0; i < windowCount; i++) {
        //   buffer[i].setAll(0, incoming[i + length - windowCount]);
        // }
      }
      // print("Buffer : ${buffer[0]}");
    } catch (e, stacktrace) {
      if (kDebugMode) {
        print('Can\'t add incoming to buffer: $e');
        print(stacktrace);
      }
      // For a real app, you might want a more robust error reporting mechanism.
      // e.g., Crashlytics equivalent.
    }
  }

  /// Clears the buffer.
  void clear() {
    for (int i = 0; i < windowCount; i++) {
      buffer[i].fillRange(0, windowSize, -1);
    }
  }
}