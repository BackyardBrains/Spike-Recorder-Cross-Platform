import 'dart:async';
import 'dart:convert';
// import 'dart:ffi';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';
// import 'dart:ffi';
import 'package:spikerbox_architecture/models/CircularFloatArrayBuffer.dart';
import 'package:spikerbox_architecture/models/FftDrawBuffer.dart';
import 'package:spikerbox_architecture/models/default_config_model.dart';
import 'package:spikerbox_architecture/provider/graph_stream_data.dart';
import 'package:spikerbox_architecture/screen/graph_template.dart';
import 'package:spikerbox_architecture/screen/spiker_box_ui.dart';
import 'package:spikerbox_architecture/widget/fft_painter.dart';

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
  int defaultChannelCountNoExpansionBoard = -1;
  @override
  int defaultSampleRateNoExpansionBoard = -1;

  int _recordedSampleCount = 0;
  int _lastRecordingState = 0;
  double currentEventSecond = 0.0;

  void _accumulateRecordedSamples(int frameCount) {
    final recordingState = DraggableGraph.isRecording;
    if (recordingState == 1 && _lastRecordingState != 1) {
      _recordedSampleCount = 0;
      currentEventSecond = 0.0;
    }
    _lastRecordingState = recordingState;
    if (recordingState != 1 || frameCount <= 0) return;
    _recordedSampleCount += frameCount;
    currentEventSecond =
        _sampleRate > 0 ? _recordedSampleCount / _sampleRate : 0.0;
  }


  @override
  Future<bool> init() async {

    js.context['onEventPositionAllocated'] = onEventPositionAllocated;
    js.context['onEventPositionCalculated'] = onEventPositionCalculated;
    js.context['onEventFound'] = onEventFound;
    js.context['onSerialParsedCallback'] = onSerialParsedCallback;
    js.context['onDrawingBufferAllocated'] = onDrawingBufferAllocated;
    js.context['onThresholdProcessCallback'] = onThresholdProcessCallback;
    js.context['onSendingFftBuffer'] = onSendingFftBuffer;
    js.context['onWebLivePlayback'] = onWebLivePlayback;
    // initFft();
    _isInitialized = true;
    return true;
  }
  void onSendingFftBuffer( 
    // List<Float32List> out_fft_data, Int16List out_window_count, Int16List out_window_size, Int16List out_frequency_counter, Int16List inSamples, Int16List inSampleCounts,
    List<Float32List> out_fft_data, Int32List out_window_count, Int32List out_window_size, Int32List out_frequency_counter, 
    Float32List out_fft_vertices, Int16List out_fft_indices, Float32List out_fft_colors, Int32List out_fft_vertex_count, Int32List out_fft_index_count, Int32List out_fft_color_count 
  ) {
    print("INIT FFT BUFFER SENDING vertices:${this.out_fft_indices != null} indices:${out_fft_colors != null} colors:${out_fft_vertex_count != null} vertex_count:${out_fft_index_count != null} index_count:${out_fft_color_count != null} color_count:${out_fft_data != null}");

    this.out_fft_data = out_fft_data;
    this.out_window_count = out_window_count;
    this.out_window_size = out_window_size;
    this.out_frequency_counter = out_frequency_counter;

    this.out_fft_vertices = out_fft_vertices;
    this.out_fft_indices = out_fft_indices;
    this.out_fft_colors = out_fft_colors;
    this.out_fft_vertex_count = out_fft_vertex_count;
    this.out_fft_index_count = out_fft_index_count;
    this.out_fft_color_count = out_fft_color_count;

  }
  
  void onThresholdProcessCallback( int frameCount ) {
    thresholdingArraylength = frameCount;
  }
  @override
  Future<bool> initializeMicrophone(
      int channelCount, int sampleRate, double drawSurfaceWidth) async {
    print("initializeMicrophoneWeb: $channelCount, $sampleRate, $drawSurfaceWidth");
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
  Future<List<Int16List>> processMicrophoneData(Uint8List data) async {
    if (data.isEmpty) return [Int16List(0)];

    // Always forward mic PCM to the WASM worker (graph + live playback on web).
    if (!isAllocated) {
      js.context.callMethod("processMicrophoneDataWeb", [
        data,
        0,
        data.length,
        json.encode(ProcessingUtil.eventLabels),
        json.encode(ProcessingUtil.eventPosition),
      ]);
      return [Int16List(0)];
    }

    int frameCount = (data.length / 2).floor();
    _accumulateRecordedSamples(frameCount);
    _shiftEventMarkersForInsertedFrames(frameCount);

    js.context.callMethod("processMicrophoneDataWeb", [
      data,
      0,
      data.length,
      json.encode(ProcessingUtil.eventLabels),
      json.encode(ProcessingUtil.eventPosition)
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
  Future<int> setBandFilter(int channelIdx, double lowCutOffFreq, double highCutOffFreq) async {
    js.context.callMethod("setBandFilterWeb", [channelIdx, lowCutOffFreq, highCutOffFreq]);
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
    ProcessingUtil.fromDrawingIdx = startPositionIdx;
    ProcessingUtil.toDrawingIdx = endPositionIdx;

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

  @override
  void setLoadedFileEventMarkers(List<int> labels, List<int> positions) {
    if (inEventIndicesPtr.isEmpty || inEventLabelsPtr.isEmpty) {
      initEventMarkers(_sampleRate);
    }

    final count = labels.length < ProcessingUtil.MAX_EVENT_MARKERS
        ? labels.length
        : ProcessingUtil.MAX_EVENT_MARKERS;
    ProcessingUtil.eventLabels
      ..clear()
      ..addAll(labels.take(count));
    ProcessingUtil.eventPosition
      ..clear()
      ..addAll(positions.take(count));

    for (int i = 0; i < count; i++) {
      inEventLabelsPtr[i] = labels[i];
      inEventIndicesPtr[i] = positions[i];
    }
    ProcessingUtil.currentEventMarkers = count;
  }

  @override
  void advanceEventMarkers(int frameCount) {
    _shiftEventMarkersForInsertedFrames(frameCount);
  }

  /// Ages [inEventIndicesPtr]/[ProcessingUtil.eventPosition] by [frameCount]
  /// samples, dropping markers that have scrolled past the left edge.
  /// Shared by [processMicrophoneData] (mic path) and [advanceEventMarkers]
  /// (used by callers that paint already-decoded samples directly, e.g.
  /// loaded-file playback ticks with live audio monitoring off).
  void _shiftEventMarkersForInsertedFrames(int frameCount) {
    if (frameCount <= 0 || inEventIndicesPtr.isEmpty) return;

    int removedIndicesCount = 0;
    for (int i = 0; i < ProcessingUtil.currentEventMarkers; i++) {
      if (inEventIndicesPtr[i] - frameCount > 0) {
        inEventIndicesPtr[i] -= frameCount;
        ProcessingUtil.eventPosition[i] = inEventIndicesPtr[i];
      } else {
        if (inEventIndicesPtr[i] != -1) {
          removedIndicesCount++;
          inEventIndicesPtr[i] = -1;
        }
      }
    }
    for (int i = 0; i < removedIndicesCount; i++) {
      if (inEventIndicesPtr[i] == -1) {
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
      for (int i = eventPositionLen; i < tempCurrentEvent; i++) {
        inEventIndicesPtr[i] =
            (ProcessingUtil.MAX_DISPLAY_SECONDS * _sampleRate).floor();
      }
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
      if (DraggableGraph.isRecording == 1) {
        GraphTemplate.nwbFileUtil?.addEvent(currentEventSecond, list[0]);
      }
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
    channelCount = int.parse(board.maxNumberOfChannels!);
    sampleRate = int.parse(board.maxSampleRate!);
    _sampleRate = sampleRate;
    packetLen = sampleRate * MAX_DISPLAY_SECONDS;


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

  /// Latest DISPLAY args when a paint is requested while one is already in flight.
  int _pendingDisplayTimeMs = 0;
  int _pendingDisplayDeviceType = 0;
  int _pendingDisplayDeviceWidth = 0;
  int _pendingDisplayStartIdx = 0;
  int _pendingDisplayEndIdx = 0;
  bool _webSerialDisplayInFlight = false;
  bool _webSerialDisplayCoalesce = false;

  @override
  Future<List<Int16List>> processSerialData(Uint8List samples, int displayTimeMs,
      int deviceType, int deviceWidth, GraphDataProvider provider) async {
    // var jsSamples = samples.toList();
    js.context.callMethod(
        "processSerialDataWeb", [
          samples, displayTimeMs, deviceType,
          json.encode(ProcessingUtil.eventLabels),
          json.encode(ProcessingUtil.eventPosition)
        ]);
    // Paint gating uses [ProcessingUtil.webSerialFramesIngestedListener] with the
    // real WASM frame count. Returning an empty channel avoids the old Int16List(1)
    // stub that treated every UART chunk as one sample.
    return Future.value([Int16List(0)]);
  }

  @override
  Future<Uint8List> processDisplaySerialData(
      int displayTimeMs,
      int deviceType,
      int deviceWidth,
      GraphDataProvider provider,
      startPositionIdx,
      endPositionIdx) async {
    _pendingDisplayTimeMs = displayTimeMs;
    _pendingDisplayDeviceType = deviceType;
    _pendingDisplayDeviceWidth = deviceWidth;
    _pendingDisplayStartIdx = (startPositionIdx as num).toInt();
    _pendingDisplayEndIdx = (endPositionIdx as num).toInt();

    if (_webSerialDisplayInFlight) {
      // Keep only the latest window; drop intermediate DISPLAY messages.
      _webSerialDisplayCoalesce = true;
      return Future.value(Uint8List(0));
    }
    _postWebSerialDisplay();
    return Future.value(Uint8List(0));
  }

  void _postWebSerialDisplay() {
    _webSerialDisplayInFlight = true;
    _webSerialDisplayCoalesce = false;
    js.context.callMethod("displaySerialDataWeb", [
      _pendingDisplayTimeMs,
      _pendingDisplayDeviceType,
      _pendingDisplayDeviceWidth,
      _pendingDisplayStartIdx,
      _pendingDisplayEndIdx,
      json.encode(ProcessingUtil.eventLabels),
      json.encode(ProcessingUtil.eventPosition)
    ]);
  }

  @override
  void notifyWebSerialDisplayFinished() {
    if (_webSerialDisplayCoalesce) {
      _postWebSerialDisplay();
      return;
    }
    _webSerialDisplayInFlight = false;
    ProcessingUtil.webSerialDisplayReadyListener?.call();
  }

  @override
  void resetWebSerialDisplayState() {
    _webSerialDisplayInFlight = false;
    _webSerialDisplayCoalesce = false;
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
    ProcessingUtil.eventMarkerNotifier.value = [eventLabel, -1];
    // ProcessingUtil.eventMarkerNotifier.value = [-1, -1];
    
  }
  void onSerialParsedCallback(frameCount) {
    final frames = frameCount is int
        ? frameCount
        : (frameCount is num ? frameCount.toInt() : 0);
    // print("onSerialParsedCallback: ${inEventIndicesPtr[0]} - $frames");
    if (frames > 0) {
      ProcessingUtil.webSerialFramesIngestedListener?.call(frames);
    }
    _accumulateRecordedSamples(frames);
    int removedIndicesCount = 0;
    for (int i = 0; i < ProcessingUtil.currentEventMarkers; i++) {
      if (inEventIndicesPtr[i] - frames > 0) {
        inEventIndicesPtr[i] -= frames;
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

    DraggableGraph.eventMarkersLabels.clear();
    int len = ProcessingUtil.eventLabels.length;
    if (len > ProcessingUtil.eventPosition.length) {
      len = ProcessingUtil.eventPosition.length;
    }
    int startPositionIdx = DraggableGraph.startPositionIdx;
    int endPositionIdx = DraggableGraph.endPositionIdx;
    for (int i = 0; i < len; i++) {
      // print("RANGE : $startPositionIdx - $endPositionIdx");
      if (ProcessingUtil.eventPosition[i] >= startPositionIdx && ProcessingUtil.eventPosition[i] <= endPositionIdx ) {
        DraggableGraph.eventMarkersLabels.add(ProcessingUtil.eventLabels[i]);
      }
    }
  }

  void onDrawingBufferAllocated(List<Int16List> dataBufferList,
      Int16List countBufferList, final channelCount) {
    print("onDrawingBufferAllocated - channel count: ${channelCount}");
    print("OnDrawingBufferAllocated - dataBufferList: ${dataBufferList.length}");
    ProcessingUtil.medianChannelValueAdjuster = List.generate(channelCount, (_) => 0);    
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
  
  @override
  List<int> processThresholdData(List<Int16List> data, int thresholdChannelCount, int drawSurfaceWidth, int selectedChannel, bool isAverageSamples) {
    return [];
  }
  
  @override
  void initThreshold(int channelCount, int sampleRate, double drawSurfaceWidth) {
    js.context.callMethod("initThreshold", [channelCount, sampleRate, drawSurfaceWidth]);
  }
  
  @override
  void setAveragedSampleCount(int avgSampleCount) {
    js.context.callMethod("setAveragedSampleCount", [avgSampleCount]);
  }

  @override
  void setSelectedChannel(int selectedChannel) {
    if (js.context.hasProperty("setSelectedChannel")) {
      js.context.callMethod("setSelectedChannel", [selectedChannel]);
    }
  }
  
  @override
  void setThreshold(double thresholdValue) {
    js.context.callMethod("setThreshold", [thresholdValue]);
  }
  
  @override
  void setIsThresholding(bool flag) {
    js.context.callMethod("setIsThresholding", [flag]);    
  }

  @override
  void resetThresholdBuffer() {}
  
  @override
  void setThresholdTriggerType(int eventThresholdTriggeredType) {
    js.context.callMethod("setThresholdTriggerType", [eventThresholdTriggeredType]);    
  }

  @override
  int thresholdingArraylength = 0;
  
  @override
  List<Float32List> out_fft = [];
  
  @override
  List<int> window_count = [];
  
  @override
  List<int> window_size = [];

  List<List<double>>? out_fft_data;
  Int32List? out_window_count;
  Int32List? out_window_size;
  Int32List? out_frequency_counter;

  Float32List? out_fft_vertices;
  Int16List? out_fft_indices;
  Float32List? out_fft_colors;
  Int32List? out_fft_vertex_count;
  Int32List? out_fft_index_count;
  Int32List? out_fft_color_count;
  List<Float32List> fft = List.generate(500, (idx)=>Float32List(500));

  @override
  CircularFloatArrayBuffer fftBuffer = CircularFloatArrayBuffer(500, 500);
  

  Int32List convertRgbaFloat32ListToInt32(Float32List fftColorList, Int32List outColorList) {
    // Ensure the input list has a multiple of 4 elements (R, G, B, A).
    if (fftColorList.length % 4 != 0) {
      print("The RGBA color list must have a length that is a multiple of 4.");
      // throw ArgumentError('The RGBA color list must have a length that is a multiple of 4.');
    }

    final int colorCount = fftColorList.length ~/ 4;

    for (int i = 0; i < colorCount; i++) {
      // Read the four float components (R, G, B, A)
      double R = fftColorList[i * 4];
      double G = fftColorList[i * 4 + 1];
      double B = fftColorList[i * 4 + 2];
      double A = fftColorList[i * 4 + 3];
      
      int r = (R * 255).round();
      int g = (G * 255).round();
      int b = (B * 255).round();
      int a = (A * 255).round();   
      outColorList[i] = (a << 24) | (r << 16) | (g << 8) | b;
    }

    return outColorList;
  }  


  @override
  int prepareForFftDrawing(int windowCount, int windowSize, int targetWindowCount, double width, double height){
    // return 0;

      // print("FFT DRAWING out_fft_vertices: ${out_fft_vertices!=null}| indices:${this.out_fft_indices != null} colors:${out_fft_colors != null} vertexCount:${out_fft_vertex_count != null} IndexCount:${out_fft_index_count != null} Color Count:${out_fft_color_count != null} outfftData:${out_fft_data != null}");
    if (out_fft_vertices != null && out_fft_indices != null && out_fft_colors != null 
        && out_fft_vertex_count != null && out_fft_index_count != null && out_fft_color_count != null 
          && out_fft_data != null){

      // print("PREPARE FFT DRAWING : ${windowCount} -- ${windowSize} ||| ${width} ___ ${height}");
      // print("PREPARE FFT DRAWING : ${fft}");
      // if (out_fft_color_count![0] != 0) {
        int selectedChannelIdx = 0;
        // int maxWindowCount = out_fft.length;
        int count = fftBuffer.get(fft);
        // print("BUFFER COUNT : ${count}");

        if (count > 0) {
          // print("FFT BUFFER GET COUNT: $count");
          ProcessingUtil.fftDrawBuffer!.add(fft, count);

          // Pointer<Pointer<Float>> drawBuffer = calloc<Pointer<Float>>(windowCount);
          List<List<double>> drawBuffer = List.generate(windowCount, (_) => []);
          try{
            int len = ProcessingUtil.fftDrawBuffer!.buffer[0].length;
            for (int i = 0; i < windowCount; i++) {
              List<double> temp = List.generate(len, (_) => -1);
              temp.setAll(0, ProcessingUtil.fftDrawBuffer!.buffer[i]);
              drawBuffer[i] = temp;
            }
            js.context.callMethod("prepareFftDrawing", [
              drawBuffer,
              selectedChannelIdx,
              windowCount,
              windowSize,
              targetWindowCount,
              width,
              height
            ]);

          }catch(err){
            print("err $err");
          }

          // int vertexCount = out_fft_vertex_count![selectedChannelIdx];
          // int indicesCountRaw = out_fft_index_count![selectedChannelIdx];
          // int indicesCount = indicesCountRaw;
          // int colorCountRaw = out_fft_color_count![selectedChannelIdx];
          // int colorCount = out_fft_color_count![selectedChannelIdx] ~/ 4;
          // Int32List colorList = Int32List(colorCount);
          // Float32List fftColorList = Float32List.fromList(out_fft_colors!);
          // Int16List indicesList = Int16List.fromList(out_fft_indices!);

          // convertRgbaFloat32ListToInt32(fftColorList, colorList);
          
          // ProcessingUtil.fftDrawData = FftDrawData(
          //     vertices: Float32List.fromList(out_fft_vertices!), colors: colorList, 
          //     indices: Uint16List.fromList(out_fft_indices!), 
          //     vertexCount: vertexCount, 
          //     colorCount: colorList.length, 
          //     indexCount: indicesCount, 
          //     scaleX: 1, scaleY: 1);          
        }
    }
    return 0;
  }
  
  void initFft() {
    print("INIT FFT000");
    int windowCount = ( (10.0 * 128) / (512 * 0.01).floor() ).floor();
    int windowSize = ( (32 * 4) ).floor();

    // out_fft_vertices = List<double>.generate(windowCount * windowSize * 2, (_) => 0);
    // out_fft_indices = List<int>.generate(windowCount * windowSize * 6, (_) => 0);
    // out_fft_colors = List<double>.generate(windowCount * windowSize * 4, (_) => 0);
    int selectedChannel = 0;
    js.context.callMethod("initFft", [windowCount, windowSize, channelCount, selectedChannel]);
    ProcessingUtil.fftDrawBuffer = FftDrawBuffer(windowCount, windowSize);
  }

  
  @override
  void processFftMicrophoneData(List<Int16List> in_samples, List<int> windowCount, List<int> windowSize, List<int> in_sample_counts, int channelCount) async {
    // print("processFftMicrophoneData EXIST");
    int selectedChannel = 0;
    int signs = -1;

    if (windowCount.isNotEmpty) {
      window_count.clear();
      window_count.addAll(windowCount);
      window_size.clear();
      window_size.addAll(windowSize);
    }
    if (out_fft.isEmpty) {
      print("FFT DATA POINTER EXIST??  out fft data : ${out_fft_data == null}");
      out_fft.clear();
      out_fft = List<Float32List>.generate(windowCount[selectedChannel], (idx)=> Float32List(windowSize[selectedChannel]));
    }

    // List<Int32List> inSamples = List.generate(channelCount, (_) => Int32List(0));
    // // print("inSamples: ${in_sample_counts}");

    // for (int i = 0; i < channelCount; i++) {
    //   int sampleCount = in_sample_counts[i];
    //   inSamples[i] = Int32List(sampleCount);
    //   signs = signs * -1;
    //   for (int j = 0; j < sampleCount; j++) {
    //     inSamples[i][j] = in_samples[i][j];
    //     // inSamples[i][j] = (Random().nextInt(100) + 100) * signs;
    //   }
    // }
    // print("inSamples: ${inSamples[0].length}");

    js.context.callMethod("processFftMicrophoneData", [
      channelCount,
      selectedChannel,
      windowCount,
      windowSize,
      in_samples,
      in_sample_counts,
    ]);

    // Pointer<Int32> inSampleCounts = calloc<Int32>(channelCount);
    // List<int> inSampleCounts = List<int>.generate(channelCount, (_) => 0);
    // for (int i = 0; i < channelCount; i++) {
    //   inSampleCounts[i] = in_sample_counts[i];
    // }


    // window_count.setAll(0, out_window_count!.toList());
    // window_size.setAll(0, out_window_size!.toList());

    // if (window_count[0] > 0) {
    //   int windowCounter = out_window_count![selectedChannel];
    //   for (int i = 0; i < windowCounter; i++) {
    //     int outSize = out_window_count![0];
    //     Float32List out_fft_list = Float32List.fromList(out_fft_data![i]);
    //     out_fft[i].setAll(0, out_fft_list);
    //     fftBuffer.put(out_fft, 0, windowCounter);
    //   }
    // }

    // inSamples.clear();

    // (out_window_count!).clear();
    // (out_window_size!).clear();
    // (out_frequency_counter!).clear();
    // (inSampleCounts).clear();

  }
  
  @override
  void onCallbackPrepareFftDrawingWeb(int resultFftDraw, int selectedChannelIdx) {
    int vertexCount = out_fft_vertex_count![selectedChannelIdx];
    int indicesCountRaw = out_fft_index_count![selectedChannelIdx];
    int indicesCount = indicesCountRaw;
    int colorCountRaw = out_fft_color_count![selectedChannelIdx];
    int colorCount = out_fft_color_count![selectedChannelIdx] ~/ 4;

    Int32List colorList = Int32List(colorCount);
    // Counter: 65536, 194310, 32768
    // Counter: 65536, 194310, 32768 | 131072 194310
    // print("out_fft_vertices: $out_fft_vertices");
    Float32List fftColorList = Float32List.fromList(out_fft_colors!.sublist(0, colorCountRaw));
    // Int16List indicesList = Int16List.fromList(out_fft_indices!.sublist(0, indicesCountRaw));
    // vertexCount = 2x indicesCountRaw
    // print("Counter: $vertexCount, $indicesCount, $colorCount | $colorCountRaw $indicesCountRaw");

    convertRgbaFloat32ListToInt32(fftColorList, colorList);
    ProcessingUtil.fftDrawData = FftDrawData(
        vertices: Float32List.fromList(out_fft_vertices!.sublist(0, vertexCount)), colors: colorList, 
        indices: Uint16List.fromList(out_fft_indices!.sublist(0, indicesCount)), 
        vertexCount: vertexCount, 
        colorCount: colorList.length, 
        indexCount: indicesCount, 
        scaleX: 1, scaleY: 1);
  }
  
  @override
  Future<bool> initWithConfig(Int32List config) {
    // TODO: implement initWithConfig
    // throw UnimplementedError();
    print("initWithConfig dart: $config ---");
    // Pass a plain JS Int32Array-friendly copy. Posting the Dart Int32List
    // wrapper as `{o: …}` made the worker read channelCount as undefined,
    // leave the circular buffer at 1 channel, and drop ch1+ on scrub.
    js.context.callMethod("initWithConfig", [Int32List.fromList(config)]);
    _sampleRate = config[0].toInt();
    channelCount = config[1].toInt();
    ProcessingUtil.medianChannelValueAdjuster = List.generate(channelCount, (_) => 0);
    // _channelCount = config[1].toInt();

    int drawSurfaceWidth = config[7].toInt();
    
    if (ProcessingUtil.drawingBuffers != null) {
      try{

        // ProcessingUtil.drawingBuffers.clear();
        // // if (ProcessingUtil.drawingBufferCounts != null) {
        // //   ProcessingUtil.drawingBufferCounts.clear();
        // // } else {
        // //   ProcessingUtil.drawingBufferCounts = [];
        // // }
        
        // for (int i = 0; i < channelCount; i++) {
        //   try{
        //     ProcessingUtil.drawingBuffers
        //         .add(Int16List(drawSurfaceWidth.toInt() * 5));
        //   }catch(err) {
        //     print("ERR2 processing util : $err");
        //   }
          
        //   ProcessingUtil.drawingBufferCounts[i] = drawSurfaceWidth.toInt() * 5;
        //   // if (ProcessingUtil.drawingBufferCounts.length < i + 1) {
        //   //   ProcessingUtil.drawingBufferCounts[i] = (drawSurfaceWidth.toInt() * 5);
        //   // } else {
        //   //   ProcessingUtil.drawingBufferCounts.add(drawSurfaceWidth.toInt() * 5);
        //   // }
        // }
      }catch(err) {
        print("ERR processing util : $err");
      }
    }

    return Future.value(true);
  }
  
  @override
  void processingNwbFileInjectData(Int16List data, Int32List sampleCounts, int selectedChannel, int channelCount) {
    // TODO: implement processingNwbFileInjectData
  }
  
  @override
  void processingSerialDataResult(Int16List convertedData, Int32List sampleCounts, int channelCount) {

    js.context.callMethod("processSerialDataWebResult", [
      Int16List.fromList(convertedData),
      Int32List.fromList(sampleCounts),
      channelCount,
      json.encode(ProcessingUtil.eventLabels),
      json.encode(ProcessingUtil.eventPosition)
    ]);
  }
  
  @override
  void cleanupDartCallbacks() {
  }
  
  @override
  void setupDartCallbacks() {
    js.context['onWebLivePlayback'] = onWebLivePlayback;
    js.context['onSerialParsedCallback'] = onSerialParsedCallback;
  }

  void onWebLivePlayback(channelData) {
    final listener = ProcessingUtil.webLivePlaybackListener;
    if (listener == null || channelData == null) return;

    final channels = <Int16List>[];
    if (channelData is List) {
      for (final ch in channelData) {
        final converted = _jsChannelToInt16List(ch);
        if (converted != null && converted.isNotEmpty) {
          channels.add(converted);
        }
      }
    } else {
      final converted = _jsChannelToInt16List(channelData);
      if (converted != null && converted.isNotEmpty) {
        channels.add(converted);
      }
    }
    if (channels.isEmpty) return;
    listener(channels);
  }

  /// Converts WASM worker [Int16Array] views (and Dart lists) for SoLoud playback.
  Int16List? _jsChannelToInt16List(dynamic ch) {
    if (ch == null) return null;
    if (ch is Int16List) return ch;
    if (ch is TypedData) {
      final byteLen = ch.lengthInBytes;
      if (byteLen < 2 || byteLen.isOdd) return null;
      return ch.buffer.asInt16List(
        ch.offsetInBytes ~/ 2,
        byteLen ~/ 2,
      );
    }
    if (ch is List) {
      if (ch.isEmpty) return null;
      return Int16List.fromList(ch.cast<int>());
    }
    if (ch is js.JsObject) {
      final len = (ch['length'] as num?)?.toInt();
      if (len == null || len <= 0) return null;
      final out = Int16List(len);
      for (var i = 0; i < len; i++) {
        out[i] = (ch[i] as num).toInt();
      }
      return out;
    }
    return null;
  }
  
  @override
  StreamController<int> postChannelCountController = StreamController<int>();
  
  @override
  Stream<int>? postChannelCountStream;

  @override
  List<DetectedSpike> findSampleSpike(
      Int16List planarChannelSamples, int sampleRateHz) {
    // Web worker does not yet expose processing_find_sample_spike; use a
    // Dart Schmitt peak-hold that mirrors the native algorithm closely enough
    // for Spike Analysis markers.
    return _findSampleSpikeDart(planarChannelSamples, sampleRateHz);
  }
}

/// Dart port of SpikeAnalysis::findSampleSpike (SD threshold + Schmitt peaks).
List<DetectedSpike> _findSampleSpikeDart(Int16List samples, int sampleRateHz) {
  if (samples.isEmpty || sampleRateHz <= 0) return const [];
  if (samples.length < (sampleRateHz * 0.2).ceil()) return const [];

  const binCount = 200.0;
  const bufferSizeInSecs = 12.0;
  var bufferSize = (samples.length / binCount).ceil();
  final maxBufferSize = (sampleRateHz * bufferSizeInSecs).ceil();
  if (bufferSize > maxBufferSize) bufferSize = maxBufferSize;
  if (bufferSize < 1) bufferSize = 1;

  final deviations = <double>[];
  for (var offset = 0; offset < samples.length; offset += bufferSize) {
    final end = min(offset + bufferSize, samples.length);
    final n = end - offset;
    if (n <= 0) break;
    var sum = 0.0;
    for (var i = offset; i < end; i++) {
      sum += samples[i];
    }
    final mean = sum / n;
    var acc = 0.0;
    for (var i = offset; i < end; i++) {
      final d = samples[i] - mean;
      acc += d * d;
    }
    deviations.add(sqrt(acc / n));
  }
  if (deviations.isEmpty) return const [];
  deviations.sort((a, b) => b.compareTo(a));
  final sig = (2 * deviations[(deviations.length * 0.4).ceil()
          .clamp(0, deviations.length - 1)])
      .round()
      .clamp(1, 32767);
  final negSig = -sig;

  const killIntervalSec = 0.005;
  final killSamples = max(1, (killIntervalSec * sampleRateHz).round());

  final pos = <DetectedSpike>[];
  final neg = <DetectedSpike>[];
  var schmittPos = false;
  var schmittNeg = false;
  var maxPeakValue = -32768;
  var minPeakValue = 32767;
  var maxPeakIndex = 0;
  var minPeakIndex = 0;

  for (var i = 0; i < samples.length; i++) {
    final sample = samples[i];
    if (!schmittPos) {
      if (sample > sig) {
        schmittPos = true;
        maxPeakValue = -32768;
      }
    } else {
      if (sample < 0) {
        schmittPos = false;
        pos.add(DetectedSpike(index: maxPeakIndex, value: maxPeakValue));
      } else if (sample > maxPeakValue) {
        maxPeakValue = sample;
        maxPeakIndex = i;
      }
    }
    if (!schmittNeg) {
      if (sample < negSig) {
        schmittNeg = true;
        minPeakValue = 32767;
      }
    } else {
      if (sample > 0) {
        schmittNeg = false;
        neg.add(DetectedSpike(index: minPeakIndex, value: minPeakValue));
      } else if (sample < minPeakValue) {
        minPeakValue = sample;
        minPeakIndex = i;
      }
    }
  }

  List<DetectedSpike> applyKill(List<DetectedSpike> train, {required bool positive}) {
    if (train.isEmpty) return train;
    final out = List<DetectedSpike>.from(train);
    for (var i = 0; i < out.length - 1; i++) {
      if ((out[i + 1].index - out[i].index) < killSamples) {
        final keepNext = positive
            ? out[i].value < out[i + 1].value
            : out[i].value > out[i + 1].value;
        if (keepNext) {
          out.removeAt(i);
        } else {
          out.removeAt(i + 1);
        }
        i--;
      }
    }
    return out;
  }

  final filteredPos = applyKill(pos, positive: true);
  final filteredNeg = applyKill(neg, positive: false);
  final spikes = <DetectedSpike>[...filteredPos, ...filteredNeg];
  spikes.sort((a, b) => a.index.compareTo(b.index));
  return spikes;
}

// Factory function to create an instance
ProcessingUtil createProcessingUtil() => ProcessingUtilImpl();
