import 'dart:async';
import 'dart:typed_data';

import 'package:libserialport_plus/libserialport_plus.dart';
import 'package:spikerbox_architecture/models/serial_util/serial_baud_auto_probe.dart';

import 'serial_util_check.dart';

class SerialUtilIos implements SerialUtil {
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
      SerialBaudAutoProbe(logTag: 'SerialUtilIos');

  SerialPortReader? reader;
  SerialPortReader? _probeReader;
  StreamSubscription? serialBufferSubscription;

  @override
  Future<List<String>> startPortCheck(int baudRate) async {
    _baudRate = baudRate;
    availablePorts = SerialPort.getAvailablePorts();
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
    if (port == null || !port!.isOpen()) {
      return;
    }
    if (address != null && port!.getInfo().name != address) {
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
    try {
      print('SETTING CONFIG FOR BAUD RATE: $baudRate');
      port!.setConfig(
        SerialPortConfig(
          baudRate: baudRate,
          bits: 8,
          parity: SerialPortParity.none,
          stopBits: 1,
          rts: SerialPortRts.on,
          dtr: SerialPortDtr.on,
        ),
      );
      _baudRate = baudRate;
      return true;
    } catch (e) {
      print('SerialUtilIos: baud $baudRate rejected: $e');
      return false;
    }
  }

  @override
  void setConfig() {
    if (!_applyConfig(_baudRate)) {
      throw StateError('Failed to set baud rate $_baudRate');
    }
  }

  bool _openPort(int requestedBaud) {
    var isOpen = port!.isOpen();
    if (!isOpen) {
      port!.open();
      isOpen = port!.isOpen();
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

  Future<void> _stopProbeReader() async {
    try {
      await _probeReader?.close();
    } catch (_) {}
    _probeReader = null;
  }

  Future<void> _stopListenReader() async {
    try {
      await reader?.close();
    } catch (_) {}
    reader = null;
  }

  Future<void> _stopReaders() async {
    await _stopProbeReader();
    await _stopListenReader();
  }

  Future<void> _releasePortSilently() async {
    await _stopReaders();
    try {
      if (port != null && port!.isOpen()) {
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

  Stream<Uint8List>? _attachReadPump() {
    if (port == null || !port!.isOpen()) {
      return null;
    }
    unawaited(_stopProbeReader());
    _probeReader = SerialPortReader(port!);
    return _probeReader!.stream;
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
      stopRxStream: _stopProbeReader,
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
    await _stopListenReader();

    if (port == null || !port!.isOpen()) {
      print('SerialUtilIos: listen aborted — port not open');
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
    int baudRate, {
    List<int>? baudProbeCandidates,
  }) async {
    serialBufferSubscription?.cancel();

    if (portName == null) {
      return null;
    }

    if (baudRate <= 0) {
      print(
        'SerialUtilIos: auto-detect on $portName '
        'candidates: ${baudProbeCandidates ?? SerialBaudAutoProbe.probeBaudRates}',
      );
      final detected = await _autoDetectBaudRate(
        portName,
        baudProbeCandidates: baudProbeCandidates,
      );
      if (detected == null) {
        print(
          'SerialUtilIos: no device response at supported baud rates '
          '(${SerialBaudAutoProbe.probeBaudRates})',
        );
        return null;
      }
      print('SerialUtilIos: baud (auto-detected): $detected');
      return _listenOnOpenPort(detected);
    }

    print('SerialUtilIos: probing $portName @ $baudRate');
    if (!await _probeBaudOnPort(portName, baudRate)) {
      print('SerialUtilIos: no device reply @ $baudRate on $portName');
      return null;
    }
    print('SerialUtilIos: probe OK @ $baudRate on $portName');
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
