import 'dart:async';
import 'package:flutter/services.dart';
import 'package:spikerbox_architecture/models/serial_util/serial_util_check.dart';
import 'package:usb_serial/usb_serial.dart';
import 'package:usb_serial/transaction.dart';

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
    if (devices.isEmpty) {
      print("No devices available to connect");
      return;
    }
    await _connectTo(devices.first);
  }

  @override
  void writeToPort({required Uint8List bytesMessage, String? address}) async {
    try {
      await _port!.write(Uint8List.fromList(bytesMessage));
    } catch (err, _) {
      try {
        await _port!.close();
      } catch (_) {
        // Ignore errors during cleanup
      }
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
    availablePorts = devices.map((e) {
      return e.deviceName;
    }).toList();

    return availablePorts;
  }

  /// Pass the device name to this function
  @override
  Future<Stream<Uint8List>?> openPortToListen(
      String? name, int baudRate) async {
    try {
      // Refresh device list before attempting connection to ensure we have the latest devices
      devices = await UsbSerial.listDevices();
      
      for (var element in devices) {
        print("element.deviceName: ${element.deviceName}");
        if (element.deviceName == name) {
          // Update devices list to ensure we're using the latest device reference
          devices = [element];
          await connectToPort();
          break;
        }
      }
      if (_port == null) {
        return null;
      } else {
        // Return the input stream - caller is responsible for cancelling the subscription
        return _port!.inputStream;
      }
    } catch (e) {
      print("Error in openPortToListen: $e");
      // Clean up on error
      _port = null;
      _device = null;
      return null;
    }
  }

  @override
  Future<void> getAvailablePorts(int baudRate, Function audioCallback) async {
    _baudRate = baudRate;

    availablePorts =
        await startPortCheck(_baudRate); // Adjust baudRate as needed
    // print("getAvailablePorts availablePorts: $availablePorts");
  }

  @override
  void setConfig() {
    // TODO: implement setConfig
  }

  @override
  void streamListen({required Stream<Uint8List>? getData}) {
    // TODO: implement streamListen
  }

  @override
  void closePort() {
    print("closePort!!!");
    
    // Cancel other subscriptions first
    _subscription?.cancel().then((_) {
      _subscription = null;
    }).catchError((e) {
      print("Error cancelling subscription: $e");
    });
    
    // Dispose transaction
    _transaction?.dispose();
    _transaction = null;
    
    // Close the port - this should close all USB requests including those from inputStream
    // The caller should cancel their stream subscription before calling closePort()
    _port?.close().then((_) {
      _port = null;
      _device = null;
    }).catchError((e) {
      print("Error closing port: $e");
      _port = null;
      _device = null;
    });
  }

  Future<bool> _connectTo(device) async {
    if (_subscription != null) {
      await _subscription!.cancel();
      _subscription = null;
    }

    if (_transaction != null) {
      _transaction!.dispose();
      _transaction = null;
    }

    if (_port != null) {
      try {
        await _port!.close();
      } catch (e) {
        print("Error closing port in _connectTo: $e");
      }
      _port = null;
    }
    // print("device ConnectTo: $device");
    if (device == null) {
      _device = null;

      return true;
    }

    try {
      _port = await device.create();
      if (_port == null) {
        print("Failed to create port from device");
        _device = null;
        return false;
      }
      
      if (await (_port!.open()) != true) {
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
          _baudRate, UsbPort.DATABITS_8, UsbPort.STOPBITS_1, UsbPort.PARITY_NONE);

      // _transaction = Transaction.stringTerminated(_port!.inputStream as Stream<Uint8List>, Uint8List.fromList([13, 10]));
      // _transaction!.stream.listen((line){ });

      return true;
    } on PlatformException catch (e) {
      print("PlatformException in _connectTo: ${e.code} - ${e.message}");
      // Handle "No such device" error gracefully
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
}
