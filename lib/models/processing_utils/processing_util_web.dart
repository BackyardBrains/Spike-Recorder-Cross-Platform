import 'dart:async';
import 'dart:typed_data';
import 'dart:ffi';
import 'processing_util.dart';

class ProcessingUtilImpl implements ProcessingUtil {
  bool _isInitialized = false;
  
  @override
  Pointer<Pointer<Int16>>? currentDataBuffer;

  @override
  Future<bool> init() async {
    _isInitialized = true;
    return true;
  }
  
  @override
  Future<bool> initializeMicrophone(int channelCount, int sampleRate) async {
    if (!_isInitialized) {
      await init();
    }
    return true;
  }

  @override
  List<Int16List> processMicrophoneData(Uint8List data) {
    // Return empty list as mock data
    return [Int16List(0)];
  }
  
  @override
    int prepareForSignalDrawingProcess( Pointer<Pointer<Int16>> outSamples,
                                        Pointer<Int32> outSampleCounts,
                                        Pointer<Float> outEventIndices,
                                        Pointer<Int32> outEventCount,
                                        Pointer<Int32> inEventIndices,
                                        int inEventCount,
                                        int fromSample,
                                        int toSample,
                                        int drawSurfaceWidth)
  {
    // Simple mock implementation for web
    // Just return success code
    return 0;
  }
}

// Factory function to create an instance
ProcessingUtil createProcessingUtil() => ProcessingUtilImpl();
