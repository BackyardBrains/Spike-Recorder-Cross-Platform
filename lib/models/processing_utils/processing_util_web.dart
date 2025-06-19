import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';
// import 'dart:ffi';
import 'package:spikerbox_architecture/models/default_config_model.dart';
import 'package:spikerbox_architecture/provider/graph_stream_data.dart';
import 'package:spikerbox_architecture/screen/spiker_box_ui.dart';

import 'processing_util.dart';
import 'dart:js' as js;

class ProcessingUtilImpl implements ProcessingUtil {
  bool _isInitialized = false;

  @override
  var currentDataBuffer;
  List<int> inEventIndicesPtr = [];
  List<int> inEventLabelsPtr = [];
  Float64List _eventPositionList = Float64List(0);

  int _sampleRate = 44100;

  @override
  Future<bool> init() async {
    _isInitialized = true;
    return true;
  }

  @override
  Future<bool> initializeMicrophone(
      int channelCount, int sampleRate, double drawSurfaceWidth) async {
    _sampleRate = sampleRate;
    js.context['onDrawingBufferAllocated'] = onDrawingBufferAllocated;
    // print("initializeMicrophoneWeb: $channelCount, $sampleRate,");
    js.context.callMethod("initializeMicrophoneWeb",
        [channelCount, sampleRate, drawSurfaceWidth]);
    js.context['onEventPositionAllocated'] = onEventPositionAllocated;
    js.context['onEventPositionCalculated'] = onEventPositionCalculated;
    if (!_isInitialized) {
      await init();
    }

    inEventIndicesPtr = [];
    inEventLabelsPtr = [];

    ProcessingUtil.currentEventMarkers = 0;
    initEventMarkers(_sampleRate);
    print("add LIstener marker");
    ProcessingUtil.eventMarkerNotifier.addListener(eventMarkerListener);

    // for (int i = 0; i < channelCount; i++) {
    //   ProcessingUtil.drawingBuffers.add(Int16List( (drawSurfaceWidth * 5).toInt() ));
    //   ProcessingUtil.drawingBufferCounts.add( (drawSurfaceWidth * 5).toInt() );
    // }

    return true;
  }

