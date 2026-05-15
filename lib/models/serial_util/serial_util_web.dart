import 'dart:async';
import 'dart:html';
import 'package:flutter/services.dart';
import 'package:serial/serial.dart';
import 'package:spikerbox_architecture/models/debugging.dart';

// import '../escape_sequences/escape_sequence.dart';
import 'serial_util_check.dart';

SerialUtil getSerialUtil() => SerialUtilWeb();

class SerialUtilWeb implements SerialUtil {
  @override
  bool isOpeningFile = false;
  static SerialPort? serialPort;

  SerialPortInfo? portInfo;
  Function? audioCallback;

  @override
  int vendorId = 0;
  @override
  int productId = 0;

  StreamController<Uint8List> streamController =
      StreamController<Uint8List>.broadcast();
  @override
  Stream<Uint8List>? dataStream;

  WritableStreamDefaultWriter? writer;
  /// Second [_disposeReader] waits for the first so releaseLock always finishes
  /// before a concurrent path calls [SerialPort.close] (avoids "locked stream").
  Future<void>? _disposeReaderInFlight;
  /// Prevents overlapping close/open/read cycles from duplicate baud timers.
  bool _serialReopenInProgress = false;
  /// Bumped when the port is closed/reopened so in-flight writes abandon stale writers.
  int _writableSession = 0;

  int _baudRate = 0;

  /// [ReadableStreamDefaultReader.cancel] / the read pump can stall on some USB
  /// states; [closePort] must not block [connectToPort] indefinitely.
  static const Duration _readCancelTimeout = Duration(seconds: 2);
  static const Duration _readPumpJoinTimeout = Duration(seconds: 4);
  static const Duration _writerReadyTimeout = Duration(seconds: 2);

  @override
  Future<void> connectToPort() async {
    print("connectToPort 1000: $serialPort");

    try {
      // UI often calls [closePort] without await. The next [connectToPort] can run
      // while the previous [closePort] is still running; [requestPort] then overwrites
      // [serialPort] before [SerialPort.close] finishes, so the browser still has an
      // open handle and [open] throws InvalidStateError: The port is already open.
      if (serialPort != null) {
        await closePort();
      }
      serialPort = await window.navigator.serial.requestPort();
      portInfo = serialPort?.getInfo();
      print("portInfo: ${portInfo?.usbVendorId} ${portInfo?.usbProductId}");
      vendorId = portInfo?.usbVendorId ?? 0;
      productId = portInfo?.usbProductId ?? 0;

      try{
        if (portInfo?.usbVendorId == 0x2E73 && portInfo?.usbProductId == 0x009) {
          // _baudRate = 500000;
          _baudRate = 222222;
        } else 
        if (portInfo?.usbVendorId == 0x0403 && portInfo?.usbProductId == 0x6015) {
          print("baudRate vendorId: ${portInfo?.usbVendorId} ---- productId: ${portInfo?.usbProductId}");
                _baudRate = 500000;
          // _baudRate = 222222;
        } else {
          _baudRate = 222222;
        }
      }catch(err) {
        print("ERR");
      }
      print("baudRate serial web: $_baudRate");
      await serialPort?.open(
        baudRate: _baudRate,
        // bufferSize: 8192,
      );
      await openPortToListen(" ", _baudRate);
    } catch (e) {
      print(
          "Port cancelled: ${e.toString().contains("NotFoundError: Failed to execute 'requestPort'")}");
      if (e
          .toString()
          .contains("NotFoundError: Failed to execute 'requestPort'")) {
        return;
      }
      print("Port opening failed: $e");
      try {
        await closePort();
      } catch (_) {}
      throw Exception("Serial connections require Chrome, or Edge");
    }
  }

