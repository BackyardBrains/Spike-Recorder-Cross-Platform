import 'dart:async';
import 'dart:typed_data';

// Conditional export based on platform
export 'processing_util_native.dart'
    if (dart.library.html) 'processing_util_web.dart';

// The abstract interface all implementations must follow
abstract class ProcessingUtil {
  Future<bool> init();
  List<Int16List> processMicrophoneData(Uint8List data);
}
