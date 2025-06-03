import 'dart:async';
import 'dart:html';
import 'package:flutter/services.dart';
import 'package:serial/serial.dart';
import 'package:spikerbox_architecture/models/debugging.dart';

// import '../escape_sequences/escape_sequence.dart';
import 'serial_util_check.dart';

SerialUtil getSerialUtil() => SerialUtilWeb();

class SerialUtilWeb implements SerialUtil {
  SerialPort? _port;
  SerialPortInfo? portInfo;
  Function? audioCallback;

  StreamController<Uint8List> streamController = StreamController();
  @override
  Stream<Uint8List>? dataStream;

  WritableStreamDefaultWriter? writer;

  int _baudRate = 0;

  @override
  Future<void> connectToPort() async {
    _port = await window.navigator.serial.requestPort();

    try {
      await _port?.open(
        baudRate: _baudRate,
        bufferSize: 8192,
      );
    } catch (e) {
      print("Port opening failed: $e");
    }
    portInfo = _port?.getInfo();
    openPortToListen(" ", _baudRate);
  }

  @override
  void closePort() {
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
    Debugging.printing("message sent : ${String.fromCharCodes(bytesMessage)}");
  }

  @override
  List<String> availablePorts = [];

  @override
  Future<List<String>> startPortCheck(int baudRate) async {
    List<String> availablePorts = [];

    return availablePorts;
  }

  ReadableStreamReader? reader;
  @override
  Future<Stream<Uint8List>?> openPortToListen(
      String? name, int baudRate) async {
    _baudRate = baudRate;
    if (_port == null) {
      return null;
    }
    try {
      reader = _port!.readable.reader;
      streamController = StreamController();
      dataStream = streamController.stream.asBroadcastStream();

      // continuouslyReadData(reader: reader);
      while (true) {
        final ReadableStreamDefaultReadResult result = await reader!.read();
        streamController.add(result.value);
      }
    } catch (e) {
      print("Reading port failed with exception: \n$e");
      if (audioCallback != null) {
        print("Audio Callback not null0");
        // final reader = _port!.readable.reader;
        writer?.releaseLock();
        // await writer?.close();
        print("Audio Callback not null1");
        reader?.releaseLock();
        print("Audio Callback not null2");
        await _port?.close();
        print("Audio Callback not null3");
        writer = null;
        reader = null;
        audioCallback!(1, null);
      }else {
        // print("Audio Callback null");
        // print(audioCallback);
      }

      return null;
    }
  }

  /// Connection is directly established with the selected port
  @override
  Future<void> getAvailablePorts(int baudRate, Function callback) async {
    audioCallback = callback;
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

  Future<void> continuouslyReadData({
    required final ReadableStreamReader reader,
  }) async {
    while (true) {
      //   final result = await reader.read();
      //   if (result.done) {
      //     // Stream has ended
      //     print("Stream has ended");
      //     break;
      //   }

      //   // Check for errors
      //   if (result.value is Error) {
      //     // Handle the error
      //     print("Error reading from the stream: ${result.value}");
      //     break; // or return, depending on your use case
      //   }

      //   // Check for undefined value (buffer overrun)
      //   if (result.value == null) {
      //     print("Buffer overrun: Value is undefined. Pausing for a moment.");
      //     await Future.delayed(
      //         const Duration(milliseconds: 100)); // Add a short delay
      //     continue; // Retry reading the data
      //   }

      //   // Process the chunk
      //   print("the event is ${result.value}");
      //   if (streamController.hasListener) {
      //     streamController.add(result.value);
      //   } else {
      //     print(
      //         "StreamController has no listener. Discarding value: ${result.value}");
      //   }
      // }

      final result = await reader.read();
      streamController.add(result.value);
    }
  }
}