  @override
  Future<void> closePort() async {
    print("closePort 1000 start: $serialPort");
    // Drop in-flight writes that might still touch the writer while we tear down.
    _writableSession++;
    await _disposeReader();
    await _disposeWriterForClose();
    try {
      if (!streamController.isClosed) {
        unawaited(streamController.close().catchError((_) {}));
      }
    } catch (err) {
      print("Error closing stream controller: $err");
    }
    print("closePort 1000 MIDDLE: $serialPort");

    try {
      await _closeSerialPortWithSettle();
    } catch (e) {
      print("Error closing web serial port: $e");
    } finally {
      writer = null;
      reader = null;
      portInfo = null;
      serialPort = null;
    }
    print("closePort 1000 END: $serialPort");

  }

  @override
  void writeToPort({required Uint8List bytesMessage, String? address}) async {
    // `void` + `async`: callers never await this Future, so any uncaught error
    // becomes an unhandled async error (uncaught in JS on web). Keep failures contained.
    try {
      await _writeToPortUnchecked(bytesMessage);
    } catch (e, _) {
      print("SerialUtilWeb.writeToPort failed: $e");
      await _resetWriterAfterError();
      audioCallback!(1, null);
    }
  }

  Future<void> _writeToPortUnchecked(Uint8List bytesMessage) async {
    print("writeToPortUnchecked: $serialPort $_serialReopenInProgress");
    if (serialPort == null || _serialReopenInProgress) {
      return;
    }
    final session = _writableSession;
    if (!_writeSessionStillValid(session)) {
      return;
    }

    writer ??= serialPort!.writable.writer;
    var w = writer;
    if (w == null || !_writeSessionStillValid(session)) {
      return;
    }

    await w.ready;
    if (!_writeSessionStillValid(session) || writer != w) {
      return;
    }

    await w.write(bytesMessage);
    if (!_writeSessionStillValid(session) || writer != w) {
      return;
    }

    await w.ready;
    if (!_writeSessionStillValid(session) || writer != w) {
      return;
    }

    Debugging.printing("message sent : ${String.fromCharCodes(bytesMessage)}");
  }

  bool _writeSessionStillValid(int session) =>
      session == _writableSession && serialPort != null && !_serialReopenInProgress;

  Future<void> _resetWriterAfterError() async {
    final w = writer;
    writer = null;
    if (w == null) {
      return;
    }
    try {
      await w.ready.timeout(_writerReadyTimeout, onTimeout: () {});
    } catch (_) {}
    try {
      await w.close();
    } catch (_) {}
    try {
      w.releaseLock();
    } catch (_) {}
  }

  @override
  List<String> availablePorts = [];

  @override
  Future<List<String>> startPortCheck(int baudRate) async {
    List<String> availablePorts = [];

    return availablePorts;
  }

  ReadableStreamReader? reader;
  /// Completed when [_pumpSerialReadLoop] for the current reader finishes (after cancel).
  Future<void>? _readPumpFuture;
  @override
  Future<Stream<Uint8List>?> openPortToListen(
      String? name, int baudRate) async {
    _baudRate = baudRate;
    if (serialPort == null) {
      return null;
    }
    try {
      print("READER1 $serialPort");
      // Release previous reader before acquiring readable (Web Serial lock rules).
      await _disposeReader();
      final readable = serialPort!.readable;
      try {
        reader = readable.reader;
      } catch (e) {
        // Readable may still be locked briefly after cancel(); wait and retry once.
        print("readable.reader first attempt failed: $e");
        await Future<void>.delayed(const Duration(milliseconds: 60));
        reader = readable.reader;
      }
      print("READER2");
      // Avoid `await streamController.close()` here: it can hang when anything still
      // listens on this sink (e.g. graph_template's serialDataSubscription).
      if (dataStream == null) {
        dataStream = streamController.stream;
      } else if (streamController.isClosed) {
        streamController = StreamController<Uint8List>.broadcast();
        dataStream = streamController.stream;
      } else {
        try {
          streamController.close();
          streamController = StreamController<Uint8List>.broadcast();
          dataStream = streamController.stream;
        } catch(err) {
          print("OPEN PORT");
        }
      }
      print("READER3");
      print("READER4");

      final localReader = reader!;
      // Return dataStream before blocking on reads so callers (e.g. graph_template)
      // can subscribe in the same turn without racing a null dataStream.
      _readPumpFuture = _pumpSerialReadLoop(localReader);
      unawaited(_readPumpFuture!);
      return dataStream;
    } catch (e) {
      print("Reading port failed with exception: \n$e");
      if (audioCallback != null && !isOpeningFile) {
        print("Audio Callback not null0");
        await _teardownSerialPortAfterReadFailure();
        try {
          audioCallback!(1, null);
        } catch (cbErr) {
          print("audioCallback error: $cbErr");
        }
      }

      return null;
    }
  }

