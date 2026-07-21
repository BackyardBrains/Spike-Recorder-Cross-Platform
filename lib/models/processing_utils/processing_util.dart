import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:spikerbox_architecture/models/CircularFloatArrayBuffer.dart';
import 'package:spikerbox_architecture/models/FftDrawBuffer.dart';
import 'package:spikerbox_architecture/models/default_config_model.dart';
import 'package:spikerbox_architecture/provider/graph_stream_data.dart';
import 'package:spikerbox_architecture/widget/fft_painter.dart';
// import 'dart:ffi';

// Conditional export based on platform
export 'processing_util_native.dart'
    if (dart.library.html) 'processing_util_web.dart';


/// One peak found by [ProcessingUtil.findSampleSpike] (Schmitt-trigger
/// positive or negative peak at sample [index] with amplitude [value]).
class DetectedSpike {
  const DetectedSpike({required this.index, required this.value});
  final int index;
  final int value;
}

// The abstract interface all implementations must follow
abstract class ProcessingUtil {
  /// Web only: worker posts processed PCM chunks after WASM processing.
  static void Function(List<Int16List> chunks)? webLivePlaybackListener;

  static int positionIndex = 0;
  // Maximum display time in seconds
  static const double MAX_DISPLAY_SECONDS = 10.0;
  static const int MAX_EVENT_MARKERS = 2000;
  static int currentEventMarkers = 0;
  static int fromSample = 0;
  static int toSample = 0;

  // Data buffer to store processed audio data (channels × samples)
  // var currentDataBuffer;

  static List<Int16List> drawingBuffers = [];
  static List<int> drawingBufferCounts = [];
  // Pointer<Pointer<Int16>>? currentDataBuffer;
  static ValueNotifier<List<int>> eventMarkerNotifier = ValueNotifier([0,0]);
  static ValueNotifier<int> initializeDevice = ValueNotifier(-100);
  static List<int> eventLabels = [];
  static List<int> eventPosition = [];
  int thresholdingArraylength = 1;

  static int fromDrawingIdx = 0;
  static int toDrawingIdx = 0;

  Future<bool> init();

  // Initialize microphone with specific settings
  Future<bool> initializeMicrophone(
      int channelCount, int sampleRate, double drawSurfaceWidth);
  
  
  void setAveragedSampleCount(int avgSampleCount);
  void setSelectedChannel(int selectedChannel);
  void setThreshold(double thresholdValue);

  void initThreshold(int channelCount, int sampleRate, double drawSurfaceWidth);
  /// Clears native threshold averaging buffers only; does not change threshold level.
  void resetThresholdBuffer();
  // List<int> processThresholdData(Uint8List data, int drawSurfaceWidth, int selectedChannel, bool isAverageSamples);
  List<int> processThresholdData(List<Int16List> data, int thresholdChannelCount, int drawSurfaceWidth, int selectedChannel, bool isAverageSamples);
  // List<Int16List> processMicrophoneData(Uint8List data, bool isAverageSamples, bool isThresholdingButton, int drawSurfaceWidth, int selectedChannel);
  Future<List<Int16List>> processMicrophoneData(Uint8List data);
  List<Int16List> prepareDisplayMicrophoneData(
      List<Int16List> data,
      int drawSurfaceWidth,
      int channelCount,
      double displayTimeMs,
      GraphDataProvider provider,
      int startPositionIdx,
      int endPositionIdx);

  // Prepare signal data for drawing
  int prepareForSignalDrawingProcess(
      // Pointer<Pointer<Int16>> outSamples,
      // Pointer<Int32> outSampleCounts,
      // Pointer<Float> outEventIndices,
      // Pointer<Int32> outEventCount,
      // Pointer<Int32> inEventIndices,
      outSamples,
      outSampleCounts,
      outEventIndices,
      outEventCount,
      inEventIndices,
      int inEventCount,
      int fromSample,
      int toSample,
      int drawSurfaceWidth);


