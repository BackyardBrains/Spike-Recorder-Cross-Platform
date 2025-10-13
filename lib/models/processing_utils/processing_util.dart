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


// The abstract interface all implementations must follow
abstract class ProcessingUtil {
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

  Future<bool> init();

  // Initialize microphone with specific settings
  Future<bool> initializeMicrophone(
      int channelCount, int sampleRate, double drawSurfaceWidth);
  
  
  void setAveragedSampleCount(int avgSampleCount);
  void setThreshold(double thresholdValue);

  void initThreshold(int channelCount, int sampleRate, double drawSurfaceWidth);
  // List<int> processThresholdData(Uint8List data, int drawSurfaceWidth, int selectedChannel, bool isAverageSamples);
  List<int> processThresholdData(List<Int16List> data, int thresholdChannelCount, int drawSurfaceWidth, int selectedChannel, bool isAverageSamples);
  // List<Int16List> processMicrophoneData(Uint8List data, bool isAverageSamples, bool isThresholdingButton, int drawSurfaceWidth, int selectedChannel);
  List<Int16List> processMicrophoneData(Uint8List data);
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
  Future<int> setBandFilter(double lowCutOffFreq, double highCutOffFreq);

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

  Future<bool> initWithConfig(Int32List config);

  void processingNwbFileInjectData(Int16List data, Int32List sampleCounts, int selectedChannel, int channelCount);
}
