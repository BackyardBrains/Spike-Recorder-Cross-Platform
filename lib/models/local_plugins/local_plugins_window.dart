import 'dart:async';
import 'dart:ffi';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:native_add/model/model.dart';
import 'package:native_add/native_add.dart' as native_add;
import 'package:processing_ffi/processing_ffi.dart' as pb;
import 'package:spikerbox_architecture/models/models.dart';
// import 'package:spikerbox_architecture/models/processing_utils/processing_bindings.dart';
import 'package:spikerbox_architecture/provider/graph_stream_data.dart';

class LocalPluginWindow implements LocalPlugin {
  final List<BufferHandlerOnDemand?> _bufferHandlerOnDemand =
      List.filled(channelCountBuffer, null);

  @override
  Future<void> spawnHelperIsolate() async {
    postFilterStream = postFilterStreamController.stream.asBroadcastStream();

    await native_add.spawnHelperIsolate();
    print("spawnHelperIsolate :  $channelCountBuffer");
    for (int i = 0; i < channelCountBuffer; i++) {
      _bufferHandlerOnDemand[i] = BufferHandlerOnDemand(
        onDataAvailable: (Uint8List newList) {
          onPacketAvailable(newList, i);
        },
      );
    }
  }

  @override
  Future<void> filterArrayElements(
      {required array,
      required int arrayLength,
      required int channelIdx}) async {
    _bufferHandlerOnDemand[channelIdx]
        ?.addBytes(Int16List.fromList(array).buffer.asUint8List());
    return;
  }

  @override
  Future<bool> initHighPassFilters(FilterSetup filterBaseSettingsModel) async {
    bool checkInit = native_add.initHighPassFilter(filterBaseSettingsModel);
    return checkInit;
  }

  @override
  Future<bool> initNotchPassFilters(FilterSetup filterBaseSettingsModel) async {
    // native_add.SetUpNotchFilter();
    // bool checkInit = native_add.initNotchPassFilter(filterBaseSettingsModel);
    if (filterBaseSettingsModel.isFilterOn) {
      if (filterBaseSettingsModel.filterConfiguration.cutOffFrequency == 50) {
        pb.processingBindings.setNotchFilter(50);
      } else 
      if (filterBaseSettingsModel.filterConfiguration.cutOffFrequency == 60) {
        pb.processingBindings.setNotchFilter(60);
      } else {
        pb.processingBindings.setNotchFilter(-1);
      }
    }
    // print("the init notch Pass filter is $checkInit");
    return true;
  }

  @override
  Future<bool> initLowPassFilters(FilterSetup filterBaseSettingsModel) async {
    bool checkInit = native_add.initLowPassFilter(filterBaseSettingsModel);
    return checkInit;
  }

  @override
  Stream<Uint8List>? postFilterStream;

  @override
  StreamController<Uint8List> postFilterStreamController =
      StreamController<Uint8List>();

  /// When another packet is available for processing from buffer
  void onPacketAvailable(Uint8List array, int channelIndex) async {
    _bufferHandlerOnDemand[channelIndex]?.toFetchBytes = false;

    Int16List listToFilter = array.buffer.asInt16List();
    Uint8List? filterElement = await native_add.filterArrayElements(
      array: listToFilter,
      length: listToFilter.length,
      channelIndex: channelIndex,
    );

    // TODO: currently data of all channels being added to the same stream
    postFilterStreamController.add(filterElement);

    onProcessingDone(channelIndex);
  }

  /// Called from JS when processing completed on a packet
  void onProcessingDone(dynamic channelIdx) {
    _bufferHandlerOnDemand[channelIdx]?.toFetchBytes = true;
    _bufferHandlerOnDemand[channelIdx]?.requestData();
  }

  @override
  Stream<Uint8List>? postDisplayStream;

  @override
  StreamController<Uint8List> postDisplayStreamController =
      StreamController<Uint8List>();
  
  int MAX_DISPLAY_SECONDS = 10000;
  
  int channelCount = 1;
  int sampleRate = 10000;
  int packetLen = 100000;
  
  @override
  Stream<int>? postChannelCountStream;
  
  @override
  // TODO: implement postChannelCountController
  StreamController<int> get postChannelCountController => throw UnimplementedError();

}
