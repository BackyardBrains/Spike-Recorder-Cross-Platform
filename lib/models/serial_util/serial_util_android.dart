import 'dart:async';
import 'package:flutter/services.dart';
import 'package:spikerbox_architecture/models/serial_util/serial_util_check.dart';
import 'package:usb_serial/usb_serial.dart';
import 'package:usb_serial/transaction.dart';

import '../../functionality/functionality_export.dart';
import '../../provider/provider_export.dart';
import '../default_config_model.dart';

// import 'package:serial_communication/serial_communication.dart';

class SerialUtilAndroid implements SerialUtil {
  UsbPort? _port;
  UsbDevice? _device;
  StreamSubscription<String>? _subscription;
  Transaction<String>? _transaction;
  List<UsbDevice> devices = [];
  int _baudRate = 0;

  @override
  Future<void> connectToPort() async {
    await _connectTo(devices.first);
  }

  @override
  void writeToPort({required Uint8List bytesMessage, String? address}) async {
    try {
      await _port!.write(Uint8List.fromList(bytesMessage));
    } catch (err, _) {
      _port!.close();
    }
  }

  @override
  Stream<Uint8List>? dataStream;

  @override
  List<String> availablePorts = [];

  @override
  Future<List<String>> startPortCheck(int baudRate) async {
    devices = await UsbSerial.listDevices();

    if (!devices.contains(_device)) {
      await _connectTo(null);
    }
    availablePorts = devices.map((e) {
      return e.deviceName;
    }).toList();

    return availablePorts;
  }

  /// Pass the device name to this function
  @override
  Future<Stream<Uint8List>?> openPortToListen(
      String? name, int baudRate) async {
    for (var element in devices) {
      if (element.deviceName == name) {
        _baudRate = baudRate;

        await connectToPort();
        break;
      }
    }
    if (_port == null) {
      return null;
    } else {
      return _port!.inputStream;
    }
  }

  @override
  Future<void> getAvailablePorts(int baudRate) async {
    availablePorts =
        await startPortCheck(_baudRate); // Adjust baudRate as needed
  }

  @override
  void setConfig() {
    // TODO: implement setConfig
  }

  @override
  void streamListen({required Stream<Uint8List>? getData}) {
    // TODO: implement streamListen
  }

  Future<bool> _connectTo(device) async {
    if (_subscription != null) {
      _subscription!.cancel();
      _subscription = null;
    }

    if (_transaction != null) {
      _transaction!.dispose();
      _transaction = null;
    }

    if (_port != null) {
      _port!.close();
      _port = null;
    }

    if (device == null) {
      _device = null;

      return true;
    }

    _port = await device.create();

    if (await (_port!.open()) != true) {
      return false;
    }
    _device = device;

    await _port!.setDTR(true);
    await _port!.setRTS(true);
    print("the baudRate is $_baudRate");
    await _port!.setPortParameters(
        _baudRate, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);

    // _transaction = Transaction.stringTerminated(_port!.inputStream as Stream<Uint8List>, Uint8List.fromList([13, 10]));
    // _transaction!.stream.listen((line){ });

    return true;
  }

  @override
  Future<void> deviceConnectWithPort(SampleRateProvider sampleRateProvider,
      ConstantProvider constantProvider) async {
    devices = await UsbSerial.listDevices();
    print("the devices is ${devices.first.productName}");

    Config deviceConfig = await SetUpFunctionality().getAllDeviceList();
    List<Board> allBoards = deviceConfig.boards ?? [];
    if (devices.last.productName == "Human Human Interface") {
      Board matchingBoards = allBoards.firstWhere((board) {
        return board.userFriendlyFullName == devices.first.productName;
      });

      sampleRateProvider
          .setSampleRate(int.parse(matchingBoards.maxSampleRate.toString()));
      constantProvider.setBaudRate(500000);
    } else {
      constantProvider.setBaudRate(222222);
    }
  }
}
