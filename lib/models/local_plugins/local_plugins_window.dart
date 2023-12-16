import 'dart:async';
import 'dart:typed_data';
import 'package:native_add/model/model.dart';
import 'package:native_add/native_add.dart' as native_add;
import 'package:spikerbox_architecture/models/models.dart';

class LocalPluginWindow implements LocalPlugin {
  final List<BufferHandlerOnDemand?> _bufferHandlerOnDemand =
      List.filled(channelCountBuffer, null);

  @override
  Future<void> spawnHelperIsolate() async {
    postFilterStream = postFilterStreamController.stream.asBroadcastStream();

    await native_add.spawnHelperIsolate();
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
      {required List<int> array,
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
  Future<bool> initNotchFilters(FilterSetup filterBaseSettingsModel) async {
    // native_add.SetUpNotchFilter();
    bool checkInit = native_add.initNotchPassFilter(filterBaseSettingsModel);
   
    return checkInit;
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
}
