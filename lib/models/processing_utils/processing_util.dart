import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:spikerbox_architecture/models/default_config_model.dart';
import 'package:spikerbox_architecture/provider/graph_stream_data.dart';
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

  // Data buffer to store processed audio data (channels × samples)
  // var currentDataBuffer;

  static List<Int16List> drawingBuffers = [];
  static List<int> drawingBufferCounts = [];
  // Pointer<Pointer<Int16>>? currentDataBuffer;
  static ValueNotifier<int> eventMarkerNotifier = ValueNotifier(0);
  static List<int> eventLabels = [];
  static List<int> eventPosition = [];

  Future<bool> init();

  // Initialize microphone with specific settings
  Future<bool> initializeMicrophone(
      int channelCount, int sampleRate, double drawSurfaceWidth);

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

  // Set band filter
  Future<int> setBandFilter(double lowCutOffFreq, double highCutOffFreq);

  // Set notch filter
  Future<int> setNotchFilter(double centerFreq);

  Future<int> setChannelFilterEnabled(int channel, bool enabled);

  Map<String, dynamic> getInformation();
  void initializeSerial(Board board, double drawSurfaceWidth);
  Future<int> processSerialData(Uint8List samples, int displayTimeMs,
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
}