  @override
  List<Int16List> processMicrophoneData(Uint8List data) {
    // start setup markers

    int frameCount = (data.length / 2).floor();
    int removedIndicesCount = 0;
    for (int i = 0; i < ProcessingUtil.currentEventMarkers; i++) {
      if (inEventIndicesPtr[i] - frameCount > 0) {
        inEventIndicesPtr[i] -= frameCount;
        ProcessingUtil.eventPosition[i] = inEventIndicesPtr[i];
      } else {
        if (inEventIndicesPtr[i] != -1) {
          removedIndicesCount++;
          inEventIndicesPtr[i] = -1;
          // DraggableGraph.eventMarkersPosition.removeAt(i);
        }
      }
    }
    for (int i = 0; i < removedIndicesCount; i++) {
      if (inEventIndicesPtr[i] == -1) {
        // print(
        //     "INDEX: $i -- $removedIndicesCount __ ${inEventIndicesPtr[i]} : ${ProcessingUtil.eventLabels} @@ ${inEventIndicesPtr.asTypedList(ProcessingUtil.currentEventMarkers)}");
        if (ProcessingUtil.eventLabels.isNotEmpty) {
          ProcessingUtil.eventLabels.removeAt(0);
          ProcessingUtil.eventPosition.removeAt(0);
        }
      }
    }
    int tempCurrentEvent = ProcessingUtil.currentEventMarkers;
    ProcessingUtil.currentEventMarkers -= removedIndicesCount;
    if (inEventIndicesPtr.isNotEmpty && inEventIndicesPtr[0] == -1) {
      int eventPositionLen = ProcessingUtil.eventLabels.length;
      for (int i = eventPositionLen; i >= 0; i--) {
        inEventIndicesPtr[i] = ProcessingUtil.eventPosition[i];
      }
      for (int i = eventPositionLen; i < tempCurrentEvent; i++) {
        // print("ZEROING: $eventPositionLen - $tempCurrentEvent");
        inEventIndicesPtr[i] =
            (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
      }
    }

    js.context.callMethod("processMicrophoneDataWeb", [
      data,
      0,
      data.length,
    ]);
    // Return empty list as mock data
    return [Int16List(0)];
  }

  @override
  int prepareForSignalDrawingProcess(
      outSamples,
      outSampleCounts,
      outEventIndices,
      outEventCount,
      inEventIndices,
      int inEventCount,
      int fromSample,
      int toSample,
      int drawSurfaceWidth) {
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
  List<Int16List> prepareDisplayMicrophoneData(
      List<Int16List> data,
      int drawSurfaceWidth,
      int channelCount,
      double displayTimeMs,
      GraphDataProvider provider,
      int startPositionIdx,
      int endPositionIdx) {
    // print("POSITION :  $startPositionIdx $endPositionIdx");
    js.context.callMethod("prepareDisplayMicrophoneDataWeb", [
      drawSurfaceWidth,
      channelCount,
      displayTimeMs,
      startPositionIdx,
      endPositionIdx,
      json.encode(ProcessingUtil.eventLabels),
      json.encode(ProcessingUtil.eventPosition)
    ]);
    return [];
  }

  @override
  Map<String, dynamic> getInformation() {
    return {};
  }

  void initEventMarkers(int sampleRate) {
    if (inEventIndicesPtr.isNotEmpty) {
      inEventIndicesPtr.clear();
      inEventLabelsPtr.clear();
      inEventIndicesPtr =
          List<int>.generate(ProcessingUtil.MAX_EVENT_MARKERS, (_) => 0);
      inEventLabelsPtr =
          List<int>.generate(ProcessingUtil.MAX_EVENT_MARKERS, (_) => 0);
      ProcessingUtil.eventPosition = [];
      for (int i = 0; i < ProcessingUtil.MAX_EVENT_MARKERS; i++) {
        inEventIndicesPtr[i] = sampleRate * 10;
      }
    } else {
      for (int i = 0; i < ProcessingUtil.MAX_EVENT_MARKERS; i++) {
        inEventIndicesPtr[i] = sampleRate * 10;
      }
    }
  }

  void eventMarkerListener() {
    if (ProcessingUtil.eventMarkerNotifier.value == -1) return;
    ProcessingUtil.currentEventMarkers =
        (ProcessingUtil.currentEventMarkers + 1) %
            ProcessingUtil.MAX_EVENT_MARKERS;
    print("ADD LISTENER--- ${ProcessingUtil.eventMarkerNotifier.value}");

    if (ProcessingUtil.currentEventMarkers > ProcessingUtil.MAX_EVENT_MARKERS) {
      ProcessingUtil.currentEventMarkers = 0;
    }
    inEventLabelsPtr[ProcessingUtil.currentEventMarkers] =
        ProcessingUtil.eventMarkerNotifier.value;
    ProcessingUtil.eventLabels.add(ProcessingUtil.eventMarkerNotifier.value);
  }

  int MAX_DISPLAY_SECONDS = 10000;

  int channelCount = 1;
  int sampleRate = 10000;
  int packetLen = 100000;

  @override
  void initializeSerial(Board board, double drawSurfaceWidth) {
    js.context.callMethod("initializeSerialWeb",
        [board.maxSampleRate, board.maxNumberOfChannels, drawSurfaceWidth]);
  }

  @override
  Future<int> processSerialData(Uint8List samples, int displayTimeMs,
      int deviceType, int deviceWidth, GraphDataProvider provider) async {
    // var jsSamples = samples.toList();
    js.context.callMethod(
        "processSerialDataWeb", [samples, displayTimeMs, deviceType]);
    return Future.value(1);
  }

  @override
  Future<Uint8List> processDisplaySerialData(
      int displayTimeMs,
      int deviceType,
      int deviceWidth,
      GraphDataProvider provider,
      startPositionIdx,
      endPositionIdx) async {
    js.context.callMethod("displaySerialDataWeb", [
      displayTimeMs,
      deviceType,
      deviceWidth,
      startPositionIdx,
      endPositionIdx
    ]);
    return Future.value(Uint8List(0));
  }

  void processSerialDataIsolate(sendPort) async {
    // await processSerialData(args[0], args[1], args[2], args[3], args[4]);
  }
  Future<Uint8List> processDisplaySerialDataIsolate(sendPort) async {
    // Uint8List data = await displaySerialData(args[0], args[1], args[2], args[3]);
    // ProcessingUtil.drawingBuffers = data;
    return Future.value(Uint8List(0));
  }

  void onEventPositionAllocated(Float64List eventPositionList) {
    _eventPositionList = eventPositionList;
    // _eventPositionList.fillRange(0, 3, -123.456);
    print("onEventPositionAllocated: $_eventPositionList");
  }

  void onEventPositionCalculated() {
    // print("onEventPositionCalculated: $_eventPositionList");
    DraggableGraph.eventMarkersPosition.clear();
    DraggableGraph.eventMarkersPosition.addAll(_eventPositionList.toList());
  }

  void onDrawingBufferAllocated(List<Int16List> dataBufferList,
      Int16List countBufferList, final channelCount) {
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

  @override
  Future<int> setChannelFilterEnabled(int channel, bool enabled) async {
    if (!_isInitialized) {
      await init();
    }
    js.context
        .callMethod("setChannelFilterEnabled", [channel, enabled ? 1 : 0]);
    return 1;
    // return setChannelFilterEnabled(channel, enabled ? 1 : 0);
  }

  Future<void> dispose() async {
    ProcessingUtil.eventMarkerNotifier.removeListener(eventMarkerListener);
  }
}

// Factory function to create an instance
ProcessingUtil createProcessingUtil() => ProcessingUtilImpl();
