import 'dart:async';
import 'dart:typed_data';
import 'dart:math' as Math;
import 'processing_util.dart';

class ProcessingUtilImpl implements ProcessingUtil {
  bool _isInitialized = false;

  @override
  Future<bool> init() async {
    // Initialize web-specific processing resources
    print('Initializing web processing utilities (mock implementation)');
    _isInitialized = true;
    return true;
  }

  @override
  List<Int16List> processMicrophoneData(Uint8List data) {
    if (!_isInitialized) {
      throw StateError('ProcessingUtil not initialized. Call init() first.');
    }

    // Web implementation returns a mock sample (no actual processing)
    print('Mock processing ${data.length} bytes of microphone data');
    
    // Create a simple mock output with one channel of data
    final mockSamples = Int16List(data.length ~/ 2);
    for (int i = 0; i < mockSamples.length; i++) {
      // Generate simple sine wave for demonstration
      mockSamples[i] = (Math.sin(i * 0.1) * 10000).toInt();
    }
    
    return [mockSamples];
  }
}

// Factory function to create an instance
ProcessingUtil createProcessingUtil() => ProcessingUtilImpl();
