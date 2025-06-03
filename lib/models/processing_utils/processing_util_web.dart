import 'dart:async';
import 'dart:isolate';
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
  Future<bool> initializeMicrophone(int channelCount, int sampleRate, double drawSurfaceWidth) async {
    js.context['onDrawingBufferAllocated'] = onDrawingBufferAllocated;
    // print("initializeMicrophoneWeb: $channelCount, $sampleRate,");
    js.context.callMethod("initializeMicrophoneWeb", [channelCount, sampleRate, drawSurfaceWidth]);
    if (!_isInitialized) {
      await init();
    }
    // for (int i = 0; i < channelCount; i++) {
    //   ProcessingUtil.drawingBuffers.add(Int16List( (drawSurfaceWidth * 5).toInt() ));
    //   ProcessingUtil.drawingBufferCounts.add( (drawSurfaceWidth * 5).toInt() );
    // }

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
  List<Int16List> prepareDisplayMicrophoneData(List<Int16List> data, int drawSurfaceWidth, int channelCount, double displayTimeMs, GraphDataProvider provider, int startPositionIdx, int endPositionIdx) {
    // print("POSITION :  $startPositionIdx $endPositionIdx");
    js.context.callMethod("prepareDisplayMicrophoneDataWeb", [drawSurfaceWidth, channelCount, displayTimeMs, startPositionIdx, endPositionIdx]);
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
  void initializeSerial(Board board, double drawSurfaceWidth) {
    js.context.callMethod("initializeSerialWeb", [board.maxSampleRate, board.maxNumberOfChannels, drawSurfaceWidth]);
  }
  @override
  Future<int> processSerialData(Uint8List samples, int displayTimeMs, int deviceType, int deviceWidth, GraphDataProvider provider) async {
    // var jsSamples = samples.toList();
    js.context.callMethod("processSerialDataWeb", [samples, displayTimeMs, deviceType]);
    return Future.value(1);
  }
  @override
  Future<Uint8List> processDisplaySerialData(int displayTimeMs, int deviceType, int deviceWidth, GraphDataProvider provider, startPositionIdx, endPositionIdx) async {
    js.context.callMethod("displaySerialDataWeb", [ displayTimeMs, deviceType, deviceWidth, startPositionIdx, endPositionIdx]);
    return Future.value(Uint8List(0));
  }

  void processSerialDataIsolate(sendPort)  async {

    // await processSerialData(args[0], args[1], args[2], args[3], args[4]);
  }
  Future<Uint8List> processDisplaySerialDataIsolate(sendPort) async {
    // Uint8List data = await displaySerialData(args[0], args[1], args[2], args[3]);
    // ProcessingUtil.drawingBuffers = data;
    return Future.value(Uint8List(0));
  }


  void onDrawingBufferAllocated(List<Int16List> dataBufferList, Int16List countBufferList, final channelCount) {
    print("onDrawingBufferAllocated");
    print(dataBufferList[0].runtimeType);
    print(Int16List.fromList(dataBufferList[0]).length);
    print(countBufferList.length);
    print(countBufferList);
    ProcessingUtil.drawingBuffers.clear();
    for (int i = 0; i < channelCount; i++) {
      ProcessingUtil.drawingBuffers.add(dataBufferList[i]);
      ProcessingUtil.drawingBufferCounts = countBufferList;
    }
    // for (int i = 0; i < channelCount; i++) {
    //   ProcessingUtil.drawingBuffers.add(Int16List( (1110 * 5).toInt() ));
    //   ProcessingUtil.drawingBufferCounts.add( (1110 * 5).toInt() );
    // }

    // print("onDrawingBufferAllocated ENDED : ${ProcessingUtil.drawingBuffers[0]}");

  }

	Future<void> dispose() async 
	{
  }
}





// Factory function to create an instance
ProcessingUtil createProcessingUtil() => ProcessingUtilImpl();
