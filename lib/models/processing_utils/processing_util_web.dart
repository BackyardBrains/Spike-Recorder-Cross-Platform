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
  Int32List inEventPositionPtr = Int32List(0);
  Int32List inEventIndicesPtr = Int32List(0);
  Int32List inEventLabelsPtr = Int32List(0);
  Float64List _eventPositionList = Float64List(0);

  int _sampleRate = 44100;
  bool isAllocated = false;

  @override
  Future<bool> init() async {
    _isInitialized = true;
    js.context['onEventPositionAllocated'] = onEventPositionAllocated;
    js.context['onEventPositionCalculated'] = onEventPositionCalculated;
    js.context['onEventFound'] = onEventFound;
    js.context['onSerialParsedCallback'] = onSerialParsedCallback;
    js.context['onDrawingBufferAllocated'] = onDrawingBufferAllocated;

    return true;
  }

  @override
  Future<bool> initializeMicrophone(
      int channelCount, int sampleRate, double drawSurfaceWidth) async {
    _sampleRate = sampleRate;
    if (!_isInitialized) {
      await init();
    }
    ProcessingUtil.currentEventMarkers = 0;
    ProcessingUtil.eventLabels.clear();
    ProcessingUtil.eventPosition.clear();
    isAllocated = false;

    // print("initializeMicrophoneWeb: $channelCount, $sampleRate,");
    js.context.callMethod("initializeMicrophoneWeb",
        [channelCount, sampleRate, drawSurfaceWidth]);

    // inEventIndicesPtr = [];
    // inEventLabelsPtr = [];

    ProcessingUtil.currentEventMarkers = 0;
    initEventMarkers(_sampleRate);
    // print("add LIstener marker $_sampleRate");
    ProcessingUtil.eventMarkerNotifier.removeListener(eventMarkerListener);
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
    if (!isAllocated) return [Int16List(0)];

    int frameCount = (data.length / 2).floor();
    int removedIndicesCount = 0;
    for (int i = 0; i < ProcessingUtil.currentEventMarkers; i++) {
      if (inEventIndicesPtr[i] - frameCount > 0) {
        inEventIndicesPtr[i] -= frameCount;
        ProcessingUtil.eventPosition[i] = inEventIndicesPtr[i];
        // print("ProcessingUtil.eventPosition[i] :  ${ProcessingUtil.eventPosition[i]} ${DateTime.now()}");
      } else {
        if (inEventIndicesPtr[i] != -1) {
          removedIndicesCount++;
          inEventIndicesPtr[i] = -1;
          // DraggableGraph.eventMarkersPosition.removeAt(i);
        }
      }
    }
    // print("inEventIndicesPtr: ${inEventIndicesPtr.sublist(0,2)}");
    for (int i = 0; i < removedIndicesCount; i++) {
      if (inEventIndicesPtr[i] == -1) {
        // print(
        //     "INDEX: $i -- $removedIndicesCount __ ${inEventIndicesPtr[i]} : ${ProcessingUtil.eventLabels} @@ ${inEventIndicesPtr.sublist(0, ProcessingUtil.currentEventMarkers)}");
        if (ProcessingUtil.eventLabels.isNotEmpty) {
          ProcessingUtil.eventLabels.removeAt(0);
          ProcessingUtil.eventPosition.removeAt(0);
        }
      }
    }
    if (inEventIndicesPtr.isNotEmpty && inEventIndicesPtr[0] == -1) {
      print("REMOVING BUFFER: ${inEventPositionPtr}");
      int tempCurrentEvent = ProcessingUtil.currentEventMarkers;
      ProcessingUtil.currentEventMarkers -= removedIndicesCount;

      int eventPositionLen = ProcessingUtil.eventLabels.length;
      int i = 0;
      for (i = 0; i < eventPositionLen; i++) {
        inEventIndicesPtr[i] = ProcessingUtil.eventPosition[i];
        inEventPositionPtr[i] = inEventPositionPtr[i + 1];
      }
      inEventPositionPtr[i] = inEventPositionPtr[i + 1];
      // print("inEventPositionPtr: $inEventPositionPtr");
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
    // DraggableGraph.eventMarkersPosition.clear();
    // DraggableGraph.eventMarkersPosition.addAll(_eventPositionList.toList());
    
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
    if (inEventIndicesPtr.length > 0) {
      // print("AFter Zero");
      // inEventIndicesPtr.clear();
      // inEventLabelsPtr.clear();
      // inEventIndicesPtr =
      //     List<int>.generate(ProcessingUtil.MAX_EVENT_MARKERS, (_) => sampleRate * ProcessingUtil.MAX_DISPLAY_SECONDS.floor());
      // inEventLabelsPtr =
      //     List<int>.generate(ProcessingUtil.MAX_EVENT_MARKERS, (_) => 0);
      int maxSamples = sampleRate * ProcessingUtil.MAX_DISPLAY_SECONDS.floor();
      inEventPositionPtr = Int32List(ProcessingUtil.MAX_EVENT_MARKERS.floor());
      inEventPositionPtr.fillRange(0, ProcessingUtil.MAX_EVENT_MARKERS.floor(), maxSamples);

      inEventIndicesPtr = Int32List(ProcessingUtil.MAX_EVENT_MARKERS.floor());
      inEventIndicesPtr.fillRange(0, ProcessingUtil.MAX_EVENT_MARKERS.floor(), maxSamples);

      inEventLabelsPtr = Int32List(ProcessingUtil.MAX_EVENT_MARKERS.floor());
      ProcessingUtil.eventPosition.clear();

      // ProcessingUtil.eventPosition = [];
      // for (int i = 0; i < ProcessingUtil.MAX_EVENT_MARKERS; i++) {
      //   inEventIndicesPtr[i] = sampleRate * 10;
      // }
    } else {
      // print("in Zero");
      inEventPositionPtr = Int32List(ProcessingUtil.MAX_EVENT_MARKERS.floor());
      inEventIndicesPtr = Int32List(ProcessingUtil.MAX_EVENT_MARKERS.floor());
      inEventLabelsPtr = Int32List(ProcessingUtil.MAX_EVENT_MARKERS.floor());

      inEventIndicesPtr.fillRange(0, ProcessingUtil.MAX_EVENT_MARKERS.floor(), sampleRate * ProcessingUtil.MAX_DISPLAY_SECONDS.floor());

      // for (int i = 0; i < ProcessingUtil.MAX_EVENT_MARKERS; i++) {
      //   inEventIndicesPtr[i] = sampleRate * ProcessingUtil.MAX_DISPLAY_SECONDS.floor();
      // }
    }
  }

  void eventMarkerListener() {
    List<int> list = ProcessingUtil.eventMarkerNotifier.value;
    if (list[0] == -1) return;


    try{
      inEventLabelsPtr[ProcessingUtil.currentEventMarkers] = list[0];
      if (list[1] != -1) {
        inEventIndicesPtr[ProcessingUtil.currentEventMarkers] = list[1];
      }
      ProcessingUtil.eventLabels.add(list[0]);
      // js.context.callMethod("onKeyPressEventMarker", [list[0], list[1], ProcessingUtil.currentEventMarkers, ProcessingUtil.fromSample, ProcessingUtil.toSample, _sampleRate * ProcessingUtil.MAX_DISPLAY_SECONDS]);

    }catch(err) {
      print("err marker listener");
      print(err);
    }
    ProcessingUtil.currentEventMarkers =
        (ProcessingUtil.currentEventMarkers + 1) %
            ProcessingUtil.MAX_EVENT_MARKERS;

  }

  int MAX_DISPLAY_SECONDS = 10000;

  int channelCount = 1;
  int sampleRate = 10000;
  int packetLen = 100000;

  @override
  void initializeSerial(Board board, double drawSurfaceWidth) {
    isAllocated = false;
    _sampleRate = int.parse(board.maxSampleRate!);
    ProcessingUtil.currentEventMarkers = 0;
    ProcessingUtil.eventLabels.clear();
    ProcessingUtil.eventPosition.clear();
    initEventMarkers(_sampleRate);
    inEventPositionPtr.fillRange(0, ProcessingUtil.MAX_EVENT_MARKERS, 0);
    ProcessingUtil.eventMarkerNotifier.removeListener(eventMarkerListener);
    ProcessingUtil.eventMarkerNotifier.addListener(eventMarkerListener);
    
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
      endPositionIdx,
      json.encode(ProcessingUtil.eventLabels),
      json.encode(ProcessingUtil.eventPosition)
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
    // inEventPositionPtr = inEventPositionPointerBuffer;
    inEventIndicesPtr.fillRange(0, ProcessingUtil.MAX_EVENT_MARKERS.floor(), _sampleRate * ProcessingUtil.MAX_DISPLAY_SECONDS.floor());

    // print("DEFAULT VALUE: $_sampleRate  =====  ${_sampleRate * ProcessingUtil.MAX_DISPLAY_SECONDS.floor()}");
    isAllocated = true;
    // _eventPositionList.fillRange(0, 3, -123.456);
    // print("onEventPositionAllocated: $_eventPositionList ${inEventIndicesPtr.length}");
  }

  void onEventFound(sampleIndex, eventLabel) {
    ProcessingUtil.eventMarkerNotifier.value = eventLabel;
    // ProcessingUtil.eventMarkerNotifier.value = [-1, -1];
    
  }
  void onSerialParsedCallback( int frameCount ) {
    // print("onSerialParsedCallback: ${inEventIndicesPtr[0]} - $frameCount");
    int removedIndicesCount = 0;
    for (int i = 0; i < ProcessingUtil.currentEventMarkers; i++) {
      if (inEventIndicesPtr[i] - frameCount > 0) {
        inEventIndicesPtr[i] -= frameCount;
        ProcessingUtil.eventPosition[i] = inEventIndicesPtr[i];
        // print("ProcessingUtil.eventPosition[i] :  ${ProcessingUtil.eventPosition[i]} ${DateTime.now()}");
      } else {
        if (inEventIndicesPtr[i] != -1) {
          removedIndicesCount++;
          inEventIndicesPtr[i] = -1;
          // DraggableGraph.eventMarkersPosition.removeAt(i);
        }
      }
    }
    // print("inEventIndicesPtr: ${inEventIndicesPtr.sublist(0,5)}");
    for (int i = 0; i < removedIndicesCount; i++) {
      if (inEventIndicesPtr[i] == -1) {
        // print(
        //     "INDEX: $i -- $removedIndicesCount __ ${inEventIndicesPtr[i]} : ${ProcessingUtil.eventLabels} @@ ${inEventIndicesPtr.sublist(0, ProcessingUtil.currentEventMarkers)}");
        if (ProcessingUtil.eventLabels.isNotEmpty) {
          ProcessingUtil.eventLabels.removeAt(0);
          ProcessingUtil.eventPosition.removeAt(0);
        }
      }
    }
    if (inEventIndicesPtr.isNotEmpty && inEventIndicesPtr[0] == -1) {
      int tempCurrentEvent = ProcessingUtil.currentEventMarkers;
      ProcessingUtil.currentEventMarkers -= removedIndicesCount;
      int eventPositionLen = ProcessingUtil.eventLabels.length;
      int i = 0;
      for (i = 0; i < eventPositionLen; i++) {
        inEventIndicesPtr[i] = ProcessingUtil.eventPosition[i];
        inEventPositionPtr[i] = inEventPositionPtr[i + 1];
      }
      inEventPositionPtr[i] = inEventPositionPtr[i + 1];
      
      // print("inEventPositionPtr: $inEventPositionPtr");
      for (int i = eventPositionLen; i < tempCurrentEvent; i++) {
        // print("ZEROING: $eventPositionLen - $tempCurrentEvent");
        inEventIndicesPtr[i] =
            (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
      }
    }
    
  }

  void onEventPositionCalculated() {
    // print("DateTime: ${DateTime.now()} ${_eventPositionList.sublist(0, ProcessingUtil.eventLabels.length)}");
    DraggableGraph.eventMarkersPosition.clear();
    // print("ProcessingUtil.eventLabels.length: ${ProcessingUtil.eventLabels.length} && ${_eventPositionList.length}");
    if (ProcessingUtil.eventLabels.isNotEmpty) {
      DraggableGraph.eventMarkersPosition.addAll(_eventPositionList.sublist(0, ProcessingUtil.eventLabels.length));
    }
  }

  void onDrawingBufferAllocated(List<Int16List> dataBufferList,
      Int16List countBufferList, final channelCount) {
    // print("onDrawingBufferAllocated");
    // print(dataBufferList[0].runtimeType);
    // print(Int16List.fromList(dataBufferList[0]).length);
    // print(countBufferList.length);
    // print(countBufferList);
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
