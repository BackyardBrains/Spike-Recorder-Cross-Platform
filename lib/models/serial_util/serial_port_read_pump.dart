import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_libserialport/flutter_libserialport.dart';

/// Main-isolate serial RX pump with capped reads.
///
/// Avoids [SerialPortReader]'s background isolate, which can crash on Windows
/// when [SerialPort.bytesAvailable] returns oversized values on FTDI devices.
class SerialPortReadPump {
  SerialPortReadPump(
    this.port, {
    this.maxChunkSize = 8192,
    this.pollInterval = const Duration(milliseconds: 2),
  });

  final SerialPort port;
  final int maxChunkSize;
  final Duration pollInterval;

  StreamController<Uint8List>? _controller;
  Timer? _timer;
  int _listenerCount = 0;

  Stream<Uint8List> get stream {
    _controller ??= StreamController<Uint8List>.broadcast(
      onListen: _onListen,
      onCancel: _onCancel,
    );
    return _controller!.stream;
  }

  void _onListen() {
    _listenerCount++;
    if (_listenerCount == 1) {
      _timer ??= Timer.periodic(pollInterval, (_) => _poll());
    }
  }

  void _onCancel() {
    _listenerCount--;
    if (_listenerCount <= 0) {
      _listenerCount = 0;
      _timer?.cancel();
      _timer = null;
    }
  }

  void _poll() {
    if (!port.isOpen) {
      return;
    }
    try {
      final available = port.bytesAvailable;
      if (available <= 0) {
        return;
      }
      final toRead = available > maxChunkSize ? maxChunkSize : available;
      if (toRead <= 0) {
        return;
      }
      final data = port.read(toRead, timeout: 0);
      if (data.isEmpty) {
        return;
      }
      final controller = _controller;
      if (controller != null && !controller.isClosed) {
        controller.add(data);
      }
    } catch (e, st) {
      final controller = _controller;
      if (controller != null && !controller.isClosed) {
        controller.addError(e, st);
      }
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _listenerCount = 0;
    final controller = _controller;
    _controller = null;
    controller?.close();
  }
}
