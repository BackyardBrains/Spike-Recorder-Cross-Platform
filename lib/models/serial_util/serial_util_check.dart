import 'dart:typed_data';
import 'package:spikerbox_architecture/models/serial_util/serial_util.dart'
    if (dart.library.io) 'package:spikerbox_architecture/models/serial_util/serial_util_native.dart'
    if (dart.library.html) 'package:spikerbox_architecture/models/serial_util/serial_util_web.dart';

abstract class SerialUtil {
  factory SerialUtil() => getSerialUtil();
  bool isOpeningFile = false;

  int vendorId = 0;
  int productId = 0;

  // static SerialPort? serialPort;

  Future<void> getAvailablePorts(int baudRate, Function audioCallback) async => [];
  Future<List<String>> getAvailablePortsWeb(int baudRate, Function audioCallback) async => [];

  void writeToPort({required Uint8List bytesMessage, String? address}) async {}
  Future<void> changePortBaudRate(int baudRate) async {}
  void connectToPort() {}
  void closePort() {}

  void setConfig() {}

  Future<Stream<Uint8List>?> openPortToListen(
      String? portName, int baudRate) async {
    return null;
  }

  Stream<String?> deviceStatusStreamListener();

  List<String> availablePorts = [];

  Future<List<String>> startPortCheck(int baudRate) async {
    List<String> availablePorts = [];
    return availablePorts;
  }

  Stream<Uint8List>? dataStream;

  void streamListen({required Stream<Uint8List>? getData}) {}
}
