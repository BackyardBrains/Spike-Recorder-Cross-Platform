import 'dart:async';
import 'dart:typed_data';
import 'package:native_add/model/model.dart';
import 'package:spikerbox_architecture/models/local_plugins/local_plugins.dart'
    if (dart.library.io) 'package:spikerbox_architecture/models/local_plugins/local_plugins_native.dart'
    if (dart.library.html) 'package:spikerbox_architecture/models/local_plugins/local_plugins_web.dart';

abstract class LocalPlugin {
  factory LocalPlugin() => getLocalPlugins();

  final StreamController<Uint8List> postFilterStreamController =
      StreamController<Uint8List>();

  /// To be listened only after call [spawnHelperIsolate]
  Stream<Uint8List>? postFilterStream;

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
      {required List<int> array,
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

  Future<bool> initNotchFilters(FilterSetup filterBaseSettingsModel) async {
    return false;
  }

  void setEnvelopConfigure(int duration) {}
}
