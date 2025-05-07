import 'dart:async';
import 'dart:typed_data';
import 'package:native_add/model/model.dart';
import 'package:spikerbox_architecture/models/default_config_model.dart';
import 'package:spikerbox_architecture/models/local_plugins/local_plugins.dart'
    if (dart.library.io) 'package:spikerbox_architecture/models/local_plugins/local_plugins_native.dart'
    if (dart.library.html) 'package:spikerbox_architecture/models/local_plugins/local_plugins_web.dart';
// import 'package:spikerbox_architecture/models/processing_utils/processing_bindings.dart';
import 'package:spikerbox_architecture/provider/graph_stream_data.dart';

abstract class LocalPlugin {
  factory LocalPlugin() => getLocalPlugins();

  final StreamController<Uint8List> postFilterStreamController =
      StreamController<Uint8List>();

  /// To be listened only after call [spawnHelperIsolate]
  Stream<Uint8List>? postFilterStream;

  final StreamController<Uint8List> postDisplayStreamController =
      StreamController<Uint8List>();

  /// To be listened only after call [spawnHelperIsolate]
  Stream<Uint8List>? postDisplayStream;


  /// Spawns helper Isolate on windows, macOS, android, iOS
  ///
  /// Spawns helper Web Worker on Web
  Future<void> spawnHelperIsolate() async {}

  /// Add packet to circular buffer for filtering
  ///
  /// [array] should be the list of Int16 on which filtering needs to be done
  ///
  /// [arrayLength] is the number of Int16 values in [array]
  Future<void> filterArrayElements(
      {required array,
      required int arrayLength,
      required int channelIdx}) async {
    return;
  }

  /// Initialise or modify high pass filter settings
  Future<bool> initHighPassFilters(FilterSetup filterBaseSettingsModel) async {
    return false;
  }

  /// Initialise or modify high pass filter settings
  Future<bool> initLowPassFilters(FilterSetup filterBaseSettingsModel) async {
    return false;
  }

  Future<bool> initNotchPassFilters(FilterSetup filterBaseSettingsModel) async {
    return false;
  }

  // int MAX_DISPLAY_SECONDS = 10000;
  
  // int channelCount = 1;
  // int sampleRate = 10000;
  // int packetLen = 100000;


  // void initializeSerial(Board board) {
    
  //   print("Initialize Serial");
  //   print(board);
  //   channelCount = int.parse(board.maxNumberOfChannels!);
  //   sampleRate = int.parse(board.maxSampleRate!);
  //   packetLen = sampleRate * MAX_DISPLAY_SECONDS;
  //   ProcessingBindings.instance.setChannelCount(channelCount);
  //   ProcessingBindings.instance.setSampleRate(sampleRate);

  // }
  // void processSerialData(Uint8List samples, int displayTimeMs, int deviceType, int drawSurfaceWidth, GraphDataProvider provider) {
  //   final outSamplesPtr = calloc<Pointer<Int16>>(channelCount);
  //   for (int i = 0; i < channelCount; i++) {
  //       outSamplesPtr[i] = calloc<Int16>(drawSurfaceWidth * 5); // 5x for envelope
  //   }

  //   final outSampleCountsPtr = calloc<Int32>(channelCount);

	// 	try {
	// 		// Prepare input data pointer
	// 		final inDataPtr = calloc<Uint8>(samples.length);
	// 		for (int i = 0; i < samples.length; i++) {
	// 			inDataPtr[i] = samples[i];
	// 		}
  //     ProcessingBindings.instance.processSampleStream(outSamplesPtr, outSampleCountsPtr, inDataPtr, samples.length, deviceType);
  //     calloc.free(inDataPtr);
  //   }catch (err) {
  //     print(err);
  //   }


  //   // Allocate memory for sample counts

  //   // Allocate memory for event indices (assuming max 100 events)
  //   final outEventIndicesPtr = calloc<Float>(100);

  //   // Allocate memory for event count
  //   final outEventCountPtr = calloc<Int32>(1);

  //   // Allocate and prepare input event indices
  //   final inEventIndicesPtr = calloc<Int32>(0); // No events yet

  //   try {
  //     int result = ProcessingBindings.instance.prepareForSignalDrawing(outSamplesPtr, outSampleCountsPtr, outEventIndicesPtr, outEventCountPtr, inEventIndicesPtr, 0, 0, (displayTimeMs*0.001 * sampleRate).toInt(), drawSurfaceWidth);
  //     if (result == 0) {
  //       int sampleCount = outSampleCountsPtr.value;
  //       Int16List channelData = outSamplesPtr[0].asTypedList(sampleCount);
  //       Uint8List uint8Data = Uint8List.view(channelData.buffer);
  //       int eventCount = outEventCountPtr.value;
  //       if (eventCount > 0) {
  //         Float32List eventIndices = outEventIndicesPtr.asTypedList(eventCount);
  //       }
  //     }      
  //   }catch(err) {

  //   } finally {
  //     for (int i = 0; i < channelCount; i++) {
  //         calloc.free(outSamplesPtr[i]);
  //     }
  //     calloc.free(outSamplesPtr);
  //     calloc.free(outSampleCountsPtr);
  //     calloc.free(outEventIndicesPtr);
  //     calloc.free(outEventCountPtr);
  //     calloc.free(inEventIndicesPtr);      
  //   }

  // }


}
