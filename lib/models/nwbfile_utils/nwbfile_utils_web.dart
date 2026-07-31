import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter_file_saver/flutter_file_saver.dart';
import 'package:spikerbox_architecture/models/nwbfile_utils/nwbfile_utils.dart';
import 'dart:js' as js;

class NwbFileUtilImpl implements NWBFileUtil {
  String recordedTime = "";
  bool isOpeningFileWeb = false;

  @override
  String recordedNwbFilePath = "";
  @override
  String openedNwbFilePath = "";
  @override
  int lastInitErrorCode = 0;
  @override
  String debugLogFilePath = "";
  
  @override
  Function(dynamic, dynamic, dynamic, dynamic)? onStartOpeningFileWebCallback;
  Function(dynamic, dynamic, dynamic, dynamic)? onStartOpeningFileWebCallbackPlayback;

  /// Pending Completers keyed by the requestId returned from index.js helpers.
  final Map<int, Completer<int>> _addEventCompleters = {};
  final Map<int, Completer<int>> _getEventCountCompleters = {};
  final Map<int, Completer<({double timestampSeconds, int eventLabel, bool deleted})?>>
      _readEventCompleters = {};

  /// Completes when the worker posts NWB_FILE_CREATED / failure ("--").
  Completer<String>? _nwbFileCreatedCompleter;
  
