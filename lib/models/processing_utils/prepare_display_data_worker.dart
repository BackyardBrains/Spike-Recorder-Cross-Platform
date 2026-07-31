import 'dart:ffi';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:ffi/ffi.dart';
import 'package:processing_ffi/processing_ffi.dart' as pb;

import 'prepare_display_data_isolate_messages.dart';
import 'processing_util.dart';

/// Runs [prepareForSignalDrawing] in a background isolate.
PrepareDisplayDataResult prepareDisplayDataIsolate(
    PrepareDisplayDataRequest request) {
  final channelCount = request.channelCount;
  final drawSurfaceWidth = request.drawSurfaceWidth;

  final outSamplesPtr = calloc<Pointer<Int16>>(channelCount);
  for (int i = 0; i < channelCount; i++) {
    outSamplesPtr[i] = calloc<Int16>(drawSurfaceWidth * 5);
  }
  final outSampleCountsPtr = calloc<Int32>(channelCount);
  final outEventIndicesPtr = calloc<Float>(ProcessingUtil.MAX_EVENT_MARKERS);
  final outEventCountPtr = calloc<Int32>(1);
  final inEventIndicesPtr = calloc<Int32>(ProcessingUtil.MAX_EVENT_MARKERS);

  try {
    for (int i = 0; i < request.inEventIndices.length; i++) {
      inEventIndicesPtr[i] = request.inEventIndices[i];
    }

    final result = pb.processingBindings.prepareForSignalDrawing(
      outSamplesPtr,
      outSampleCountsPtr,
      outEventIndicesPtr,
      outEventCountPtr,
      inEventIndicesPtr,
      request.currentEventMarkers,
      request.startPositionIdx,
      request.endPositionIdx,
      drawSurfaceWidth,
    );

    if (result != 0) {
      throw StateError('prepareForSignalDrawing failed: $result');
    }

    final sampleCount = outSampleCountsPtr[0];
    final drawingBuffers = List<Int16List>.generate(
      channelCount,
      (i) => Int16List.fromList(outSamplesPtr[i].asTypedList(sampleCount)),
    );
    final drawingBufferCounts =
        List<int>.generate(channelCount, (i) => outSampleCountsPtr[i]);

    final labelCount = request.eventLabels.length;
    final eventMarkerPositions = outEventIndicesPtr
        .asTypedList(labelCount)
        .map((v) => v.toDouble())
        .toList();

    return PrepareDisplayDataResult(
      requestId: request.requestId,
      drawingBuffers: drawingBuffers,
      drawingBufferCounts: drawingBufferCounts,
      eventMarkerPositions: eventMarkerPositions,
    );
  } finally {
    for (int i = 0; i < channelCount; i++) {
      calloc.free(outSamplesPtr[i]);
    }
    calloc.free(outSamplesPtr);
    calloc.free(outSampleCountsPtr);
    calloc.free(outEventIndicesPtr);
    calloc.free(outEventCountPtr);
    calloc.free(inEventIndicesPtr);
  }
}

/// Runs [processMicrophoneStream] in a background isolate.
InsertMicrophoneDataResult insertMicrophoneDataIsolate(
    InsertMicrophoneDataRequest request) {
  final channelCount = request.channelCount;
  final data = request.data;
  final maxFrames = math.max(1, (data.length / 2).floor());

  final outSamplesPtr = calloc<Pointer<Int16>>(channelCount);
  for (int i = 0; i < channelCount; i++) {
    outSamplesPtr[i] = calloc<Int16>(maxFrames);
  }
  final outSampleCountsPtr = calloc<Int32>(channelCount);
  final inDataPtr = calloc<Uint8>(data.length);

  try {
    inDataPtr.asTypedList(data.length).setAll(0, data);

    final status = pb.processingBindings.processMicrophoneStream(
      outSamplesPtr,
      outSampleCountsPtr,
      inDataPtr,
      data.length,
    );

    if (status != 0) {
      return InsertMicrophoneDataResult(
        requestId: request.requestId,
        status: status,
        channels: List.generate(channelCount, (_) => Int16List(0)),
        frameCount: 0,
      );
    }

    final frameCount = outSampleCountsPtr[0];
    final channels = List<Int16List>.generate(
      channelCount,
      (i) => Int16List.fromList(
        outSamplesPtr[i].asTypedList(outSampleCountsPtr[i]),
      ),
    );

    return InsertMicrophoneDataResult(
      requestId: request.requestId,
      status: status,
      channels: channels,
      frameCount: frameCount,
    );
  } finally {
    for (int i = 0; i < channelCount; i++) {
      calloc.free(outSamplesPtr[i]);
    }
    calloc.free(outSamplesPtr);
    calloc.free(outSampleCountsPtr);
    calloc.free(inDataPtr);
  }
}

/// Runs [processSampleStream] in a background isolate.
InsertSerialDataResult insertSerialDataIsolate(InsertSerialDataRequest request) {
  final channelCount = request.channelCount;
  final drawSurfaceWidth = request.drawSurfaceWidth;
  final data = request.data;

  final outSamplesPtr = calloc<Pointer<Int16>>(channelCount);
  for (int i = 0; i < channelCount; i++) {
    outSamplesPtr[i] = calloc<Int16>(drawSurfaceWidth * 5);
  }
  final outSampleCountsPtr = calloc<Int32>(channelCount);
  final inDataPtr = calloc<Uint8>(data.length);

  try {
    inDataPtr.asTypedList(data.length).setAll(0, data);

    final status = pb.processingBindings.processSampleStream(
      outSamplesPtr,
      outSampleCountsPtr,
      inDataPtr,
      data.length,
      request.deviceType,
    );

    if (status < 0) {
      return InsertSerialDataResult(
        requestId: request.requestId,
        status: status,
        channels: List.generate(channelCount, (_) => Int16List(0)),
        frameCount: 0,
      );
    }

    final sampleCounts =
        List<int>.generate(channelCount, (i) => outSampleCountsPtr[i]);
    var frameCount = 0;
    for (final count in sampleCounts) {
      if (count > 0) {
        frameCount = frameCount == 0 ? count : math.min(frameCount, count);
      }
    }

    final channels = List<Int16List>.generate(channelCount, (i) {
      final count = sampleCounts[i];
      if (count <= 0) return Int16List(0);
      return Int16List.fromList(outSamplesPtr[i].asTypedList(count));
    });

    return InsertSerialDataResult(
      requestId: request.requestId,
      status: status,
      channels: channels,
      frameCount: frameCount,
    );
  } finally {
    for (int i = 0; i < channelCount; i++) {
      calloc.free(outSamplesPtr[i]);
    }
    calloc.free(outSamplesPtr);
    calloc.free(outSampleCountsPtr);
    calloc.free(inDataPtr);
  }
}
