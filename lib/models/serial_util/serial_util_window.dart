import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:spikerbox_architecture/models/serial_util/serial_baud_auto_probe.dart';

import 'serial_util_check.dart';

class SerialUtilWindow implements SerialUtil {
  @override
  bool isOpeningFile = false;
  SerialPort? port;
  int _baudRate = 0;

  @override
  int get detectedBaudRate => _baudRate;

  @override
  int vendorId = 0;
  @override
  int productId = 0;

  @override
  List<String> availablePorts = [];

  @override
  Stream<Uint8List>? dataStream;

  final SerialBaudAutoProbe _baudProbe =
      SerialBaudAutoProbe(logTag: 'SerialUtilWindow');

  @override
  Future<List<String>> startPortCheck(int baudRate) async {
    _baudRate = baudRate;
    availablePorts = SerialPort.availablePorts;
    return availablePorts;
  }

  @override
  Future<void> changePortBaudRate(int baudRate) async {}

  @override
  Future<void> getAvailablePorts(int baudRate, Function callback) async {
    availablePorts = await startPortCheck(baudRate);
  }

  @override
  void writeToPort({required Uint8List bytesMessage, String? address}) {
    final targetPort = address ?? port?.name;
    if (port?.name != targetPort) {
      return;
    }
    try {
      print("writing to port: ${utf8.decode(bytesMessage)}");
      final intsize = port?.write(bytesMessage, timeout: 1000);
      print("command is sent. Length: $intsize, cmd: $intsize");
    } catch (err, _) {
      port!.close();
      throw Exception("ERROR WRITING TO PORT: $err");
    }
  }

  bool _applyConfig(int baudRate) {
    final config = SerialPortConfig();
    try {
      print('SETTING CONFIG FOR BAUD RATE: $baudRate');
      config.baudRate = baudRate;
      config.bits = 8;
      config.stopBits = 1;
      config.parity = 0;
      config.setFlowControl(SerialPortFlowControl.none);
      config.dtr = SerialPortDtr.on;
      config.rts = SerialPortRts.on;
      port!.config = config;
      _baudRate = baudRate;
      return true;
    } catch (e) {
      print('SerialUtilWindow: baud $baudRate rejected: $e');
      return false;
    } finally {
      config.dispose();
    }
  }

  @override
  void setConfig() {
    if (!_applyConfig(_baudRate)) {
      throw StateError('Failed to set baud rate $_baudRate');
    }
  }

  bool _openPort(int requestedBaud) {
    var isOpen = port!.isOpen;
    if (!isOpen) {
      isOpen = port!.openReadWrite();
    }
    if (!isOpen) {
      return false;
    }
    if (!_applyConfig(requestedBaud)) {
      try {
        port!.close();
      } catch (_) {}
      return false;
    }
    return true;
  }

  void _releasePortSilently() {
    try {
      _probeReader?.close();
    } catch (_) {}
    _probeReader = null;
    try {
      reader?.close();
    } catch (_) {}
    reader = null;
    try {
      if (port != null && port!.isOpen) {
        port!.close();
      }
    } catch (_) {}
    port = null;
  }

  @override
  void setBaudRate(int baudRate) {
    _baudRate = baudRate;
  }

  @override
  Future<void> closePort() async {
    _releasePortSilently();
  }

  @override
  Future<void> connectToPort() async {}

  SerialPortReader? reader;
  SerialPortReader? _probeReader;
  StreamSubscription? serialBufferSubscription;

  Future<int?> _autoDetectBaudRate(String portName) async {
    return _baudProbe.detect(
      tryProbeBaud: (baud) => _baudProbe.probeAtBaud(
        baud: baud,
        openAtBaud: (b) async {
          _releasePortSilently();
          port = SerialPort(portName);
          return _openPort(b);
        },
        closePort: () async => _releasePortSilently(),
        writeQuery: () async {
          writeToPort(bytesMessage: SerialBaudAutoProbe.probeQueryBytes);
        },
        rxStream: () {
          if (port == null || !port!.isOpen) {
            return null;
          }
          try {
            _probeReader?.close();
          } catch (_) {}
          _probeReader = SerialPortReader(port!);
          return _probeReader!.stream;
        },
      ),
    );
  }

  Future<Stream<Uint8List>?> _openPortToListenAtBaud(
    String portName,
    int baudRate,
  ) async {
    _baudRate = baudRate;
    _releasePortSilently();
    port = SerialPort(portName);

    if (port?.name != portName) {
      return null;
    }
    if (!_openPort(baudRate)) {
      print('SerialUtilWindow: failed to open $portName @ $baudRate');
      _releasePortSilently();
      dataStream = null;
      return null;
    }
    await Future<void>.delayed(SerialBaudAutoProbe.probeSettleTime);
    reader = SerialPortReader(port!);
    dataStream = reader!.stream;
    return dataStream;
  }

  @override
  Future<Stream<Uint8List>?> openPortToListen(
    String? portName,
    int baudRate,
  ) async {
    if (serialBufferSubscription != null) {
      serialBufferSubscription?.cancel();
    }

    if (portName == null) {
      return null;
    }

    var effectiveBaud = baudRate;
    if (baudRate <= 0) {
      final detected = await _autoDetectBaudRate(portName);
      if (detected == null) {
        print(
          'SerialUtilWindow: no device response at supported baud rates '
          '(${SerialBaudAutoProbe.probeBaudRates})',
        );
        return null;
      }
      effectiveBaud = detected;
      print('SerialUtilWindow: baud (auto-detected): $effectiveBaud');
    }

    return _openPortToListenAtBaud(portName, effectiveBaud);
  }

  @override
  void streamListen({required Stream<Uint8List>? getData}) {
    try {
      getData?.listen((event) {
        final message = String.fromCharCodes(event);
        if (message.contains(':') && message.contains(';')) {}
      });
    } catch (e) {}
  }

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
