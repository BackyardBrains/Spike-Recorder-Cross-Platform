import 'dart:typed_data';
import 'package:spikerbox_architecture/models/serial_util/serial_util.dart'
    if (dart.library.io) 'package:spikerbox_architecture/models/serial_util/serial_util_native.dart'
    if (dart.library.html) 'package:spikerbox_architecture/models/serial_util/serial_util_web.dart';

import '../../provider/provider_export.dart';

abstract class SerialUtil {
  factory SerialUtil() => getSerialUtil();

  Future<void> getAvailablePorts(int baudRate) async => [];

  void writeToPort({required Uint8List bytesMessage, String? address}) async {}

  void connectToPort() {}

  void setConfig() {}

  Future<Stream<Uint8List>?> openPortToListen(
      String? portName, int baudRate) async {
    return null;
  }

  List<String> availablePorts = [];

  Future<List<String>> startPortCheck(int baudRate) async {
    List<String> availablePorts = [];
    return availablePorts;
  }

  Stream<Uint8List>? dataStream;

  void streamListen({required Stream<Uint8List>? getData}) {}

  Future<void> deviceConnectWithPort(SampleRateProvider sampleRateProvider,
      ConstantProvider constantProvider) async {}
}
