import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_file_saver/flutter_file_saver.dart';
import 'package:nwbfile_plugin/nwbfile_plugin.dart' as nwb;
import 'package:path_provider/path_provider.dart';
import 'package:spikerbox_architecture/models/nwbfile_utils/nwbfile_utils.dart';

class NwbFileUtilImpl implements NWBFileUtil {
  String recordedTime = "";
  @override
  String recordedNwbFilePath = "";
  @override
  String openedNwbFilePath = "";
  @override
  int lastInitErrorCode = 0;
  @override
  String debugLogFilePath = "";

  /// Per-physical-channel mask: 1 = record, 0 = skip (from [ChannelColorProvider]).
  List<int> _recordVisibleMask = [1];
  int _recordVisibleChannelCount = 1;

  /// Cached once so record-button presses don't re-hit path_provider.
  static String? _cachedDocumentsPath;
  static String? _cachedDownloadsPath;
  static String? _cachedWindowsRecordingsPath;

  Future<String> _documentsPath() async {
    return _cachedDocumentsPath ??=
        (await getApplicationDocumentsDirectory()).path;
  }

  Future<String?> _downloadsPath() async {
    if (_cachedDownloadsPath != null) return _cachedDownloadsPath;
    final dir = await getDownloadsDirectory();
    _cachedDownloadsPath = dir?.path;
    return _cachedDownloadsPath;
  }

  /// Human-readable meaning of the numeric codes returned by the native
  /// `processing_init()` (see `nwbfile_processing_plugin.cpp`). Kept in sync
  /// manually since the codes are plain ints across the FFI boundary.
  static const Map<int, String> _initErrorMeanings = {
    1: "Could not open/create the NWB file (open IO failed)",
    2: "NWB file structure initialization failed",
    3: "Recording device metadata initialization failed",
    4: "Electrodes table creation failed",
    5: "Electrical series creation failed",
    6: "Events table creation failed",
    7: "Event meanings table creation failed",
    8: "HDF5 library exception",
    9: "Unexpected C++ exception",
    10: "Unknown native error",
  };

  /// Plain-text log so a non-technical user can find and send this file
  /// without needing a terminal/console attached (release Windows builds
  /// have no visible stdout/stderr).
  Future<void> _appendDebugLog(String message) async {
    try {
      final dir = Platform.isWindows
          ? await _windowsRecordingsDirectory()
          : await _documentsPath();
      final logFile =
          File('$dir${Platform.pathSeparator}spike_recorder_debug.log');
      debugLogFilePath = logFile.path;
      final line = '[${DateTime.now().toIso8601String()}] $message\n';
      await logFile.writeAsString(line,
          mode: FileMode.append, flush: true);
    } catch (e) {
      debugPrint('Failed to write debug log: $e');
    }
  }

  /// Windows: avoid OneDrive-backed Documents (can hang/fail HDF5 create).
  /// Default to local AppData\Roaming\<app>\Downloads.
  Future<String> _windowsRecordingsDirectory() async {
    if (_cachedWindowsRecordingsPath != null) {
      return _cachedWindowsRecordingsPath!;
    }

    final candidates = <Directory>[
      Directory(
          '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}Downloads'),
      Directory(
          '${(await getTemporaryDirectory()).path}${Platform.pathSeparator}spike_recorder_Downloads'),
    ];

    for (final dir in candidates) {
      try {
        if (!await dir.exists()) {
          await dir.create(recursive: true);
        }
        final probe = File(
            '${dir.path}${Platform.pathSeparator}.write_probe_${DateTime.now().microsecondsSinceEpoch}');
        await probe.writeAsString('ok', flush: true);
        await probe.delete();
        _cachedWindowsRecordingsPath = dir.path;
        debugPrint('NWB Windows recordings dir: ${dir.path}');
        return dir.path;
      } catch (e) {
        debugPrint('NWB Windows recordings dir unusable (${dir.path}): $e');
      }
    }

    final fallback =
        '${(await getApplicationSupportDirectory()).path}${Platform.pathSeparator}Downloads';
    await Directory(fallback).create(recursive: true);
    _cachedWindowsRecordingsPath = fallback;
    return fallback;
  }

  @override
  Function(dynamic, dynamic, dynamic, dynamic)? onStartOpeningFileWebCallback;