  int prepareForFftDrawing(int windowCount, int windowSize, int targetWindowCount, double width, double height);
  // Set band filter
  Future<int> setBandFilter(int channelIdx, double lowCutOffFreq, double highCutOffFreq);

  // Set notch filter
  Future<int> setNotchFilter(double centerFreq);

  Future<int> setChannelFilterEnabled(int channel, bool enabled);

  Map<String, dynamic> getInformation();
  void initializeSerial(Board board, double drawSurfaceWidth);
  Future<List<Int16List>> processSerialData(Uint8List samples, int displayTimeMs,
      int deviceType, int drawSurfaceWidth, GraphDataProvider provider);
  Future<Uint8List> processDisplaySerialData(
      int displayTimeMs,
      int deviceType,
      int drawSurfaceWidth,
      GraphDataProvider provider,
      int startPositionIdx,
      int endPositionIdx);
  // Future<int> processSerialDataIsolate(List<dynamic> args);
  // Future<Uint8List> displaySerialDataIsolate(List<dynamic> args);
  void processSerialDataIsolate(sendPort);
  void processDisplaySerialDataIsolate(sendPort);

  void setThresholdTriggerType(int eventThresholdTriggeredType) {}

  void setIsThresholding(bool bool);


  List<Float32List> out_fft = [];
  List<int> window_count = [];
  List<int> window_size = [];
  void processFftMicrophoneData(List<Int16List> in_samples, List<int> windowCount, List<int> windowSize, List<int> in_sample_counts, int channelCount);
  void onCallbackPrepareFftDrawingWeb(int resultFftDraw, int selectedChannelIdx);

  CircularFloatArrayBuffer fftBuffer = CircularFloatArrayBuffer(500, 500);
  static FftDrawData? fftDrawData;
  static FftDrawBuffer? fftDrawBuffer;
  static List<int> medianChannelValueAdjuster = [];

  Future<bool> initWithConfig(Int32List config);

  void processingNwbFileInjectData(Int16List data, Int32List sampleCounts, int selectedChannel, int channelCount);
  void processingSerialDataResult(Int16List data, Int32List sampleCounts, int channelCount);

  /// Runs native `processing_find_sample_spike` (Schmitt peak finder) on a
  /// single planar channel. Returns positive + negative peaks sorted by index.
  /// Empty when the buffer is too short (< ~0.2 s) or detection fails.
  List<DetectedSpike> findSampleSpike(Int16List planarChannelSamples, int sampleRateHz);

  void setupDartCallbacks();
  void cleanupDartCallbacks();

  /// Overwrites the current event marker state from a fully-computed set of
  /// (label, position) pairs, where each position is a raw sample offset
  /// within the [MAX_DISPLAY_SECONDS] * sampleRate display window (0 = left
  /// edge/oldest, sampleRate * MAX_DISPLAY_SECONDS = right edge/newest).
  ///
  /// Used for loaded-file playback/scrubbing, where the correct marker
  /// positions are derived from the absolute sample position in the file
  /// (driven by the scrub/playback position) rather than incrementally aged
  /// frame-by-frame like realtime markers.
  void setLoadedFileEventMarkers(List<int> labels, List<int> positions);

  /// Ages the current event marker positions by [frameCount] samples,
  /// shifting them toward the left edge (0 = about to scroll off screen)
  /// exactly like the realtime mic/serial pipelines do internally.
  ///
  /// [processMicrophoneData]/[processSerialData] already do this as a
  /// side effect of decoding, but [processingSerialDataResult] (used to
  /// paint already-decoded samples, e.g. loaded-file playback ticks when
  /// live audio monitoring is off) does not touch event marker state at
  /// all. Callers driving playback through that path must call this once
  /// per tick with the number of samples just advanced, or markers will
  /// appear frozen during playback.
  void advanceEventMarkers(int frameCount);

  int defaultChannelCountNoExpansionBoard = -1;
  int defaultSampleRateNoExpansionBoard = -1;

  StreamController<int> postChannelCountController = StreamController<int>();
  Stream<int>? postChannelCountStream;
  

}
