import 'dart:async';
import 'dart:html';
import 'package:flutter/services.dart';
import 'package:serial/serial.dart';
import 'package:spikerbox_architecture/models/debugging.dart';
import '../../provider/provider_export.dart';
import 'serial_util_check.dart';

SerialUtil getSerialUtil() => SerialUtilWeb();

class SerialUtilWeb implements SerialUtil {
  SerialPort? _port;
  SerialPortInfo? portInfo;

  StreamController<Uint8List> streamController = StreamController();
  @override
  Stream<Uint8List>? dataStream;

  WritableStreamDefaultWriter? writer;
  bool isPortOpen = false;
  int _baudRate = 500000;
  ReadableStreamReader? reader;
  bool isListenPort = false;
  ReadableStream? readable;
  bool isSetBaudRate = false;

  @override
  Future<void> connectToPort() async {
    final port1 = await window.navigator.serial.requestPort();

    try {
      await port1.open(
        baudRate: _baudRate,
      );

      isPortOpen = true;
    } catch (e) {
      print("Port opening failed: $e");
    }
    portInfo = port1.getInfo();
    int? pid = portInfo?.usbProductId;
    await setBaudRate(pid);

    await port1.close();
    _port = await window.navigator.serial.requestPort();

    try {
      await _port?.open(
        baudRate: _baudRate,
        dataBits: DataBits.eight,
        stopBits: StopBits.one,
        bufferSize: 255,
        flowControl: FlowControl.hardware,
      );
      isSetBaudRate = true;

      // isPortOpen = true;
    } catch (e) {
      print("Port opening failed: $e");
    }

    if (isSetBaudRate) {
      portInfo = _port?.getInfo();
      openPortToListen(" ", _baudRate);
    }
  }

  @override
  void writeToPort({required Uint8List bytesMessage, String? address}) async {
    if (_port == null) {
      return;
    }

    writer ??= _port!.writable.writer;

    await writer!.ready;
    await writer!.write(bytesMessage);
    await writer!.ready;
    await writer!.close();
    Debugging.printing("message sent : ${String.fromCharCodes(bytesMessage)}");
  }

  final startTime = DateTime.now();

  @override
  List<String> availablePorts = [];

  @override
  Future<List<String>> startPortCheck(int baudRate) async {
    List<String> availablePorts = [];
    return availablePorts;
  }

  @override
  Future<Stream<Uint8List>?> openPortToListen(
      String? name, int baudRate) async {
    _baudRate = baudRate;
    if (_port == null) {
      return null;
    }

    try {
      readable = _port!.readable;

      reader = readable?.reader;
      if (streamController.stream.isBroadcast) {
        streamController.close();
        dataStream = streamController.stream.asBroadcastStream();
      } else {
        dataStream = streamController.stream.asBroadcastStream();
      }
      isListenPort = true;

      while (isListenPort) {
        ReadableStreamDefaultReadResult result = await reader!.read();

        final currentTime = DateTime.now();
        currentTime.difference(startTime);
        if (result.value.isNotEmpty) {
          streamController.add(result.value.buffer.asUint8List());
        }
      }
    } catch (e) {
      print("Reading port failed with exception: \n$e");
      return null;
    }
    return null;
  }

  /// Connection is directly established with the selected port
  @override
  Future<void> getAvailablePorts(int baudRate) async {
    _baudRate = baudRate;
    await connectToPort();

    availablePorts = [_port!.getInfo().usbProductId!.toString()];
  }

  @override
  void setConfig() {
    // TODO: implement setConfig
  }

  @override
  void streamListen({required Stream<Uint8List>? getData}) {
    // TODO: implement streamListen
  }

  Future<void> closePort() async {
    try {
      // Release the reader lock first
      isListenPort = false;
      if (reader != null) {
        print("the port is Listen $isListenPort");
        reader?.releaseLock();
        readable?.close();
      }

      // Close the serial port
      if (_port != null) {
        await _port!.close();
      }

      _port = null; // Reset the port reference
    } catch (e) {
      print("Error closing port: $e");
    }
  }

  @override
  Future<void> deviceConnectWithPort(SampleRateProvider sampleRateProvider,
      ConstantProvider constantProvider) async {
    int? productId = portInfo!.usbProductId;

    print("the manufacture is $productId");
  }

  Future<void> setBaudRate(int? pid) async {
    if (pid == 24597) {
      print("the manufacture is $pid");
      _baudRate = 500000;
    } else {
      _baudRate = 222222;
    }
  }
}
