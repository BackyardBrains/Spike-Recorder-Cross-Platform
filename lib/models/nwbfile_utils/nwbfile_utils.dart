import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
// import 'dart:ffi';

// Conditional export based on platform
export "nwbfile_utils_native.dart"
    if (dart.library.html) "nwbfile_utils_web.dart";


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
  Future<bool> readElectricalSeries(Int16List outSamples, Int32List outSamplesCount, int selectedChannel,int channelCount);
  Future<bool> seekElectricalSeries(String filePath, Int16List outSamples, Int32List outSamplesCount, Int32List outConfig, int startTimeStamp, int endTimeStamp, int startChannel, int endChannel);
  Future<String> makeFilePublic(String path);
  Future<String> makeFilePublicBuffer(Uint8List buffer);
  Future<String> recordNewFileLocation();
  
  Future<String> startOpeningFileWeb(String filePath, int startIdx, int endIdx, int startChannel, int endChannel);
  Future<bool> seekElectricalSeriesWeb(String filePath, Int16List outSamples, Int32List outSamplesCount, Int32List outConfig, int startTimeStamp, int endTimeStamp, int startChannel, int endChannel);
}

