import 'dart:async';
import 'dart:typed_data';

// Export the platform-specific implementation
export 'processing_util_native.dart'
    if (dart.library.html) 'processing_util_web.dart';

// This is the base abstract class that defines the interface
abstract class ProcessingUtil {
  Future<void> init();
  Future<void> processNewData(dynamic data);
}
