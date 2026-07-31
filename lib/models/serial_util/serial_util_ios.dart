import 'dart:async';
import 'dart:typed_data';

import 'serial_util_check.dart';

/// iOS uses External Accessory (MFi) via [BybAccessory], not desktop serial APIs.
/// This stub satisfies [SerialUtil] without invoking libserialport or platform_serial.
class SerialUtilIos implements SerialUtil {
  @override
  bool isOpeningFile = false;

  @override
  int get detectedBaudRate => 0;

  @override
  int vendorId = 0;
  @override
  int productId = 0;

  @override
  List<String> availablePorts = [];

  @override
  Stream<Uint8List>? dataStream;

  StreamSubscription? serialBufferSubscription;

  @override
  Future<List<String>> startPortCheck(int baudRate) async {
    availablePorts = [];
    return availablePorts;
  }

  @override
  Future<void> changePortBaudRate(int baudRate) async {}

  @override
  Future<void> getAvailablePorts(int baudRate, Function callback) async {
    availablePorts = await startPortCheck(baudRate);
  }

  @override
  void writeToPort({required Uint8List bytesMessage, String? address}) {}

  @override
  void setConfig() {}

  @override
  void setBaudRate(int baudRate) {}

  @override
  Future<void> closePort() async {
    dataStream = null;
  }

  @override
  Future<void> connectToPort() async {}

  @override
  Future<Stream<Uint8List>?> openPortToListen(
    String? portName,
    int baudRate, {
    List<int>? baudProbeCandidates,
  }) async {
    return null;
  }

  @override
  void streamListen({required Stream<Uint8List>? getData}) {}

  @override
  Future<List<String>> getAvailablePortsWeb(
    int baudRate,
    Function audioCallback,
  ) {
    return Future.value([]);
  }

  @override
  Stream<String?> deviceStatusStreamListener() {
    return Stream.empty();
  }

  @override
  Future<void> resetPort() {
    return Future.value();
  }
}