  /// Keeps only visible channels in planar layout: [ch0 samples][ch1 samples]...
  static ({Int16List data, Int32List counts, int channelCount})
      filterVisibleChannelSamples(
    Int16List data,
    Int32List samplesCount,
    int physicalChannelCount,
    List<int> visibleMask,
  ) {
    final channelCount = physicalChannelCount < samplesCount.length
        ? physicalChannelCount
        : samplesCount.length;

    int visibleCount = 0;
    for (int i = 0; i < channelCount; i++) {
      if (i >= visibleMask.length || visibleMask[i] != 0) {
        visibleCount++;
      }
    }

    if (visibleCount == 0) {
      return (
        data: Int16List(0),
        counts: Int32List(0),
        channelCount: 0,
      );
    }

    if (visibleMask.isEmpty ||
        (visibleCount == channelCount &&
            visibleMask.length >= channelCount &&
            visibleMask.take(channelCount).every((v) => v == 1))) {
      return (
        data: data,
        counts: samplesCount,
        channelCount: channelCount,
      );
    }

    final filteredCounts = Int32List(visibleCount);
    var totalSamples = 0;
    var readOffset = 0;
    for (int i = 0; i < channelCount; i++) {
      final len = samplesCount[i];
      if (i < visibleMask.length && visibleMask[i] == 0) {
        readOffset += len;
        continue;
      }
      totalSamples += len;
      readOffset += len;
    }

    final filteredData = Int16List(totalSamples);
    readOffset = 0;
    var writeOffset = 0;
    var recordIdx = 0;
    for (int i = 0; i < channelCount; i++) {
      final len = samplesCount[i];
      if (i < visibleMask.length && visibleMask[i] == 0) {
        readOffset += len;
        continue;
      }
      filteredData.setRange(writeOffset, writeOffset + len, data, readOffset);
      filteredCounts[recordIdx++] = len;
      writeOffset += len;
      readOffset += len;
    }

    return (
      data: filteredData,
      counts: filteredCounts,
      channelCount: visibleCount,
    );
  }

  @override
  Future<String> processingInit(
      int sampleRate,
      int channelCount,
      String deviceInfo,
      String deviceManufacturer,
      List<int> visibleChannelsList,
      int visibleChannelCount) async {
    // final path = "${(await getApplicationDocumentsDirectory()).path}/${DateTime.now().millisecondsSinceEpoch}";
    // final path = (await getApplicationDocumentsDirectory()).path + "/example_recording2.nwb";
    print("PROCESSING INIT: $sampleRate, $channelCount, $deviceInfo, $deviceManufacturer, $visibleChannelsList, $visibleChannelCount");
    recordedTime = DateTime.now().millisecondsSinceEpoch.toString();
    final docsPath = await _documentsPath();
    String path = "$docsPath\\spike_recorder$recordedTime.nwb";
    if (Platform.isWindows) {
      final recordingsDir = await _windowsRecordingsDirectory();
      path =
          "$recordingsDir${Platform.pathSeparator}spike_recorder$recordedTime.nwb";
    } else if (Platform.isIOS) {
      path = "$docsPath/spike_recorder$recordedTime.nwb";
    } else if (Platform.isMacOS) {
      final downloadsPath = await _downloadsPath();
      path = "${downloadsPath ?? docsPath}/spike_recorder$recordedTime.nwb";
    } else if (Platform.isAndroid || Platform.isLinux) {
      path = "$docsPath/spike_recorder$recordedTime.nwb";
    }
    _recordVisibleMask = List<int>.from(visibleChannelsList);
    _recordVisibleChannelCount = visibleChannelCount > 0
        ? visibleChannelCount
        : _recordVisibleMask.where((v) => v == 1).length;
    if (_recordVisibleChannelCount == 0) {
      print("❌ No visible channels to record");
      return Future.value("false");
    }

    print(
        "NWB file path: $path ---- $sampleRate, visible channels: $_recordVisibleChannelCount / $channelCount, mask: $_recordVisibleMask");
    Pointer<Char> charPointer = path.toString().toNativeUtf8().cast<Char>();
    Pointer<Char> deviceInfoPointer = deviceInfo.toNativeUtf8().cast<Char>();
    Pointer<Char> deviceManufacturerPointer =
        deviceManufacturer.toNativeUtf8().cast<Char>();

    print("Dart processing init start");
    int initResult;
    try {
      initResult = nwb.processingInit(
          charPointer,
          sampleRate,
          _recordVisibleChannelCount,
          deviceInfoPointer,
          deviceManufacturerPointer);
    } finally {
      malloc.free(charPointer);
      malloc.free(deviceInfoPointer);
      malloc.free(deviceManufacturerPointer);
    }
    print("Dart processing init END");
    lastInitErrorCode = initResult;
    if (initResult != 0) {
      final meaning = _initErrorMeanings[initResult] ?? "Unrecognized error";
      print(
          "❌ Failed to initialize NWB file, error code: $initResult ($meaning)");
      await _appendDebugLog(
          "processingInit FAILED code=$initResult ($meaning) path=$path "
          "sampleRate=$sampleRate channelCount=$channelCount "
          "visibleChannelCount=$_recordVisibleChannelCount");
      recordedNwbFilePath = "";
      return Future.value("false");
    }
    recordedNwbFilePath = path;
    return Future.value(path);
  }

