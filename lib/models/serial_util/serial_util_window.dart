// ignore_for_file: empty_catches

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:spikerbox_architecture/provider/provider_export.dart';
import '../../functionality/functionality_export.dart';
import '../default_config_model.dart';
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
    availablePorts = SerialPort.availablePorts;

    return availablePorts;
  }

  // get the list of current ports
  @override
  Future<void> getAvailablePorts(int baudRate) async {
    availablePorts = await startPortCheck(9600); // Adjust baudRate as needed

    // Wait for 3 seconds before the next check
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
    port?.close();
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

  @override
  Future<void> deviceConnectWithPort(SampleRateProvider sampleRateProvider,
      ConstantProvider constantProvider) async {
    port = SerialPort(availablePorts.last);

    Config deviceConfig = await SetUpFunctionality().getAllDeviceList();
    List<Board> allBoards = deviceConfig.boards ?? [];
    if (port?.productName == "Human Human Interface") {
      Board matchingBoards = allBoards.firstWhere((board) {
        return board.userFriendlyFullName == port?.productName;
      });

      sampleRateProvider
          .setSampleRate(int.parse(matchingBoards.maxSampleRate.toString()));
      constantProvider.setBaudRate(500000);
    } else if (port?.productId == 29597) {
    } else {
      constantProvider.setBaudRate(222222);
    }

    // port!.name;
    // final devices = SerialPort.fromAddress(port!.address);
    // devices.name;

    // print(
    //     "the macAddress ${devices.macAddress}, busNumber ${devices.busNumber}, vendorid ${devices.vendorId},serial number ${devices.serialNumber}, address ${devices.address} ComName ${devices.name}, manufacture ${devices.manufacturer} and product name ${devices.productName}");
    // devices.productName;
  }
}
