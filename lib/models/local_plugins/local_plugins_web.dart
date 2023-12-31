import 'dart:async';
import 'dart:typed_data';
import 'package:native_add/model/model.dart';
import 'package:spikerbox_architecture/models/models.dart';
import 'package:spikerbox_architecture/models/local_plugins/local_plugins_check.dart';
import 'dart:js' as js;

LocalPlugin getLocalPlugins() => LocalPluginWeb();

class LocalPluginWeb implements LocalPlugin {
  FilterSetup? _highPassFilterSetup;
  FilterSetup? _lowPassFilterSetup;

  static final List<Int16List?> _dataBuffer =
      List.generate(channelCountBuffer, (index) => null);

  final List<BufferHandlerOnDemand?> _bufferHandlerOnDemand =
      List.generate(channelCountBuffer, (index) => null);

  /// Starts web worker
  ///
  /// Sets up buffer also
  @override
  Future<void> spawnHelperIsolate() async {
    postFilterStream = postFilterStreamController.stream.asBroadcastStream();
    for (int i = 0; i < channelCountBuffer; i++) {
      _bufferHandlerOnDemand[i] = BufferHandlerOnDemand(
        chunkReadSize: 4000,
        onDataAvailable: (Uint8List newList) {
          onPacketAvailable(newList, i);
        },
      );
    }
    js.context['onDataBufferAllocated'] = onDataBufferAllocated;
    js.context['onProcessingDone'] = onProcessingDone;
    js.context.callMethod("initializeModule", []);
  }

  @override
  Future<void> filterArrayElements(
      {required List<int> array,
      required int arrayLength,
      required int channelIdx}) async {
    Int16List iList = Int16List.fromList(array);

    // Add data to circular buffer
    _bufferHandlerOnDemand[channelIdx]?.addBytes(iList.buffer.asUint8List());
    return;
  }

  @override
  Future<bool> initHighPassFilters(FilterSetup filterBaseSettingsModel) async {
    _highPassFilterSetup = filterBaseSettingsModel;
    js.context.callMethod("sendToWebInitHighPassFilter", [
      filterBaseSettingsModel.channelCount,
      filterBaseSettingsModel.filterConfiguration.sampleRate,
      filterBaseSettingsModel.filterConfiguration.cutOffFrequency,
      0.5
    ]);
    return true;
  }

  @override
  Future<bool> initLowPassFilters(FilterSetup filterBaseSettingsModel) async {
    _lowPassFilterSetup = filterBaseSettingsModel;
    js.context.callMethod("sendToWebInitLowPassFilter", [
      filterBaseSettingsModel.channelCount,
      filterBaseSettingsModel.filterConfiguration.sampleRate,
      filterBaseSettingsModel.filterConfiguration.cutOffFrequency,
      0.5
    ]);
    return true;
  }

  Future<bool> initNotchPassFilters(FilterSetup filterBaseSettingsModel) async {
    return false;
  }

  @override
  Stream<Uint8List>? postFilterStream;

  @override
  StreamController<Uint8List> postFilterStreamController =
      StreamController<Uint8List>();

  /// When another packet is available for processing from buffer
  void onPacketAvailable(Uint8List packet, int channelIndex) {
    _bufferHandlerOnDemand[channelIndex]?.toFetchBytes = false;
    Int16List listFromBuffer = packet.buffer.asInt16List();
    if (_dataBuffer[channelIndex]!.isEmpty) {
      _bufferHandlerOnDemand[channelIndex]?.toFetchBytes = true;
      _bufferHandlerOnDemand[channelIndex]?.requestData();
      return;
    }

    for (int i = 0; i < listFromBuffer.length; i++) {
      _dataBuffer[channelIndex]![i] = listFromBuffer[i];
    }

    bool toApplyHighPass = false;
    bool toApplyLowPass = false;
    bool toApplyNotch = false;
    if (_highPassFilterSetup != null) {
      if (_highPassFilterSetup!.isFilterOn) {
        toApplyHighPass = true;
      }
    }
    if (_lowPassFilterSetup != null) {
      if (_lowPassFilterSetup!.isFilterOn) {
        toApplyLowPass = true;
      }
    }
    js.context.callMethod("sendToWorkerApplyFilter", [
      channelIndex,
      listFromBuffer.length,
      toApplyHighPass,
      toApplyLowPass,
      toApplyNotch,
    ]);
  }

  /// Called only once in the beginning to send address of buffer to dart
  void onDataBufferAllocated(Int16List dataBuffer, final channelIndex) {
    _dataBuffer[channelIndex] = dataBuffer;
  }

  /// Called from JS when processing completed on a packet
  void onProcessingDone(int channelIdx) {
    Int16List returnList = Int16List(_dataBuffer[channelIdx]?.length ?? 0);
    for (int i = 0; i < returnList.length; i++) {
      returnList[i] = _dataBuffer[channelIdx]![i];
    }

    postFilterStreamController.add(returnList.buffer.asUint8List());

    _bufferHandlerOnDemand[channelIdx]?.toFetchBytes = true;
    _bufferHandlerOnDemand[channelIdx]?.requestData();
  }
}