  @override
  Future<String> makeFilePublicBuffer(Uint8List buffer) async {
    return "-";
  }

  @override
  Future<String> makeFilePublic(String path) async {
    if (Platform.isAndroid) {
      int lastIdx = path.lastIndexOf("/");
      String fileName = "";
      if (lastIdx > -1) {
        fileName = path.substring(lastIdx + 1);
      }
      print("fileName: $fileName");
      File file = File(path);

      String resultString = await FlutterFileSaver().writeFileAsBytes(
        fileName: fileName,
        bytes: file.readAsBytesSync(),
      );
      print("resultString");
      print(resultString);
      return Future.value(path);
    } else {
      return Future.value(path);
    }
  }

  @override
  Future<bool> addElectricalSeries(Int16List data, Int32List samplesCount,
      int selectedChannel, int channelCount, int isFinishRecording) {
    // Finalize requires at least one sample per visible channel; native rejects empty counts.
    // if (isFinishRecording == 1 && data.isEmpty) {
    //   final finishChannelCount = _recordVisibleChannelCount;
    //   if (finishChannelCount <= 0) {
    //     return Future.value(false);
    //   }
    //   final finishData = Int16List(finishChannelCount);
    //   final finishCounts = Int32List(finishChannelCount)..fillRange(0, finishChannelCount, 1);
    //   final finishDataPtr = calloc<Int16>(finishData.length);
    //   finishDataPtr.asTypedList(finishData.length).fillRange(0, finishData.length, 0);
    //   final finishCountsPtr = calloc<Int32>(finishCounts.length);
    //   finishCountsPtr.asTypedList(finishCounts.length).setAll(0, finishCounts);
    //   try {
    //     nwb.nwbfile_add_electrical_series(
    //       finishDataPtr,
    //       finishCountsPtr,
    //       selectedChannel,
    //       finishChannelCount,
    //       isFinishRecording,
    //     );
    //     return Future.value(true);
    //   } finally {
    //     calloc.free(finishDataPtr);
    //     calloc.free(finishCountsPtr);
    //   }
    // }

    final filtered = filterVisibleChannelSamples(
      data,
      samplesCount,
      channelCount,
      _recordVisibleMask,
    );
    // print("FILTERED CHANNEL COUNT: ${filtered.channelCount} IS FINISH RECORDING: $isFinishRecording");
    if (filtered.channelCount == 0 && isFinishRecording != 1) {
      return Future.value(false);
    }

    // calloc(0) can return nullptr on Windows; never pass that into native fwrite/HDF5.
    if (filtered.data.isEmpty || filtered.counts.isEmpty) {
      print(
          "⚠️ Skipping addElectricalSeries: empty data (finish=$isFinishRecording)");
      return Future.value(isFinishRecording == 1);
    }

    Pointer<Int16> dataPtr = calloc<Int16>(filtered.data.length);
    dataPtr.asTypedList(filtered.data.length).setAll(0, filtered.data);
    Pointer<Int32> samplesCountPtr =
        calloc<Int32>(filtered.counts.length);
    samplesCountPtr
        .asTypedList(filtered.counts.length)
        .setAll(0, filtered.counts);
    // print("FILTERED DATA: ${filtered.data.length} IS FINISH RECORDING: $isFinishRecording");
    // print("FILTERED COUNTS: ${filtered.counts} IS FINISH RECORDING: $isFinishRecording");
    try {
      nwb.nwbfile_add_electrical_series(
        dataPtr,
        samplesCountPtr,
        selectedChannel,
        filtered.channelCount,
        isFinishRecording,
      );
      // print("📊 Add electrical series result: $isFinishRecording");
      return Future.value(true);
    } finally {
      calloc.free(dataPtr);
      calloc.free(samplesCountPtr);
    }
  }

  @override
  Future<int> addEvent(double timestampSeconds, int eventLabel) async {
    final row = nwb.nwbfileAddEvent(timestampSeconds, eventLabel);
    print("📌 Added NWB event: timestamp=$timestampSeconds, label=$eventLabel, row=$row");
    return row;
  }

