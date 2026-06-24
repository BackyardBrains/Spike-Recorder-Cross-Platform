import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
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

  /// Per-physical-channel mask: 1 = record, 0 = skip (from [ChannelColorProvider]).
  List<int> _recordVisibleMask = [1];
  int _recordVisibleChannelCount = 1;

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
    recordedTime = DateTime.now().millisecondsSinceEpoch.toString();
    String path =
        "${(await getApplicationDocumentsDirectory()).path}\\spike_recorder$recordedTime.nwb";
    if (Platform.isIOS) {
      path =
          "${(await getApplicationDocumentsDirectory()).path}/spike_recorder$recordedTime.nwb";
    } else
    if (Platform.isMacOS) {
      path =
          "${(await getDownloadsDirectory())?.path}/spike_recorder$recordedTime.nwb";
      // String computerNamePath = (await getApplicationDocumentsDirectory()).path.split("/Library")[0];
      // path = "${computerNamePath}/spike_recorder$recordedTime.nwb";
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
    int initResult = nwb.processingInit(
        charPointer,
        sampleRate,
        _recordVisibleChannelCount,
        deviceInfoPointer,
        deviceManufacturerPointer);
    print("Dart processing init END");
    if (initResult < 0) {
      print("❌ Failed to initialize NWB file, error code: $initResult");
      return Future.value("false");
    }
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
    final filtered = filterVisibleChannelSamples(
      data,
      samplesCount,
      channelCount,
      _recordVisibleMask,
    );
    if (filtered.channelCount == 0) {
      return Future.value(false);
    }

    Pointer<Int16> dataPtr = calloc<Int16>(filtered.data.length);
    dataPtr.asTypedList(filtered.data.length).setAll(0, filtered.data);
    Pointer<Int32> samplesCountPtr =
        calloc<Int32>(filtered.counts.length);
    samplesCountPtr
        .asTypedList(filtered.counts.length)
        .setAll(0, filtered.counts);
    try {
      nwb.nwbfile_add_electrical_series(
        dataPtr,
        samplesCountPtr,
        selectedChannel,
        filtered.channelCount,
        isFinishRecording,
      );
      return Future.value(true);
    } finally {
      calloc.free(dataPtr);
      calloc.free(samplesCountPtr);
    }
  }

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

    try {
      print("FILE PATH: $filePath");
      final path = filePath;
      // final path = "${(await getApplicationDocumentsDirectory()).path}/example_recording_android_serial3$recordedTime.nwb";
      // final path = "${(await getApplicationDocumentsDirectory()).path}/example_recording.nwb";
      // final path = "${(await getApplicationDocumentsDirectory()).path}/ZERIAL2_example_recording_multiple_channels.nwb";
      print("NWB SEEK file path: $path");
      Pointer<Char> charPointer = path.toString().toNativeUtf8().cast<Char>();

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
          charPointer,
          outSamplesPtr,
          outSamplesCountPtr,
          outConfigPtr,
          startTimeStamp,
          endTimeStamp,
          startChannel,
          endChannel);
      print("📊 Seek result: $result == $startChannel, $endChannel");

      if (endChannel == 1) {
        return Future.value(true);
      }

      if (result == 0) {
        // Success - copy data back from native memory
        int samplesPerChannel =
            outSamplesCountPtr.value; // Now represents samples per channel
        int actualDataPoints = samplesPerChannel * numChannelsToRead;
        print("📊 Samples per channel: $samplesPerChannel");
        print("📊 Total data points: $actualDataPoints");

        // Copy the data back to the Dart list (channel-major format)
        if (actualDataPoints > 0 && actualDataPoints <= outSamples.length) {
          // print("outSamplesCount.length: ${outSamplesCount} || actualDataPoints: $actualDataPoints");
          // int sumPositionIdx = 0;
          // for (int i = 0; i < outSamplesCount.length; i++) {
          //   outSamplesCount[i] = actualDataPoints;
          //   for (int j = 0; j < actualDataPoints; j++) {
          //     outSamples[sumPositionIdx + j] = outSamplesPtr[j];
          //   }
          //   sumPositionIdx += actualDataPoints;
          // }
          // print("outSamplesCount.length FIN: ${outSamplesCount}");

          // Copy configuration parameters
          // for (int i = 0; i < 5 && i < outConfig.length; i++) {
          //   outConfig[i] = outConfigPtr[i];
          // }

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
      print("🔄 Freeing memory...");

      // Copy data from native memory to Dart lists (channel-major format)
      int samplesPerChannel = outSamplesCountPtr.value;
      int numChannelsToRead = endChannel - startChannel + 1;
      int totalDataPoints = samplesPerChannel * numChannelsToRead;

      // Set samples count for each channel
      for (int i = 0; i < outSamplesCount.length; i++) {
        outSamplesCount[i] = samplesPerChannel;
      }

      // Copy the channel-major data
      for (int i = 0; i < totalDataPoints && i < outSamples.length; i++) {
        outSamples[i] = outSamplesPtr[i];
      }

      // Copy configuration parameters
      outConfig.setAll(0, outConfigPtr.asTypedList(10));

      calloc.free(outSamplesPtr);
      calloc.free(outSamplesCountPtr);
      calloc.free(outConfigPtr);
      print("🔄 Freeing memory... Done");
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
    // return Future.value([]);
    try {
      // 1. Get the Application Documents Directory
final directory = await getApplicationDocumentsDirectory();
      final files = directory.listSync();
      
      // 1. Create a temporary structure to hold the File and its DateTime
      List<Map<String, dynamic>> fileWithDates = [];

      for (var file in files) {
        if (file is File && file.path.endsWith('.nwb')) {
          final stat = file.statSync();
          fileWithDates.add({
            'path': file.path,
            'date': stat.modified, // Store as DateTime object for easy comparison
          });
        }
      }

      // 2. Sort the list: newest date first
      // b['date'].compareTo(a['date']) gives a descending order (newest to oldest)
      fileWithDates.sort((a, b) => (b['date'] as DateTime).compareTo(a['date'] as DateTime));

      // 3. Map the sorted list into your requested 'path@@@dateTime' format
      List<String> sortedCombinedData = fileWithDates.map((item) {
        final path = item['path'] as String;
        final dateTimeStr = (item['date'] as DateTime).toIso8601String();
        return "$path@@@$dateTimeStr";
      }).toList();

      return Future.value(sortedCombinedData);
      // return Future.value(nwbFiles.map((file) => (file.path + "@@@" + file.)).toList());
    } catch (e) {
      print("Error fetching files: $e");
    };    
    return Future.value([]);
  }
}

NWBFileUtil createNwbFileUtil() => NwbFileUtilImpl();
