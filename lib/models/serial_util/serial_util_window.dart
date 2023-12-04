import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'serial_util_check.dart';

class SerialUtilWindow implements SerialUtil {
  SerialPort? port;
  int _baudRate = 0;

  @override
  List<String> availablePorts = [];

  @override
  Stream<Uint8List>? dataStream;

  @override
  Future<List<String>> startPortCheck(int baudRate) async {
    // Timer.periodic(Duration(seconds: 5), (timer) {
    availablePorts = SerialPort.availablePorts;
    // });
    return availablePorts;
  }

  // get the list of current ports
  @override
  Future<void> getAvailablePorts(int baudRate) async {
    availablePorts = await startPortCheck(9600); // Adjust baudRate as needed

    // Wait for 5 seconds before the next check
  }

  @override
  void writeToPort({required Uint8List bytesMessage, String? address}) {
    if (port?.name == address) {
      try {
        final intsize = port?.write(bytesMessage);
        print("command is sent. Length: $intsize, cmd: ${intsize}");
      } catch (err, _) {
        port!.close();
      }
    }
  }

  @override
  void setConfig() {
    SerialPortConfig config = SerialPortConfig();
    config.baudRate = _baudRate;
    config.bits = 8;
    config.stopBits = 1;
    port!.config = config;
  }

  bool _openPort() {
    bool isOpen = false;
    if (!port!.isOpen) {
      isOpen = port!.openReadWrite();
    }
    setConfig();
    return isOpen;
  }

  @override
  void connectToPort() {}

  @override
  Future<Stream<Uint8List>?> openPortToListen(
      String? portName, int baudRate) async {
    _baudRate = baudRate;
    // checkEscapeSequence();
    if (portName == null) return null;
    port = SerialPort(portName);

    if (port?.name == portName) {
      if (!port!.isOpen) !_openPort();
      SerialPortReader reader = SerialPortReader(port!);
      return reader.stream.asBroadcastStream();
    }
    return null;
  }

  @override
  void streamListen({required Stream<Uint8List>? getData}) {
    try {
      getData?.listen((event) {
        String message = String.fromCharCodes(event);

        // print("serial received value: $event, as String: $message");
        //         escapdeinstance.addPacket(Uint8List.fromList(message.codeUnits));
        //         escapdeinstance.addPacket(Uint8List.fromList(message.codeUnits));
        //         if(message.contains(":")&&message.contains(";")){
        // print("the upcoming print is event ${event}, as String: $message");
        //         }
        // escapdeinstance.addPacket(Uint8List.fromList(message.codeUnits));
        // BitwiseUtil().readBytes(Uint8List.fromList([44,255,55,69]), 10);
        if (message.contains(":") && message.contains(";")) {}
      });
    } catch (e) {}
  }
}