  @override
  Future<({double timestampSeconds, int eventLabel, bool deleted})?> readEvent(
      int rowIndex) async {
    final timestampPtr = calloc<Float>();
    final eventLabelPtr = calloc<Int32>();
    final deletedPtr = calloc<Uint8>();
    try {
      final result = nwb.nwbfileReadEvent(
        rowIndex,
        timestampPtr,
        eventLabelPtr,
        deletedPtr,
      );
      if (result != 0) {
        print("❌ Failed to read NWB event at row $rowIndex, error code: $result");
        return null;
      }
      final event = (
        timestampSeconds: timestampPtr.value,
        eventLabel: eventLabelPtr.value,
        deleted: deletedPtr.value != 0,
      );
      print(
          "📖 Read NWB event: row=$rowIndex, timestamp=${event.timestampSeconds}, label=${event.eventLabel}, deleted=${event.deleted}");
      return event;
    } finally {
      calloc.free(timestampPtr);
      calloc.free(eventLabelPtr);
      calloc.free(deletedPtr);
    }
  }

  @override
  Future<int> getEventCount() async => nwb.nwbfileGetEventCount();

  @override
  Future<bool> readElectricalSeries(Int16List outSamples,
      Int32List outSamplesCount, int selectedChannel, int channelCount) {
    Pointer<Int16> outSamplesPtr = calloc<Int16>(outSamples.length);
    Pointer<Int32> outSamplesCountPtr = calloc<Int32>(outSamplesCount.length);

    try {
      print("📖 Reading electrical series data...");
      print("   Channel: $selectedChannel");
      print("   Expected samples: ${outSamples.length}");

      int result = nwb.nwbfile_read_electrical_series(
          outSamplesPtr, outSamplesCountPtr, selectedChannel, channelCount);

      print("📊 Read result: $result");

      if (result == 0) {
        // Success - copy data back from native memory
        int actualSampleCount = outSamplesCountPtr.value;
        print("📊 Actual samples read: $actualSampleCount");

        // Copy the data back to the Dart list
        if (actualSampleCount > 0 && actualSampleCount <= outSamples.length) {
          for (int i = 0; i < actualSampleCount; i++) {
            outSamples[i] = outSamplesPtr[i];
          }
          outSamplesCount[0] = actualSampleCount;

          print("✅ Successfully copied $actualSampleCount samples");

          // Print first few samples for verification
          if (actualSampleCount > 0) {
            print("📈 First 5 samples:");
            for (int i = 0; i < 5 && i < actualSampleCount; i++) {
              print("   Sample $i: ${outSamples[i]}");
            }
          }

          return Future.value(true);
        } else {
          print("❌ Invalid sample count: $actualSampleCount");
          return Future.value(false);
        }
      } else {
        print("❌ Failed to read electrical series, error code: $result");
        return Future.value(false);
      }
    } finally {
      calloc.free(outSamplesPtr);
      calloc.free(outSamplesCountPtr);
    }
  }

