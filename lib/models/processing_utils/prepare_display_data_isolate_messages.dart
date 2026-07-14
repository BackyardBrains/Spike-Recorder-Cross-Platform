import 'dart:isolate';
import 'dart:typed_data';

/// Request to prepare display data in a background isolate.
class PrepareDisplayDataRequest {
  final int requestId;
  final int drawSurfaceWidth;
  final int channelCount;
  final int startPositionIdx;
  final int endPositionIdx;
  final int currentEventMarkers;
  final List<int> inEventIndices;
  final List<int> eventLabels;
  final List<int> eventPosition;

  PrepareDisplayDataRequest({
    required this.requestId,
    required this.drawSurfaceWidth,
    required this.channelCount,
    required this.startPositionIdx,
    required this.endPositionIdx,
    required this.currentEventMarkers,
    required this.inEventIndices,
    required this.eventLabels,
    required this.eventPosition,
  });
}

/// Serializable drawing prep result returned to the main isolate.
class PrepareDisplayDataResult {
  final int requestId;
  final List<Int16List> drawingBuffers;
  final List<int> drawingBufferCounts;
  final List<double> eventMarkerPositions;

  PrepareDisplayDataResult({
    required this.requestId,
    required this.drawingBuffers,
    required this.drawingBufferCounts,
    required this.eventMarkerPositions,
  });
}

class PrepareDisplayDataShutdown {}

class PrepareDisplayDataIsolateReady {
  final SendPort workerCommandPort;
  PrepareDisplayDataIsolateReady(this.workerCommandPort);
}

/// Insert microphone PCM into the native circular buffer (point B: awaited).
class InsertMicrophoneDataRequest {
  final int requestId;
  final Uint8List data;
  final int channelCount;

  InsertMicrophoneDataRequest({
    required this.requestId,
    required this.data,
    required this.channelCount,
  });
}

class InsertMicrophoneDataResult {
  final int requestId;
  final int status;
  final List<Int16List> channels;
  final int frameCount;

  InsertMicrophoneDataResult({
    required this.requestId,
    required this.status,
    required this.channels,
    required this.frameCount,
  });
}

/// Insert serial UART bytes into the native circular buffer (point B: awaited).
class InsertSerialDataRequest {
  final int requestId;
  final Uint8List data;
  final int channelCount;
  final int deviceType;
  final int drawSurfaceWidth;

  InsertSerialDataRequest({
    required this.requestId,
    required this.data,
    required this.channelCount,
    required this.deviceType,
    required this.drawSurfaceWidth,
  });
}

class InsertSerialDataResult {
  final int requestId;
  final int status;
  final List<Int16List> channels;
  /// Decoded frames from native outSampleCounts (not raw bytes / channelCount).
  final int frameCount;

  InsertSerialDataResult({
    required this.requestId,
    required this.status,
    required this.channels,
    required this.frameCount,
  });
}
