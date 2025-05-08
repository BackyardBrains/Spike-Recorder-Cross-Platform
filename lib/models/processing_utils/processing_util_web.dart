import 'dart:async';
import 'dart:typed_data';
// import 'dart:ffi';
import 'package:spikerbox_architecture/models/default_config_model.dart';
import 'package:spikerbox_architecture/provider/graph_stream_data.dart';

import 'processing_util.dart';
import 'dart:js' as js;

class ProcessingUtilImpl implements ProcessingUtil {
  bool _isInitialized = false;
  
  @override
  var currentDataBuffer;

  @override
  Future<bool> init() async {
    _isInitialized = true;
    return true;
  }
  
  @override
  Future<bool> initializeMicrophone(int channelCount, int sampleRate) async {
    js.context.callMethod("initializeMicrophoneWeb", [channelCount, sampleRate]);
    if (!_isInitialized) {
      await init();
    }
    return true;
  }

  @override
  List<Int16List> processMicrophoneData(Uint8List data) {
    js.context.callMethod("processMicrophoneDataWeb", [data, 0, data.length]);
    // Return empty list as mock data
    return [Int16List(0)];
  }
  
  @override
    int prepareForSignalDrawingProcess( outSamples,
                                        outSampleCounts,
                                        outEventIndices,
                                        outEventCount,
                                        inEventIndices,
                                        int inEventCount,
                                        int fromSample,
                                        int toSample,
                                        int drawSurfaceWidth)
  {
    // Simple mock implementation for web
    // Just return success code
    return 0;
  }


  @override
  Future<int> setBandFilter(double lowCutOffFreq, double highCutOffFreq) async {
    js.context.callMethod("setBandFilterWeb", [lowCutOffFreq, highCutOffFreq]);
    return 0;
  }

  @override
  Future<int> setNotchFilter(double centerFreq) async {
    js.context.callMethod("setNotchFilterWeb", [centerFreq]);
    return 0;
  }

  @override
  List<Int16List> prepareDisplayMicrophoneData(List<Int16List> data, int drawSurfaceWidth, int channelCount, double displayTimeMs, GraphDataProvider provider) {
    js.context.callMethod("prepareDisplayMicrophoneDataWeb", [drawSurfaceWidth, channelCount, displayTimeMs]);
    return [];
  }

  @override
  Map<String, dynamic> getInformation()  {
    return {};
  }


  int MAX_DISPLAY_SECONDS = 10000;
  
  int channelCount = 1;
  int sampleRate = 10000;
  int packetLen = 100000;

  @override
  void initializeSerial(Board board) {
    js.context.callMethod("initializeSerialWeb", [board.maxSampleRate, board.maxNumberOfChannels]);
  }
  @override
  void processSerialData(Uint8List samples, int displayTimeMs, int deviceType, int deviceWidth, GraphDataProvider provider) {
    // var jsSamples = samples.toList();
    js.context.callMethod("processSerialDataWeb", [samples, displayTimeMs, deviceType]);
  }



	Future<void> dispose() async 
	{
  }
}





// Factory function to create an instance
ProcessingUtil createProcessingUtil() => ProcessingUtilImpl();