  void onNwbFileCreatedCallback(String resultString){
    print("onNwbFileCreatedCallback: $resultString");
    recordedNwbFilePath = resultString;
    final completer = _nwbFileCreatedCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(resultString);
    }
  }

  void onSeekNwbFileBufferWebCallback(config, arrSampleCount, arrSamples, isStartOpeningFileWeb){
    print("configzzzz");
    print(config);
    // Store config for later use - validate it has at least 10 elements
    if (config != null && config is List && config.length >= 10) {
      Int32List configList = Int32List.fromList(config.map((e) => e as int).toList());
      isOpeningFileWeb = true;
      // Call the GraphTemplate callback with the config and result
      if (onStartOpeningFileWebCallback != null) {
        // Pass both the config and success status
        // The config will be used to populate arrConfigWeb in GraphTemplate
        onStartOpeningFileWebCallback!(configList, arrSampleCount, arrSamples, isStartOpeningFileWeb);
        if (isOpeningFileWeb) {
          // js.context.callMethod('fillLoadedSamplesToBuffer', [config]);
        }
      }
    } else {
      print("WARNING: onSeekNwbFileBufferWebCallback received invalid config: $config (isList: ${config is List}, length: ${config is List ? config.length : 'N/A'})");
    }
  }
  
  void setOpenedFileName(fileName){
    openedNwbFilePath = fileName;
  }
  
  void onSeekNwbFileBufferWebCallbackPlayback(config, arrSampleCount, arrSamples, isStartOpeningFileWeb){
    // Store config for later use - validate it has at least 10 elements
    if (config != null && config is List && config.length >= 10) {
      Int32List configList = Int32List.fromList(config.map((e) => e as int).toList());
      // Call the GraphTemplate callback with the config and result
      if (onStartOpeningFileWebCallbackPlayback != null) {
        // Pass both the config and success status
        // The config will be used to populate arrConfigWeb in GraphTemplate
        onStartOpeningFileWebCallbackPlayback!(configList, arrSampleCount, arrSamples, isStartOpeningFileWeb);
        if (isOpeningFileWeb) {
          // js.context.callMethod('fillLoadedSamplesToBuffer', [config]);
        }
      }
    } else {
      // print("WARNING: onSeekNwbFileBufferWebCallback received invalid config: $config (isList: ${config is List}, length: ${config is List ? config.length : 'N/A'})");
    }
  }

  NwbFileUtilImpl(){
    js.context['onNwbFileCreated'] = onNwbFileCreatedCallback;
    js.context['onSeekNwbFileBufferWebCallback'] = onSeekNwbFileBufferWebCallback;
    js.context['onSeekNwbFileBufferWebCallbackPlayback'] = onSeekNwbFileBufferWebCallbackPlayback;
    js.context['setOpenedFileName'] = setOpenedFileName;
    js.context['onAddNwbEventResult'] = _onAddNwbEventResult;
    js.context['onGetNwbEventCountResult'] = _onGetNwbEventCountResult;
    js.context['onReadNwbEventResult'] = _onReadNwbEventResult;
    //SEEK_NWB_FILE_BUFFER_WEB_CALLBACK
  }

  void _onAddNwbEventResult(dynamic requestId, dynamic rowIndex, [dynamic error]) {
    final id = (requestId as num).toInt();
    final completer = _addEventCompleters.remove(id);
    if (completer == null || completer.isCompleted) return;
    if (error != null) {
      print("addEvent web error: $error");
    }
    completer.complete((rowIndex as num?)?.toInt() ?? -1);
  }

  void _onGetNwbEventCountResult(dynamic requestId, dynamic count, [dynamic error]) {
    final id = (requestId as num).toInt();
    final completer = _getEventCountCompleters.remove(id);
    if (completer == null || completer.isCompleted) return;
    if (error != null) {
      print("getEventCount web error: $error");
    }
    completer.complete((count as num?)?.toInt() ?? 0);
  }

  void _onReadNwbEventResult(
    dynamic requestId,
    dynamic ok,
    dynamic timestampSeconds,
    dynamic eventLabel,
    dynamic deleted, [
    dynamic error,
  ]) {
    final id = (requestId as num).toInt();
    final completer = _readEventCompleters.remove(id);
    if (completer == null || completer.isCompleted) return;
    if (error != null) {
      print("readEvent web error: $error");
    }
    if (ok != true) {
      completer.complete(null);
      return;
    }
    completer.complete((
      timestampSeconds: (timestampSeconds as num).toDouble(),
      eventLabel: (eventLabel as num).toInt(),
      deleted: deleted == true,
    ));
  }

  @override
  Future<String> recordNewFileLocation() async {
    recordedTime = DateTime.now().millisecondsSinceEpoch.toString();
    String path = "spike_recorder$recordedTime.nwb";

    String resultString =js.context.callMethod('recordNewNwbFile', [path]);
    print("resultString: $resultString");
    return Future.value(resultString);
  }

  @override
  Future<String> processingInit(int sampleRate, int channelCount, String deviceInfo, String deviceManufacturer, List<int> visibleChannelsList, int visibleChannelCount) async {
    print("processingInit: $sampleRate, $channelCount, $deviceInfo, $deviceManufacturer");
    recordedTime = DateTime.now().millisecondsSinceEpoch.toString();
    String path = "spike_recorder${recordedTime.toString()}.nwb";
    String charPointer = path.toString();
    String deviceInfoPointer = deviceInfo;
    String deviceManufacturerPointer = deviceManufacturer;
    // Worker expects a typed array (.o buffer); plain List<int> does not survive postMessage.
    final visibleSignals = Int16List.fromList(visibleChannelsList);

    // Wait for the worker callback instead of returning before the file exists
    // (callers used to poll recordedNwbFilePath every 50ms).
    recordedNwbFilePath = "";
    final created = Completer<String>();
    _nwbFileCreatedCompleter = created;

    js.context.callMethod('createNwbFile', [
      charPointer,
      sampleRate,
      channelCount,
      deviceInfoPointer,
      deviceManufacturerPointer,
      visibleSignals,
      visibleChannelCount,
    ]);

    // If the callback already raced ahead of this await, honor it.
    if (recordedNwbFilePath.isNotEmpty && !created.isCompleted) {
      created.complete(recordedNwbFilePath);
    }

    try {
      final result = await created.future.timeout(
        const Duration(seconds: 10),
        onTimeout: () => "--",
      );
      if (result.isEmpty || result == "--") {
        return "false";
      }
      return result;
    } finally {
      if (identical(_nwbFileCreatedCompleter, created)) {
        _nwbFileCreatedCompleter = null;
      }
    }
  }

  @override
  Future<String> makeFilePublic(String path) async {
    js.context.callMethod('makeFilePublicWeb', [path]);    
    return "";
  }

  @override
  Future<String> makeFilePublicBuffer(Uint8List buffer) async {
    // COPY HDF5FILE from WASMFS to fileHandle
    // js.context.callMethod('copyFileFromWasmFsToFileHandle', [path]);
    if (kIsWeb) {
      String fileName = "spike_recorder.nwb";

      String resultString = await FlutterFileSaver().writeFileAsBytes(
          fileName: fileName,
          bytes: buffer,
      );
      return Future.value(resultString);
    } else {
      return Future.value("-");
    }
    
  }

  @override
  Future<bool> addElectricalSeries(Int16List data, Int32List samplesCount, int selectedChannel,int channelCount, int isFinishRecording) {
    if (recordedNwbFilePath == "") {
      return Future.value(false); 
    }
    print("addElectricalSeries: DATA: $data");
    js.context.callMethod('addElectricalSeriesWeb', [data, samplesCount, selectedChannel, channelCount, isFinishRecording]);
    // print("addElectricalSeries: $isFinishRecording SamplesCOUNT: $samplesCount DATA: $data");
    // Pointer<Int16> dataPtr = calloc<Int16>(data.length);
    // dataPtr.asTypedList(data.length).setAll(0, data);
    // Pointer<Int32> samplesCountPtr = calloc<Int32>(samplesCount.length);
    // samplesCountPtr.asTypedList(samplesCount.length).setAll(0, samplesCount);
    // nwb.nwbfile_add_electrical_series(dataPtr, samplesCountPtr, selectedChannel, channelCount, isFinishRecording);
    return Future.value(true);
  }
  
  @override
  Future<int> addEvent(double timestampSeconds, int eventLabel) async {
    final completer = Completer<int>();
    final requestId = (js.context
            .callMethod('addNwbEventWeb', [timestampSeconds, eventLabel]) as num)
        .toInt();
    _addEventCompleters[requestId] = completer;
    return completer.future;
  }

  @override
  Future<({double timestampSeconds, int eventLabel, bool deleted})?> readEvent(
      int rowIndex) async {
    final completer =
        Completer<({double timestampSeconds, int eventLabel, bool deleted})?>();
    final requestId =
        (js.context.callMethod('readNwbEventWeb', [rowIndex]) as num).toInt();
    _readEventCompleters[requestId] = completer;
    return completer.future;
  }

  @override
  Future<int> getEventCount() async {
    final completer = Completer<int>();
    final requestId =
        (js.context.callMethod('getNwbEventCountWeb', []) as num).toInt();
    _getEventCountCompleters[requestId] = completer;
    return completer.future;
  }

  @override
  Future<bool> readElectricalSeries(Int16List outSamples, Int32List outSamplesCount, int selectedChannel, int channelCount) {
    return Future.value(true);
  }

  @override
  Future<bool> seekElectricalSeriesWeb(String filePath, Int16List outSamples, Int32List outSamplesCount, Int32List outConfig, int startIdx, int endIdx, int startChannel, int endChannel) async {
    js.context.callMethod('seekOpeningFileWeb', [filePath, startIdx, endIdx, startChannel, endChannel, false]);
    isOpeningFileWeb = true;
    return Future.value(true);
  }

  @override
  Future<bool> seekElectricalSeries(String filePath, Int16List outSamples, Int32List outSamplesCount, Int32List outConfig, int startIdx, int endIdx, int startChannel, int endChannel) async {
    print("seekElectricalSeries: $filePath, $startIdx, $endIdx, $startChannel, $endChannel");
    js.context.callMethod('startOpeningFileWeb', [filePath, startIdx, endIdx, startChannel, endChannel, false]);
    isOpeningFileWeb = true;
    return Future.value(true);
    
    // Pointer<Int16> outSamplesPtr = calloc<Int16>(outSamples.length);
    // Pointer<Int32> outSamplesCountPtr = calloc<Int32>(outSamplesCount.length);
    // Pointer<Int32> outConfigPtr = calloc<Int32>(10); // Allocate for 5 config parameters

    // try {
    //   print("FILE PATH: $filePath");
    //   final path = filePath;
    //   // final path = "${(await getApplicationDocumentsDirectory()).path}/example_recording_android_serial3$recordedTime.nwb";
    //   // final path = "${(await getApplicationDocumentsDirectory()).path}/example_recording.nwb";
    //   // final path = "${(await getApplicationDocumentsDirectory()).path}/ZERIAL2_example_recording_multiple_channels.nwb";
    //   print("NWB SEEK file path: $path");
    //   Pointer<Char> charPointer = path.toString().toNativeUtf8().cast<Char>();

    //   int numChannelsToRead = endChannel - startChannel + 1;
    //   print("🎯 Seeking electrical series data (Multi-Channel)...");
    //   print("   Time range: $startTimeStamp to $endTimeStamp");
    //   print("   Channels: $startChannel to $endChannel ($numChannelsToRead channels)");
    //   print("   Expected samples per channel: ${endTimeStamp - startTimeStamp}");
    //   print("   Expected total data points: ${(endTimeStamp - startTimeStamp) * numChannelsToRead}");

    //   int result = nwb.nwbfile_seek_electrical_series(charPointer, outSamplesPtr, outSamplesCountPtr, outConfigPtr, startTimeStamp, endTimeStamp, startChannel, endChannel);
    //   print("📊 Seek result: $result == $startChannel, $endChannel");

    //   if (endChannel == 1) {
    //     return Future.value(true);
    //   }

    //   if (result == 0) {
    //     // Success - copy data back from native memory
    //     int samplesPerChannel = outSamplesCountPtr.value; // Now represents samples per channel
    //     int actualDataPoints = samplesPerChannel * numChannelsToRead;
    //     print("📊 Samples per channel: $samplesPerChannel");
    //     print("📊 Total data points: $actualDataPoints");
        
    //     // Copy the data back to the Dart list (channel-major format)
    //     if (actualDataPoints > 0 && actualDataPoints <= outSamples.length) {
    //       // print("outSamplesCount.length: ${outSamplesCount} || actualDataPoints: $actualDataPoints");
    //       // int sumPositionIdx = 0;
    //       // for (int i = 0; i < outSamplesCount.length; i++) {
    //       //   outSamplesCount[i] = actualDataPoints;
    //       //   for (int j = 0; j < actualDataPoints; j++) {
    //       //     outSamples[sumPositionIdx + j] = outSamplesPtr[j];
    //       //   }
    //       //   sumPositionIdx += actualDataPoints;
    //       // }
    //       // print("outSamplesCount.length FIN: ${outSamplesCount}");
          
    //       // Copy configuration parameters
    //       // for (int i = 0; i < 5 && i < outConfig.length; i++) {
    //       //   outConfig[i] = outConfigPtr[i];
    //       // }
          
    //       print("✅ Successfully copied $actualDataPoints data points from seek operation");
          
    //       // Print configuration parameters
    //       print("📋 Recording Configuration:");
    //       print("   Sample Rate: ${outConfig[0]} Hz");
    //       print("   Total Channels: ${outConfig[1]}");
    //       print("   Group Name (ID): ${outConfig[2]}");
    //       print("   Group Index: ${outConfig[3]}");
    //       print("   BitVolts (µV): ${outConfig[4]}");
          
    //       // Print first few samples for verification (channel-major format)
    //       if (samplesPerChannel > 0) {
    //         print("📈 First 5 samples from seek (channel-major format):");
    //         int samplesToShow = (samplesPerChannel < 5) ? samplesPerChannel : 5;
    //         for (int i = 0; i < samplesToShow; i++) {
    //           String sampleInfo = "Sample ${startTimeStamp + i}: ";
    //           for (int ch = 0; ch < numChannelsToRead; ch++) {
    //             int idx = ch * samplesPerChannel + i;
    //             sampleInfo += "Ch${startChannel + ch}=${outSamples[idx]}";
    //             if (ch < numChannelsToRead - 1) sampleInfo += ", ";
    //           }
    //           print("   $sampleInfo");
    //         }
    //       }
          
    //       return Future.value(true);
    //     } else {
    //       print("❌ Invalid data point count from seek: $actualDataPoints");
    //       return Future.value(false);
    //     }
    //   } else {
    //     print("❌ Failed to seek electrical series, error code: $result");
    //     return Future.value(false);
    //   }
    // } finally {
    //   print("🔄 Freeing memory...");
      
    //   // Copy data from native memory to Dart lists (channel-major format)
    //   int samplesPerChannel = outSamplesCountPtr.value;
    //   int numChannelsToRead = endChannel - startChannel + 1;
    //   int totalDataPoints = samplesPerChannel * numChannelsToRead;
      
    //   // Set samples count for each channel
    //   for (int i = 0; i < outSamplesCount.length; i++) {
    //     outSamplesCount[i] = samplesPerChannel;
    //   }
      
    //   // Copy the channel-major data
    //   for (int i = 0; i < totalDataPoints && i < outSamples.length; i++) {
    //     outSamples[i] = outSamplesPtr[i];
    //   }
      
    //   // Copy configuration parameters
    //   outConfig.setAll(0, outConfigPtr.asTypedList(10));

    //   calloc.free(outSamplesPtr);
    //   calloc.free(outSamplesCountPtr);
    //   calloc.free(outConfigPtr);
    //   print("🔄 Freeing memory... Done");
    // }
    // return Future.value(true);
  }
  
  @override
  Future<String> startOpeningFileWeb(String filePath, int startIdx, int endIdx, int startChannel, int endChannel) async {
    js.context.callMethod('startOpeningFileWeb', [filePath, startIdx, endIdx, startChannel, endChannel, true]);
    return Future.value("");
  }
  
  @override
  Future<List<String>> fetchNwbFiles() {
    // TODO: implement fetchNwbFiles
    throw UnimplementedError();
  }
  

  
}

NWBFileUtil createNwbFileUtil() => NwbFileUtilImpl();