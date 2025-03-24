import 'dart:async';
import 'dart:typed_data';
import 'dart:ffi';

// Conditional export based on platform
export 'processing_util_native.dart'
    if (dart.library.html) 'processing_util_web.dart';

// The abstract interface all implementations must follow
abstract class ProcessingUtil {
  // Maximum display time in seconds
  static const double MAX_DISPLAY_SECONDS = 10.0;
  
  // Data buffer to store processed audio data (channels × samples)
  Pointer<Pointer<Int16>>? currentDataBuffer;
  
  Future<bool> init();
  
  // Initialize microphone with specific settings
  Future<bool> initializeMicrophone(int channelCount, int sampleRate);
  
  List<Int16List> processMicrophoneData(Uint8List data);
}
