import 'dart:async';
import 'dart:html';
import 'package:flutter/services.dart';
import 'package:serial/serial.dart';
import 'package:spikerbox_architecture/models/debugging.dart';
import 'package:spikerbox_architecture/models/usb_protocol/commands.dart';

import 'serial_device_frame_parser.dart';
import 'serial_line_errors.dart';
import 'serial_util_check.dart';

SerialUtil getSerialUtil() => SerialUtilWeb();

class SerialUtilWeb implements SerialUtil {
  bool _useHardwareFlowControl = false;

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

  /// Tracks Web Serial open state — [requestPort] returns a closed port.
  bool _portOpen = false;

  /// Serializes [closePort], [connectToPort], and baud changes (no overlapping I/O).
  Future<void> _serialLifecycle = Future<void>.value();

  static const int _serialBufferSize = 1048576;
  static const List<int> _probeBaudRates = [500000, 230400, 222222];
  static final Uint8List _probeQueryBytes =
      UsbCommand.hwTypeInquiry.cmdAsBytes();
  static const Duration _probeSettleTime = Duration(milliseconds: 150);
  static const Duration _probeReopenDelay = Duration(milliseconds: 300);
  static const Duration _probeFrameTimeout = Duration(seconds: 3);
  static const int _probeAttemptsPerBaud = 2;

  final SerialDeviceFrameParser _frameParser = SerialDeviceFrameParser();
  bool _probing = false;
  bool _probeReading = false;
  bool _probeSawCompleteFrame = false;
  bool _probeAcceptRx = false;
  bool _intentionalProbeStop = false;
  int _probeRxBytes = 0;
  Completer<bool>? _probeResponseCompleter;
  Timer? _queryRepeatTimer;
  ReadableStreamReader? _probeActiveReader;

  /// [ReadableStreamDefaultReader.cancel] / the read pump can stall on some USB
  /// states; [closePort] must not block [connectToPort] indefinitely.
  static const Duration _readCancelTimeout = Duration(seconds: 2);
  static const Duration _readPumpJoinTimeout = Duration(seconds: 4);
  static const Duration _writerReadyTimeout = Duration(seconds: 2);

  @override
  void setBaudRate(int baudRate) {
    _baudRate = baudRate;
  }

  /// Tries [_probeBaudRates] in order; first baud with a valid escape frame wins.
  Future<int?> _autoDetectBaudRate() async {
    if (serialPort == null) {
      return null;
    }
    _probing = true;
    try {
      for (final baud in _probeBaudRates) {
        print('SerialUtilWeb: probing baud $baud');
        final ok = await _tryProbeBaud(baud);
        if (ok) {
          return baud;
        }
        await Future<void>.delayed(_probeReopenDelay);
      }
      return null;
    } finally {
      _cancelQueryRepeatTimer();
      _probing = false;
    }
  }

  void _cancelQueryRepeatTimer() {
    _queryRepeatTimer?.cancel();
    _queryRepeatTimer = null;
  }