  Future<void> _pumpSerialReadLoop(ReadableStreamReader localReader) async {
    try {
      while (reader == localReader) {
        final ReadableStreamDefaultReadResult result = await localReader.read();
        if (result.done) {
          print("RESULT DONEZ");
          break;
        }
        streamController.add(result.value);
      }
    } catch (e) {
      print("Reading port failed with exception: \n$e");
      if (audioCallback != null && !isOpeningFile) {
        print("Audio Callback not null0");
        // Must not await teardown here: [_disposeReaderBody] waits on this pump
        // future; awaiting [_teardownSerialPortAfterReadFailure] would deadlock
        // because teardown calls [_disposeReader] again.
        unawaited(_teardownSerialPortAfterReadFailure().then((_) {
          try {
            audioCallback!(1, null);
          } catch (cbErr) {
            print("audioCallback error: $cbErr");
          }
        }));
      }
    }
  }

  /// Same stream-unlock + close sequence as [closePort], for read/open failures.
  Future<void> _teardownSerialPortAfterReadFailure() async {
    if (serialPort == null) {
      return;
    }
    _writableSession++;
    await _fullyReleasePortStreams();
    try {
      await _closeSerialPortWithSettle();
    } catch (_) {}
    writer = null;
    reader = null;
    portInfo = null;
    serialPort = null;
  }

  /// Connection is directly established with the selected port
  @override
  Future<void> getAvailablePorts(int baudRate, Function callback) async {
    audioCallback = callback;
    _baudRate = baudRate;
    try {
      await connectToPort();
    } catch (err) {
      throw Exception("Serial connections require Chrome, or Edge");
    }

    if (serialPort == null) {
      availablePorts = [];
      return;
    }
    availablePorts = [serialPort!.getInfo().usbProductId!.toString()];
    print("getttavailablePorts: $availablePorts");
  }

