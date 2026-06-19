import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'package:spikerbox_architecture/models/serial_util/serial_baud_auto_probe.dart';
import 'package:spikerbox_architecture/models/serial_util/serial_port_read_pump.dart';

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

  SerialPortReadPump? _readPump;

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
    if (port == null || !port!.isOpen) {
      return;
    }
    if (address != null && port!.name != address) {
      return;
    }
    try {
      port!.write(bytesMessage, timeout: 1000);
    } catch (err, _) {
      unawaited(closePort());
      throw Exception('ERROR WRITING TO PORT: $err');
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

  void _stopReadPump() {
    _readPump?.dispose();
    _readPump = null;
  }

  Future<void> _releasePortSilently() async {
    _stopReadPump();
    try {
      if (port != null && port!.isOpen) {
        port!.close();
      }
    } catch (_) {}
    port = null;
    dataStream = null;
  }

  @override
  void setBaudRate(int baudRate) {
    _baudRate = baudRate;
  }

  @override
  Future<void> closePort() async {
    await _releasePortSilently();
  }

  @override
  Future<void> connectToPort() async {}

  StreamSubscription? serialBufferSubscription;

  Stream<Uint8List>? _attachReadPump() {
    if (port == null || !port!.isOpen) {
      return null;
    }
    _stopReadPump();
    _readPump = SerialPortReadPump(port!);
    return _readPump!.stream;
  }

  Future<bool> _probeBaudOnPort(String portName, int baud) {
    return _baudProbe.probeAtBaud(
      baud: baud,
      openAtBaud: (b) async {
        await _releasePortSilently();
        port = SerialPort(portName);
        return _openPort(b);
      },
      closePort: _releasePortSilently,
      writeQuery: () async {
        writeToPort(bytesMessage: SerialBaudAutoProbe.probeQueryBytes);
      },
      rxStream: _attachReadPump,
      stopRxStream: () async => _stopReadPump(),
    );
  }

  Future<int?> _autoDetectBaudRate(
    String portName, {
    List<int>? baudProbeCandidates,
  }) async {
    final tryProbe = (int baud) => _probeBaudOnPort(portName, baud);
    if (baudProbeCandidates != null && baudProbeCandidates.isNotEmpty) {
      return _baudProbe.detectWithCandidates(
        baudProbeCandidates,
        tryProbeBaud: tryProbe,
      );
    }
    return _baudProbe.detect(tryProbeBaud: tryProbe);
  }

  Future<Stream<Uint8List>?> _listenOnOpenPort(int baudRate) async {
    _baudRate = baudRate;
    _stopReadPump();

    if (port == null || !port!.isOpen) {
      print('SerialUtilWindow: listen aborted — port not open');
      dataStream = null;
      return null;
    }

    try {
      port!.flush(SerialPortBuffer.both);
    } catch (_) {}

    await Future<void>.delayed(SerialBaudAutoProbe.probeSettleTime);

    _readPump = SerialPortReadPump(port!);
    dataStream = _readPump!.stream;
    return dataStream;
  }

  @override
  Future<Stream<Uint8List>?> openPortToListen(
    String? portName,
    int baudRate, {
    List<int>? baudProbeCandidates,
  }) async {
    serialBufferSubscription?.cancel();

    if (portName == null) {
      return null;
    }

    if (baudRate <= 0) {
      print(
        'SerialUtilWindow: auto-detect on $portName '
        'candidates: ${baudProbeCandidates ?? SerialBaudAutoProbe.probeBaudRates}',
      );
      final detected = await _autoDetectBaudRate(
        portName,
        baudProbeCandidates: baudProbeCandidates,
      );
      if (detected == null) {
        print(
          'SerialUtilWindow: no device response at supported baud rates '
          '(${SerialBaudAutoProbe.probeBaudRates})',
        );
        return null;
      }
      print('SerialUtilWindow: baud (auto-detected): $detected');
      return _listenOnOpenPort(detected);
    }

    print('SerialUtilWindow: probing $portName @ $baudRate');
    if (!await _probeBaudOnPort(portName, baudRate)) {
      print('SerialUtilWindow: no device reply @ $baudRate on $portName');
      return null;
    }
    print('SerialUtilWindow: probe OK @ $baudRate on $portName');
    return _listenOnOpenPort(baudRate);
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