  void _startQueryRepeatTimer() {
    _cancelQueryRepeatTimer();
    if (!_probing) {
      return;
    }
    _queryRepeatTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final c = _probeResponseCompleter;
      if (!_probing || c == null || c.isCompleted) {
        timer.cancel();
        _queryRepeatTimer = null;
        return;
      }
      unawaited(_sendProbeQueryOnce());
    });
  }

  Future<bool> _sendQueryAndAwaitFrameProbe() async {
    _probeSawCompleteFrame = false;
    _frameParser.reset();
    _probeResponseCompleter = Completer<bool>();

    await _sendProbeQueryOnce();
    if (_probing) {
      _frameParser.reset();
      _probeAcceptRx = true;
      _startQueryRepeatTimer();
    }

    try {
      return await _probeResponseCompleter!.future.timeout(
        _probeFrameTimeout,
        onTimeout: () {
          print(
            'SerialUtilWeb: probe timeout (${_probeFrameTimeout.inSeconds}s) — '
            'rawRx=$_probeRxBytes B, buf=${_frameParser.bufferedBytes} B, '
            'start=${_frameParser.hasStartMarker}, end=${_frameParser.hasEndMarker}',
          );
          return _probeSawCompleteFrame;
        },
      );
    } finally {
      _cancelQueryRepeatTimer();
      _probeAcceptRx = false;
      _probeResponseCompleter = null;
    }
  }

  Future<bool> _tryProbeBaud(int baud) async {
    final port = serialPort;
    if (port == null) {
      return false;
    }

    if (_portOpen) {
      await _stopProbeReading();
      await _closeSerialPortWithSettle();
      await Future<void>.delayed(_probeReopenDelay);
    }

    _writableSession++;
    _baudRate = baud;
    _probeSawCompleteFrame = false;
    _probeAcceptRx = false;
    _probeRxBytes = 0;
    _frameParser.reset();

    try {
      await _openSerialPortWithRetry();
    } catch (e) {
      print('SerialUtilWeb: probe open @$baud failed: $e');
      return false;
    }

    _probing = true;
    _probeReading = true;
    _probeActiveReader = port.readable.reader;
    final probePump = _probeReadLoop(port, _probeActiveReader!);

    try {
      await Future<void>.delayed(_probeSettleTime);
      var success = false;
      for (var attempt = 1; attempt <= _probeAttemptsPerBaud; attempt++) {
        if (attempt > 1) {
          print(
            'SerialUtilWeb: probe @$baud no response in '
            '${_probeFrameTimeout.inSeconds}s — retry $attempt/$_probeAttemptsPerBaud',
          );
        }
        success = await _sendQueryAndAwaitFrameProbe();
        if (success) {
          break;
        }
      }
      await _stopProbeReadLoop(_probeActiveReader!, probePump);

      if (success) {
        _probing = false;
        await _fullyReleasePortStreams();
      } else {
        await _fullyReleasePortStreams();
        await _closeSerialPortWithSettle();
      }
      return success;
    } catch (e, st) {
      print('SerialUtilWeb: probe @$baud error: $e\n$st');
      await _stopProbeReading();
      await _closeSerialPortWithSettle();
      return false;
    } finally {
      _probeActiveReader = null;
      _probeResponseCompleter = null;
    }
  }

  Future<void> _stopProbeReading() async {
    if (!_probeReading) {
      return;
    }
    _intentionalProbeStop = true;
    try {
      final cancelResult = (_probeActiveReader as dynamic)?.cancel();
      if (cancelResult is Future) {
        await cancelResult.timeout(_readCancelTimeout, onTimeout: () {});
      }
    } catch (_) {}
    _probeReading = false;
    await Future<void>.delayed(const Duration(milliseconds: 80));
    _intentionalProbeStop = false;
  }

  Future<void> _sendProbeQueryOnce() async {
    final port = serialPort;
    if (port == null || _serialReopenInProgress) {
      return;
    }
    WritableStreamDefaultWriter? w;
    try {
      w = port.writable.writer;
      await w.ready.timeout(_writerReadyTimeout, onTimeout: () {});
      await w.write(_probeQueryBytes);
      await w.ready.timeout(_writerReadyTimeout, onTimeout: () {});
      await w.close();
    } catch (e) {
      print('SerialUtilWeb: probe query send failed: $e');
    } finally {
      try {
        w?.releaseLock();
      } catch (_) {}
    }
  }

  void _completeProbeResponse(bool success) {
    final c = _probeResponseCompleter;
    if (c == null || c.isCompleted) {
      return;
    }
    c.complete(success);
  }

  void _onProbeCompleteFrame() {
    _probeSawCompleteFrame = true;
    _cancelQueryRepeatTimer();
    _completeProbeResponse(true);
  }

  void _onProbeRxChunk(Uint8List chunk) {
    _probeRxBytes += chunk.length;
    if (_probing && !_probeAcceptRx) {
      return;
    }
    if (_frameParser.feed(chunk)) {
      final frame = _frameParser.lastCompleteFrame;
      final payload = _frameParser.lastPayload;
      if (frame != null && payload != null) {
        print(
          'SerialUtilWeb: probe frame OK (${frame.length} B, '
          '${payload.length} B payload) @ $_baudRate',
        );
        _onProbeCompleteFrame();
      }
    }
  }

  bool _isRecoverableProbeReadError(Object e) {
    return isSerialRecoverableLineError(e) || isSerialBreakError(e);
  }

  Future<ReadableStreamReader> _freshProbeReader(
    SerialPort port,
    ReadableStreamReader old,
  ) async {
    await _releaseReaderLock(old);
    if (!_probing) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    final reader = port.readable.reader;
    _probeActiveReader = reader;
    return reader;
  }

  Future<void> _probeReadLoop(
    SerialPort port,
    ReadableStreamReader probeReader,
  ) async {
    var activeReader = probeReader;
    try {
      while (_probeReading) {
        try {
          final result = await activeReader.read();
          if (result.done) {
            if (!_probeReading || _intentionalProbeStop) {
              break;
            }
            activeReader = await _freshProbeReader(port, activeReader);
            continue;
          }
          final value = result.value;
          if (value.isEmpty) {
            continue;
          }
          _onProbeRxChunk(Uint8List.fromList(value));
        } catch (e) {
          if (_intentionalProbeStop) {
            break;
          }
          if (_probing && _isRecoverableProbeReadError(e)) {
            print('SerialUtilWeb: probe $e — keep reading');
            if (!_probeReading || serialPort == null) {
              break;
            }
            activeReader = await _freshProbeReader(port, activeReader);
            continue;
          }
          rethrow;
        }
      }
    } catch (e) {
      if (_probing) {
        print('SerialUtilWeb: probe read ended: $e');
        _completeProbeResponse(_probeSawCompleteFrame);
      }
    } finally {
      await _releaseReaderLock(activeReader);
      _probeActiveReader = null;
    }
  }

  Future<void> _stopProbeReadLoop(
    ReadableStreamReader probeReader,
    Future<void> probePump,
  ) async {
    _probeReading = false;
    try {
      final cancelResult = (probeReader as dynamic).cancel();
      if (cancelResult is Future) {
        await cancelResult.timeout(_readCancelTimeout, onTimeout: () {});
      }
    } catch (_) {}
    try {
      await probePump.timeout(_readPumpJoinTimeout, onTimeout: () {});
    } catch (_) {}
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }

  /// New broadcast stream for each connect/listen session. Abandons the previous
  /// controller so an in-flight [close] from [closePort] cannot race the read pump.
  void _replaceDataStream() {
    final previous = streamController;
    streamController = StreamController<Uint8List>.broadcast();
    dataStream = streamController.stream;
    if (!previous.isClosed) {
      unawaited(previous.close().catchError((_) {}));
    }
  }

  Future<void> _releaseReaderLock(ReadableStreamReader reader) async {
    for (var attempt = 0; attempt < 8; attempt++) {
      try {
        reader.releaseLock();
        return;
      } catch (_) {
        await Future<void>.delayed(Duration(milliseconds: 35 * (attempt + 1)));
      }
    }
  }

  Future<T> _runSerialLifecycle<T>(Future<T> Function() action) async {
    final previous = _serialLifecycle;
    final gate = Completer<void>();
    _serialLifecycle = gate.future;
    await previous;
    try {
      return await action();
    } finally {
      gate.complete();
    }
  }

  @override
  Future<void> connectToPort() async {
    return _runSerialLifecycle(_connectToPortBody);
  }

  Future<void> _connectToPortBody() async {
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
      // Brief settle after picker — some drivers reject immediate open().
      await Future<void>.delayed(const Duration(milliseconds: 50));
      portInfo = serialPort?.getInfo();
      print("portInfo: ${portInfo?.usbVendorId} ${portInfo?.usbProductId}");
      vendorId = portInfo?.usbVendorId ?? 0;
      productId = portInfo?.usbProductId ?? 0;

      final detectedBaud = await _autoDetectBaudRate();
      if (detectedBaud == null) {
        await closePort();
        throw Exception(
            'No device response at supported baud rates (500000, 230400, 222222)');
      }
      _baudRate = detectedBaud;
      print("baudRate serial web (auto-detected): $_baudRate");
      await openPortToListen(" ", _baudRate);
    } catch (e) {
      print(
          "Port cancelled: $e --- ${e.toString().contains("NotFoundError: Failed to execute 'requestPort'")}");
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
    return _runSerialLifecycle(_closePortBody);
  }

  Future<void> _closePortBody() async {
    _cancelQueryRepeatTimer();
    _probing = false;
    _completeProbeResponse(false);
    final portToClose = serialPort;
    print("closePort 1000 start: $portToClose");
    // Drop in-flight writes that might still touch the writer while we tear down.
    _writableSession++;
    await _disposeReader();
    await _disposeWriterForClose();
    _replaceDataStream();
    print("closePort 1000 MIDDLE: $portToClose");

    try {
      if (identical(serialPort, portToClose)) {
        await _closeSerialPortWithSettle();
      }
    } catch (e) {
      print("Error closing web serial port: $e");
    } finally {
      writer = null;
      reader = null;
      if (identical(serialPort, portToClose)) {
        portInfo = null;
        serialPort = null;
      }
      _portOpen = false;
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
      session == _writableSession &&
      serialPort != null &&
      !_serialReopenInProgress;

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
    if (!_portOpen) {
      await _openSerialPortWithRetry();
    } else {
      // Baud probe left the port open — unlock streams, do not close/reopen.
      await _fullyReleasePortStreams();
    }

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
      _replaceDataStream();
      print("READER3");
      print("READER4");

      final localReader = reader!;
      final outbound = streamController;
      // Return dataStream before blocking on reads so callers (e.g. graph_template)
      // can subscribe in the same turn without racing a null dataStream.
      _readPumpFuture = _pumpSerialReadLoop(localReader, outbound);
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

  Future<void> _pumpSerialReadLoop(
    ReadableStreamReader localReader,
    StreamController<Uint8List> outbound,
  ) async {
    var activeReader = localReader;
    try {
      while (reader == activeReader && !outbound.isClosed) {
        try {
          final ReadableStreamDefaultReadResult result =
              await activeReader.read();
          if (result.done) {
            print("RESULT DONEZ");
            break;
          }
          if (!outbound.isClosed) {
            outbound.add(result.value);
          }
        } catch (e) {
          if (isSerialRecoverableLineError(e) &&
              reader == activeReader &&
              serialPort != null) {
            print(
                'SerialUtilWeb: ${serialLineErrorLabel(e)} — re-acquiring reader');
            await _reacquireReaderAfterLineError(activeReader);
            if (reader == null) {
              break;
            }
            activeReader = reader!;
            continue;
          }
          rethrow;
        }
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
    // serialPort = null;
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
    return _runSerialLifecycle(() async {
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
    });
  }

  Future<void> _reopenPortAndListen() async {
    print("_reopenPortAndListen start");

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
    if (port == null || !_portOpen) {
      _portOpen = false;
      return;
    }
    Object? lastCloseError;
    for (var attempt = 0; attempt < 6; attempt++) {
      try {
        await port.close();
        _portOpen = false;
        lastCloseError = null;
        break;
      } catch (e) {
        if (isSerialPortAlreadyClosedError(e)) {
          _portOpen = false;
          return;
        }
        lastCloseError = e;
        print("serialPort.close attempt ${attempt + 1} failed: $e");
        _writableSession++;
        await Future<void>.delayed(Duration(milliseconds: 100 * (attempt + 1)));
        await _fullyReleasePortStreams();
      }
    }
    if (lastCloseError != null) {
      print(
          "serialPort.close: giving up after retries, last error: $lastCloseError");
    }
    _portOpen = false;
    await Future<void>.delayed(const Duration(milliseconds: 200));
  }

  bool _isPortAlreadyOpenError(Object e) {
    final s = e.toString();
    return s.contains('already open') || s.contains('InvalidStateError');
  }

  Future<void> _openSerialPortWithRetry() async {
    final port = serialPort;
    if (port == null || _portOpen) {
      return;
    }

    Object? lastError;
    final attempts = <Future<void> Function()>[
      () => port.open(
            baudRate: _baudRate,
            dataBits: DataBits.eight,
            stopBits: StopBits.one,
            parity: Parity.none,
            bufferSize: _serialBufferSize,
            flowControl: _useHardwareFlowControl
                ? FlowControl.hardware
                : FlowControl.none,
          ),
      () => port.open(
            baudRate: _baudRate,
            dataBits: DataBits.eight,
            stopBits: StopBits.one,
            parity: Parity.none,
            bufferSize: 8192,
            flowControl: _useHardwareFlowControl
                ? FlowControl.hardware
                : FlowControl.none,
          ),
      () => port.open(baudRate: _baudRate),
    ];

    for (var i = 0; i < attempts.length; i++) {
      try {
        await attempts[i]();
        _portOpen = true;
        await _trySetPortSignals(port);
        if (i > 0) {
          print(
              'SerialUtilWeb: open @$_baudRate succeeded on attempt ${i + 1}');
        }
        return;
      } catch (e) {
        if (_isPortAlreadyOpenError(e)) {
          _portOpen = true;
          await _trySetPortSignals(port);
          return;
        }
        lastError = e;
        print('SerialUtilWeb: open @$_baudRate attempt ${i + 1} failed: $e');
      }
    }

    throw lastError ?? StateError('Failed to open serial port @ $_baudRate');
  }

  Future<void> _trySetPortSignals(SerialPort port) async {
    try {
      final result = (port as dynamic).setSignals(
        dataTerminalReady: true,
        requestToSend: false,
      );
      if (result is Future) {
        await result;
      }
    } catch (_) {}
  }

  Future<void> _reacquireReaderAfterLineError(
      ReadableStreamReader staleReader) async {
    if (identical(reader, staleReader)) {
      reader = null;
    }
    try {
      final cancelResult = (staleReader as dynamic).cancel();
      if (cancelResult is Future) {
        await cancelResult.timeout(_readCancelTimeout, onTimeout: () {});
      }
    } catch (_) {}
    await _releaseReaderLock(staleReader);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    final port = serialPort;
    if (port == null || _serialReopenInProgress) {
      return;
    }
    try {
      reader = port.readable.reader;
    } catch (e) {
      print('SerialUtilWeb: re-acquire reader failed: $e');
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
          await Future<void>.delayed(
              Duration(milliseconds: 35 * (attempt + 1)));
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 120));
    } catch (_) {}
  }
}
