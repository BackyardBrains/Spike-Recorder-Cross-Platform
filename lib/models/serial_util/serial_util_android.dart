import 'dart:async';

import 'package:flutter/services.dart';
import 'package:spikerbox_architecture/models/serial_util/serial_baud_auto_probe.dart';
import 'package:spikerbox_architecture/models/serial_util/serial_util_check.dart';
import 'package:usb_serial/usb_serial.dart';
import 'package:usb_serial/transaction.dart';

class SerialUtilAndroid implements SerialUtil {
  @override
  bool isOpeningFile = false;
  UsbPort? _port;
  UsbDevice? _device;
  StreamSubscription<String>? _subscription;
  Transaction<String>? _transaction;
  List<UsbDevice> devices = [];
  int _baudRate = 0;

  @override
  int get detectedBaudRate => _baudRate;

  @override
  int vendorId = 0;
  @override
  int productId = 0;

  final SerialBaudAutoProbe _baudProbe =
      SerialBaudAutoProbe(logTag: 'SerialUtilAndroid');

  @override
  Future<void> changePortBaudRate(int baudRate) async {}

  @override
  Future<void> connectToPort() async {
    if (devices.isEmpty) {
      print("No devices available to connect");
      return;
    }
    final detected = await _autoDetectBaudForDevice(devices.first);
    if (detected == null) {
      print(
        'SerialUtilAndroid: no device response at supported baud rates '
        '(${SerialBaudAutoProbe.probeBaudRates})',
      );
      return;
    }
    _baudRate = detected;
    print('SerialUtilAndroid: baud (auto-detected): $_baudRate');
    if (_port == null) {
      await _connectTo(devices.first);
    }
  }

  @override
  void writeToPort({required Uint8List bytesMessage, String? address}) async {
    try {
      await _port!.write(Uint8List.fromList(bytesMessage));
    } catch (err, _) {
      try {
        await _port!.close();
      } catch (_) {}
      _port = null;
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
    availablePorts = devices.map((e) => e.deviceName).toList();

    return availablePorts;
  }

  Future<int?> _autoDetectBaudForDevice(
    UsbDevice device, {
    List<int>? baudProbeCandidates,
  }) async {
    final tryProbe = (int baud) => _baudProbe.probeAtBaud(
          baud: baud,
          openAtBaud: (b) async {
            await _closePortSilently();
            _baudRate = b;
            return _connectTo(device);
          },
          closePort: _closePortSilently,
          writeQuery: () async {
            writeToPort(bytesMessage: SerialBaudAutoProbe.probeQueryBytes);
          },
          rxStream: () => _port?.inputStream,
        );
    if (baudProbeCandidates != null && baudProbeCandidates.isNotEmpty) {
      return _baudProbe.detectWithCandidates(
        baudProbeCandidates,
        tryProbeBaud: tryProbe,
      );
    }
    return _baudProbe.detect(tryProbeBaud: tryProbe);
  }

  @override
  Future<Stream<Uint8List>?> openPortToListen(
    String? name,
    int baudRate, {
    List<int>? baudProbeCandidates,
  }) async {
    try {
      devices = await UsbSerial.listDevices();

      for (final element in devices) {
        if (element.deviceName != name) {
          continue;
        }
        devices = [element];
        if (baudRate <= 0) {
          final detected = await _autoDetectBaudForDevice(
            element,
            baudProbeCandidates: baudProbeCandidates,
          );
          if (detected == null) {
            return null;
          }
          _baudRate = detected;
          print('SerialUtilAndroid: baud (auto-detected): $_baudRate');
          if (_port != null) {
            return _port!.inputStream;
          }
          return null;
        }
        _baudRate = baudRate;
        if (!await _connectTo(element)) {
          return null;
        }
        return _port!.inputStream;
      }
      return null;
    } catch (e) {
      print("Error in openPortToListen: $e");
      _port = null;
      _device = null;
      throw Exception("Error in openPortToListen: $e");
    }
  }

  @override
  Future<void> getAvailablePorts(int baudRate, Function audioCallback) async {
    _baudRate = baudRate;
    availablePorts = await startPortCheck(_baudRate);
  }

  @override
  void setConfig() {}

  @override
  void setBaudRate(int baudRate) {
    _baudRate = baudRate;
  }

  @override
  void streamListen({required Stream<Uint8List>? getData}) {}

  Future<void> _closePortSilently() async {
    try {
      await _subscription?.cancel();
    } catch (_) {}
    _subscription = null;

    _transaction?.dispose();
    _transaction = null;

    try {
      await _port?.close();
    } catch (_) {}
    _port = null;
  }

  @override
  Future<void> closePort() async {
    print("closePort!!!");
    await _closePortSilently();
    _device = null;
  }

  Future<bool> _connectTo(UsbDevice? device) async {
    if (device == null) {
      _device = null;
      return true;
    }

    try {
      await _subscription?.cancel();
    } catch (_) {}
    _subscription = null;

    _transaction?.dispose();
    _transaction = null;

    if (_port != null) {
      try {
        await _port!.close();
      } catch (_) {}
      _port = null;
    }

    try {
      _port = await device.create();
      if (_port == null) {
        print("Failed to create port from device");
        _device = null;
        return false;
      }

      if (await _port!.open() != true) {
        print("Failed to open port");
        _port = null;
        _device = null;
        return false;
      }
      _device = device;

      await _port!.setDTR(true);
      await _port!.setRTS(true);
      print("the baudRate is $_baudRate");
      await _port!.setPortParameters(
        _baudRate,
        UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
        UsbPort.PARITY_NONE,
      );

      return true;
    } on PlatformException catch (e) {
      print("PlatformException in _connectTo: ${e.code} - ${e.message}");
      _port = null;
      _device = null;
      return false;
    } catch (e) {
      print("Unexpected error in _connectTo: $e");
      _port = null;
      _device = null;
      return false;
    }
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
    return UsbSerial.usbEventStream?.map((event) => event.event) ??
        Stream.empty();
  }
  
  @override
  Future<void> resetPort() {
    // TODO: implement resetPort
    throw UnimplementedError();
  }
}