  @override
  Future<List<String>> getAvailablePortsWeb(
      int baudRate, Function callback) async {
    audioCallback = callback;
    _baudRate = baudRate;
    try {
      print("connectToPort: $baudRate");
      try {
        await connectToPort();
      } catch (err) {
        throw Exception("Serial connections require Chrome, or Edge");
      }
      if (serialPort == null) {
        return [];
      }
      availablePorts = [serialPort!.getInfo().usbProductId!.toString()];
      print("availablePorts: $availablePorts");
      return availablePorts;
    } catch (err) {
      print(
          "error in getAvailablePortsWeb: ${err.toString()} --- ${err.toString().contains("Null check operator used on a null value")}");
      if (err.toString().contains("Null check operator used on a null value")) {
        throw Exception("BYPASS");
      } else {
        throw Exception("Serial connections require Chrome, or Edge");
      }
    }

    // print("getttavailablePorts: $availablePorts");
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

  @override
  Stream<String?> deviceStatusStreamListener() {
    return Stream.empty();
  }
  
  @override
  Future<void> changePortBaudRate(int baudRate) async {
    if (serialPort == null) {
      return;
    }
    if (_baudRate == baudRate) {
      return;
    }
    if (_serialReopenInProgress) {
      return;
    }
    _serialReopenInProgress = true;
    _baudRate = baudRate;
    try {
      await _reopenPortAndListen();
    } catch (e, _) {
      print("changePortBaudRate async error: $e");
    } finally {
      _serialReopenInProgress = false;
    }
  }

  Future<void> _reopenPortAndListen() async {
    if (serialPort == null) {
      return;
    }
    // Invalidate any writer acquired while the previous session was still "open"
    // and drop in-flight writes that still hold the old WritableStreamDefaultWriter.
    _writableSession++;
    try {
      await _fullyReleasePortStreams();
      await _closeSerialPortWithSettle();
      await _openSerialPortWithRetry();
      await openPortToListen(" ", _baudRate);
    } catch (e, _) {
      print("_reopenPortAndListen failed: $e");
    } finally {
      // Always attach the next write to the current port's writable, never a pre-close writer.
      writer = null;
    }
  }

  Future<void> _fullyReleasePortStreams() async {
    // Web Serial requires readable + writable unlocked before port.close().
    // Release the reader side first (stops the read loop), then the writer.
    await _disposeReader();
    await _disposeWriterForClose();
  }

  Future<void> _disposeWriterForClose() async {
    final w = writer;
    writer = null;
    if (w == null) {
      return;
    }
    try {
      await w.ready.timeout(_writerReadyTimeout, onTimeout: () {});
    } catch (_) {}
    try {
      await w.close();
    } catch (_) {}
    try {
      w.releaseLock();
    } catch (_) {}
  }

  /// Close the port and give Chromium time to finish internal teardown.
  Future<void> _closeSerialPortWithSettle() async {
    final port = serialPort;
    if (port == null) {
      return;
    }
    Object? lastCloseError;
    for (var attempt = 0; attempt < 6; attempt++) {
      try {
        await port.close();
        lastCloseError = null;
        break;
      } catch (e) {
        lastCloseError = e;
        print("serialPort.close attempt ${attempt + 1} failed: $e");
        _writableSession++;
        await Future<void>.delayed(Duration(milliseconds: 100 * (attempt + 1)));
        await _fullyReleasePortStreams();
      }
    }
    if (lastCloseError != null) {
      print("serialPort.close: giving up after retries, last error: $lastCloseError");
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  bool _isPortAlreadyOpenError(Object e) {
    final s = e.toString();
    return s.contains('already open') || s.contains('InvalidStateError');
  }

  Future<void> _openSerialPortWithRetry() async {
    final port = serialPort;
    if (port == null) {
      return;
    }
    try {
      await port.open(baudRate: _baudRate);
    } catch (e) {
      if (!_isPortAlreadyOpenError(e)) {
        rethrow;
      }
      // Port still reported open: close again, settle, then open once more.
      try {
        await _fullyReleasePortStreams();
        await port.close();
      } catch (_) {}
      await Future<void>.delayed(const Duration(milliseconds: 150));
      await port.open(baudRate: _baudRate);
    }
  }

  Future<void> _disposeReader() async {
    if (_disposeReaderInFlight != null) {
      await _disposeReaderInFlight;
      return;
    }
    _disposeReaderInFlight = _disposeReaderBody();
    try {
      await _disposeReaderInFlight;
    } finally {
      _disposeReaderInFlight = null;
    }
  }

  Future<void> _disposeReaderBody() async {
    final localReader = reader;
    if (localReader == null) {
      try {
        await (_readPumpFuture ?? Future<void>.value())
            .timeout(_readPumpJoinTimeout, onTimeout: () {});
      } catch (_) {}
      _readPumpFuture = null;
      return;
    }
    reader = null;
    try {
      try {
        final cancelResult = (localReader as dynamic).cancel();
        if (cancelResult is Future) {
          await cancelResult.timeout(_readCancelTimeout, onTimeout: () {});
        }
      } catch (_) {
        // cancel may fail if reader is already invalid.
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      // Wait until read pump exits so read() is not still pending during releaseLock.
      try {
        await (_readPumpFuture ?? Future<void>.value())
            .timeout(_readPumpJoinTimeout, onTimeout: () {});
      } catch (_) {}
      _readPumpFuture = null;
      // Required for SerialPort.close(): readable must be unlocked (cancel alone is not enough).
      for (var attempt = 0; attempt < 8; attempt++) {
        try {
          localReader.releaseLock();
          break;
        } catch (_) {
          await Future<void>.delayed(Duration(milliseconds: 35 * (attempt + 1)));
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
    } catch (_) {}
  }
}