  @override
  Future<bool> seekElectricalSeries(
      String filePath,
      Int16List outSamples,
      Int32List outSamplesCount,
      Int32List outConfig,
      int startTimeStamp,
      int endTimeStamp,
      int startChannel,
      int endChannel) async {
    Pointer<Int16> outSamplesPtr = calloc<Int16>(outSamples.length);
    Pointer<Int32> outSamplesCountPtr = calloc<Int32>(outSamplesCount.length);
    Pointer<Int32> outConfigPtr =
        calloc<Int32>(10); // Allocate for 5 config parameters
    Pointer<Char>? charPointer;

    try {
      print("FILE PATH: $filePath");
      final path = filePath;
      print("NWB SEEK file path: $path");
      charPointer = path.toString().toNativeUtf8().cast<Char>();

      int numChannelsToRead = endChannel - startChannel + 1;
      print("🎯 Seeking electrical series data (Multi-Channel)...");
      print("   Time range: $startTimeStamp to $endTimeStamp");
      print(
          "   Channels: $startChannel to $endChannel ($numChannelsToRead channels)");
      print(
          "   Expected samples per channel: ${endTimeStamp - startTimeStamp}");
      print(
          "   Expected total data points: ${(endTimeStamp - startTimeStamp) * numChannelsToRead}");

      int result = nwb.nwbfile_seek_electrical_series(
          charPointer!,
          outSamplesPtr,
          outSamplesCountPtr,
          outConfigPtr,
          startTimeStamp,
          endTimeStamp,
          startChannel,
          endChannel);
      print("📊 Seek result: $result == $startChannel, $endChannel");


      if (result == 0) {
        // Success - copy data back from native memory
        int samplesPerChannel =
            outSamplesCountPtr.value; // Now represents samples per channel
        int actualDataPoints = samplesPerChannel * numChannelsToRead;
        print("📊 Samples per channel: $samplesPerChannel");
        print("📊 Total data points: $actualDataPoints");

        // Copy the data back to the Dart list (channel-major format)
        if (actualDataPoints > 0 && actualDataPoints <= outSamples.length) {
          for (int i = 0; i < outSamplesCount.length; i++) {
            outSamplesCount[i] = samplesPerChannel;
          }
          for (int i = 0; i < actualDataPoints; i++) {
            outSamples[i] = outSamplesPtr[i];
          }
          outConfig.setAll(0, outConfigPtr.asTypedList(10));

          print(
              "✅ Successfully copied $actualDataPoints data points from seek operation");

          // Print configuration parameters
          print("📋 Recording Configuration:");
          print("   Sample Rate: ${outConfig[0]} Hz");
          print("   Total Channels: ${outConfig[1]}");
          print("   Group Name (ID): ${outConfig[2]}");
          print("   Group Index: ${outConfig[3]}");
          print("   BitVolts (µV): ${outConfig[4]}");

          // Print first few samples for verification (channel-major format)
          if (samplesPerChannel > 0) {
            print("📈 First 5 samples from seek (channel-major format):");
            int samplesToShow = (samplesPerChannel < 5) ? samplesPerChannel : 5;
            for (int i = 0; i < samplesToShow; i++) {
              String sampleInfo = "Sample ${startTimeStamp + i}: ";
              for (int ch = 0; ch < numChannelsToRead; ch++) {
                int idx = ch * samplesPerChannel + i;
                sampleInfo += "Ch${startChannel + ch}=${outSamples[idx]}";
                if (ch < numChannelsToRead - 1) sampleInfo += ", ";
              }
              print("   $sampleInfo");
            }
          }

          return Future.value(true);
        } else {
          print("❌ Invalid data point count from seek: $actualDataPoints");
          return Future.value(false);
        }
      } else {
        print("❌ Failed to seek electrical series, error code: $result");
        return Future.value(false);
      }
    } finally {
      if (charPointer != null) {
        malloc.free(charPointer);
      }
      calloc.free(outSamplesPtr);
      calloc.free(outSamplesCountPtr);
      calloc.free(outConfigPtr);
    }
  }

  @override
  Future<String> recordNewFileLocation() {
    return Future.value("");
    // throw UnimplementedError();
  }

  @override
  Future<String> startOpeningFileWeb(String filePath, int startIdx, int endIdx,
      int startChannel, int endChannel) {
    return Future.value("");
  }

  @override
  Future<bool> seekElectricalSeriesWeb(
      String filePath,
      Int16List outSamples,
      Int32List outSamplesCount,
      Int32List outConfig,
      int startTimeStamp,
      int endTimeStamp,
      int startChannel,
      int endChannel) {
    // TODO: implement seekElectricalSeriesWeb
    return Future.value(true);
  }

  @override
  Function(dynamic p1, dynamic p2, dynamic p3, dynamic p4)?
      onStartOpeningFileWebCallbackPlayback;
      
  @override
  Future<List<String>> fetchNwbFiles() async {
    try {
      final directories = <Directory>[
        await getApplicationDocumentsDirectory(),
      ];
      if (Platform.isWindows) {
        directories.add(Directory(await _windowsRecordingsDirectory()));
      }

      List<Map<String, dynamic>> fileWithDates = [];
      final seen = <String>{};

      for (final directory in directories) {
        if (!await directory.exists()) continue;
        final files = directory.listSync();
        for (var file in files) {
          if (file is File && file.path.endsWith('.nwb')) {
            if (!seen.add(file.path)) continue;
            final stat = file.statSync();
            fileWithDates.add({
              'path': file.path,
              'date': stat.modified,
            });
          }
        }
      }

      fileWithDates.sort((a, b) =>
          (b['date'] as DateTime).compareTo(a['date'] as DateTime));

      List<String> sortedCombinedData = fileWithDates.map((item) {
        final path = item['path'] as String;
        final dateTimeStr = (item['date'] as DateTime).toIso8601String();
        return "$path@@@$dateTimeStr";
      }).toList();

      return Future.value(sortedCombinedData);
    } catch (e) {
      print("Error fetching files: $e");
    }
    return Future.value([]);
  }
}

NWBFileUtil createNwbFileUtil() => NwbFileUtilImpl();
