import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
// import 'dart:ffi';

// Conditional export based on platform
export "nwbfile_utils_native.dart"
    if (dart.library.html) "nwbfile_utils_web.dart";


/// One row of the NWB EventsTable, as returned by [NWBFileUtil.getAllEvents].
class NWBEvent {
  final int rowIndex;
  final double timestampSeconds;
  final int eventLabel;
  final bool deleted;

  const NWBEvent({
    required this.rowIndex,
    required this.timestampSeconds,
    required this.eventLabel,
    required this.deleted,
  });

  @override
  String toString() =>
      'NWBEvent(rowIndex: $rowIndex, timestampSeconds: $timestampSeconds, '
      'eventLabel: $eventLabel, deleted: $deleted)';
}

// The abstract interface all implementations must follow
abstract class NWBFileUtil {
  String recordedNwbFilePath = "";
  String openedNwbFilePath = "";
  
  // Callback for file opening completion (used by GraphTemplate)
  Function(dynamic, dynamic, dynamic, dynamic)? onStartOpeningFileWebCallback;
  Function(dynamic, dynamic, dynamic, dynamic)? onStartOpeningFileWebCallbackPlayback;
  
  Future<List<String>> fetchNwbFiles();
  Future<String> processingInit(int sampleRate, int channelCount, String deviceInfo, String deviceManufacturer, List<int> visibleChannelsList, int visibleChannelCount);
  Future<bool> addElectricalSeries(Int16List data, Int32List samplesCount, int selectedChannel,int channelCount, int isFinishRecording);
  /// Appends one EventsTable row. Returns the new row index (>= 0), or -1 on failure.
  Future<int> addEvent(double timestampSeconds, int eventLabel);
  /// Reads one EventsTable row by index. Returns null if the row does not
  /// exist or the read failed.
  Future<({double timestampSeconds, int eventLabel, bool deleted})?> readEvent(
      int rowIndex);
  /// Returns the total number of EventsTable rows recorded so far (including
  /// soft-deleted rows), or 0 if unavailable.
  Future<int> getEventCount();
  Future<bool> readElectricalSeries(Int16List outSamples, Int32List outSamplesCount, int selectedChannel,int channelCount);
  Future<bool> seekElectricalSeries(String filePath, Int16List outSamples, Int32List outSamplesCount, Int32List outConfig, int startTimeStamp, int endTimeStamp, int startChannel, int endChannel);
  Future<String> makeFilePublic(String path);
  Future<String> makeFilePublicBuffer(Uint8List buffer);
  Future<String> recordNewFileLocation();
  
  Future<String> startOpeningFileWeb(String filePath, int startIdx, int endIdx, int startChannel, int endChannel);
  Future<bool> seekElectricalSeriesWeb(String filePath, Int16List outSamples, Int32List outSamplesCount, Int32List outConfig, int startTimeStamp, int endTimeStamp, int startChannel, int endChannel);
}

/// Adds a [getAllEvents] helper on top of the per-implementation
/// [NWBFileUtil.getEventCount] / [NWBFileUtil.readEvent] primitives so
/// native and web implementations don't need to duplicate the loop.
extension NWBFileUtilEvents on NWBFileUtil {
  /// Reads every EventsTable row via [NWBFileUtil.getEventCount] +
  /// [NWBFileUtil.readEvent]. Soft-deleted rows are excluded unless
  /// [includeDeleted] is true. Rows are returned in row-index order.
  Future<List<NWBEvent>> getAllEvents({bool includeDeleted = false}) async {
    final count = await getEventCount();
    final events = <NWBEvent>[];
    for (int rowIndex = 0; rowIndex < count; rowIndex++) {
      final event = await readEvent(rowIndex);
      if (event == null) continue;
      if (!includeDeleted && event.deleted) continue;
      events.add(NWBEvent(
        rowIndex: rowIndex,
        timestampSeconds: event.timestampSeconds,
        eventLabel: event.eventLabel,
        deleted: event.deleted,
      ));
    }
    return events;
  }
}

