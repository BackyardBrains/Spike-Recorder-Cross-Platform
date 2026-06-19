import 'dart:async';
import 'dart:convert';
import 'dart:html';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'package:serial/serial.dart';
import 'package:spikerbox_architecture/message_identifier.dart';
import 'package:spikerbox_architecture/models/debugging.dart';
import 'package:spikerbox_architecture/models/frame_detect.dart';
import 'package:spikerbox_architecture/models/usb_protocol/commands.dart';

import 'serial_device_frame_parser.dart';
import 'serial_line_errors.dart';
import 'serial_util_check.dart';

SerialUtil getSerialUtil() => SerialUtilWeb();

class SerialUtilWeb implements SerialUtil {
  // Many USB-serial bridges used by BYB devices do not implement RTS/CTS in a way
  // that Chromium's Web Serial API can reliably negotiate (especially on ChromeOS).
  // Using hardware flow control here has been observed to cause intermittent
  // "NetworkError: The device has been lost." after a successful open.
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
  static const int _probeBufferSize = 8192;
  static const int _probeFrameDetectMaxBytes = 65536;
  static const List<int> _probeBaudRates = [500000, 230400, 222222];
  static final Uint8List _probeQueryBytes = Uint8List.fromList([
    ...UsbCommand.hwTypeInquiry.cmdAsBytes(),
    // ...utf8.encode('board:;\n'),
    // ...utf8.encode('h:;\n'),
  ]);

  /// Same tokens [GraphTemplate.listOfDevices] accepts from hwTypeInquiry.
  static const List<String> _probeDeviceReplyTokens = [
    'PLANTSS;',
    'MUSCUSB1;',
    'HBLEOSB;',
    'MSBPCDC;',
    'NRNSBPRO;',
    'HUMANSB;',
    'NSBPCDC;',
    'HHIBOX;',
    'UNIBOX;',
    'NEURONSS;',
    'HEARTSS;',
  ];

  static final List<Uint8List> _probeDeviceReplyTokenBytes =
      _probeDeviceReplyTokens
          .map((t) => Uint8List.fromList(t.codeUnits))
          .toList(growable: false);

  /// Replies are often `HWT:HHIBOX;` (graph_template logs).
  static final List<Uint8List> _probeHwtDeviceReplyTokenBytes =
      _probeDeviceReplyTokens
          .map((t) => Uint8List.fromList('HWT:$t'.codeUnits))
          .toList(growable: false);

  static final List<Uint8List> _probeAllReplyTokenBytes = [
    ..._probeDeviceReplyTokenBytes,
    ..._probeHwtDeviceReplyTokenBytes,
  ];

  static final int _probeMaxDeviceTokenBytes = _probeAllReplyTokenBytes.fold(
    0,
    (max, t) => t.length > max ? t.length : max,
  );

  static const int _probeAdcStreamMinRxBytes = 8192;
  static const int _probeAsciiWindowMax = 16384;
  static const int _probeAdcSyncHitsRequired = 2;

  static const Duration _probeSettleTime = Duration(milliseconds: 400);
  static const Duration _probeReopenDelay = Duration(milliseconds: 300);
  static const Duration _probeFrameTimeoutDefault =
      Duration(milliseconds: 3000);
  static const Duration _probeFrameTimeout500k = Duration(milliseconds: 3000);
  /// Shorter hwType wait when the device is likely off (no RX on first baud).
  static const Duration _probeFrameTimeoutDeadDevice =
      Duration(milliseconds: 700);
  static const int _probeAttemptsPerBaud = 2;

  Duration _probeFrameTimeoutForBaud(int baud) =>
      baud == 500000 ? _probeFrameTimeout500k : _probeFrameTimeoutDefault;
  static const int _probeBaudScanRounds = 3;

  /// After this many UART line errors inside [_lineErrorRecoveryWindow], re-probe baud.
  static const int _lineErrorsBeforeBaudRecovery = 8;
  static const Duration _lineErrorRecoveryWindow = Duration(seconds: 4);
  static const int _maxListenBaudRecoveryAttempts = 2;
  static const Duration _reacquireBackoffBase = Duration(milliseconds: 60);
  static const Duration _reacquireBackoffMax = Duration(milliseconds: 1000);

  int _consecutiveLineErrors = 0;
  DateTime? _lineErrorWindowStart;
  int _reacquireBackoffStep = 0;
  int _listenBaudRecoveryRounds = 0;
  bool _listenBaudRecoveryInProgress = false;

  final SerialDeviceFrameParser _frameParser = SerialDeviceFrameParser();
  final BytesBuilder _probeAsciiWindow = BytesBuilder(copy: false);
  late final MessageIdentifier _probeMessageId = MessageIdentifier(
    onDeviceData: (_) {},
    onDeviceMessage: (Uint8List msg) {
      if (!_probing || !_probeAcceptRx || _probeSawCompleteFrame) {
        return;
      }
      if (_probeReplyIdentifiesDevice(msg)) {
        print('SerialUtilWeb: probe escape message @ $_baudRate');
        _onProbeCompleteFrame();
      }
    },
  );
  bool _probing = false;
  bool _probeReading = false;
  bool _probeSawCompleteFrame = false;
  bool _probeAcceptRx = false;
  bool _intentionalProbeStop = false;

  /// Set while [_disposeReaderBody] cancels the reader — pending [read] ends with BreakError.
  bool _intentionalReaderStop = false;
  int _probeRxBytes = 0;
  Completer<bool>? _probeResponseCompleter;
  Timer? _queryRepeatTimer;
  ReadableStreamReader? _probeActiveReader;
  Future<void>? _probeWriteInFlight;
  FrameDetect? _probeFrameDetect;
  int _probeAdcFrameHits = 0;

  /// [ReadableStreamDefaultReader.cancel] / the read pump can stall on some USB
  /// states; [closePort] must not block [connectToPort] indefinitely.
  static const Duration _readCancelTimeout = Duration(seconds: 2);
  static const Duration _readPumpJoinTimeout = Duration(seconds: 4);
  static const Duration _writerReadyTimeout = Duration(seconds: 2);

  @override
  void setBaudRate(int baudRate) {
    _baudRate = baudRate;
  }

  /// Tries [_probeBaudRates] in order; framed reply, ASCII token, or ADC hint.
  /// Repeats the full baud list up to [_probeBaudScanRounds] times if all fail.
  Future<int?> _autoDetectBaudRate() async {
    if (serialPort == null) {
      return null;
    }
    _probing = true;
    int? bestAdcBaud;
    var bestAdcScore = 0.0;
    try {
      for (var round = 1; round <= _probeBaudScanRounds; round++) {
        if (round > 1) {
          print(
            'SerialUtilWeb: all baud rates failed — '
            'rescan round $round/$_probeBaudScanRounds',
          );
        }
        for (final baud in _probeBaudRates) {
          print('SerialUtilWeb: probing baud $baud (round $round)');
          final fastScan = round == 1 && identical(baud, _probeBaudRates.first);
          try {
            final ok = await _tryProbeBaud(
              baud,
              acceptAdcStream: false,
              fastScan: fastScan,
            );
            if (ok) {
              return baud;
            }
            if (fastScan && _probeRxBytes == 0) {
              print(
                'SerialUtilWeb: no RX on first baud — aborting scan (device off?) -- $fastScan && $_probeRxBytes',
              );
              return null;
            }
          } on SerialConnectAborted {
            rethrow;
          }
          final score =
              _probeRxBytes > 0 ? _probeAdcFrameHits / _probeRxBytes : 0.0;
          print(
            'SerialUtilWeb: @$baud scan rawRx=$_probeRxBytes '
            'adcSyncs=$_probeAdcFrameHits score=${score.toStringAsFixed(6)}',
          );
          if (_probeAdcFrameHits >= _probeAdcSyncHitsRequired &&
              score > bestAdcScore) {
            bestAdcScore = score;
            bestAdcBaud = baud;
          }
          await Future<void>.delayed(_probeReopenDelay);
        }
      }
      if (bestAdcBaud != null) {
        print(
          'SerialUtilWeb: strict re-probe @$bestAdcBaud '
          '(ADC hint score=$bestAdcScore)',
        );
        final ok = await _tryProbeBaud(bestAdcBaud, acceptAdcStream: true);
        return ok ? bestAdcBaud : null;
      }
      print('SerialUtilWeb: END');

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
      _probeAsciiWindow.clear();
      unawaited(_sendProbeQueryOnce());
    });
  }

  void _resetProbeRxState() {
    _frameParser.reset();
    _probeMessageId.reset();
    _probeAsciiWindow.clear();
    _probeRxBytes = 0;
    _probeFrameDetect = FrameDetect(channelCount: 1, minimumBytesToCheck: 50);
    _probeAdcFrameHits = 0;
  }

  void _resetProbeMessageAttemptState() {
    _frameParser.reset();
    _probeMessageId.reset();
    _probeAsciiWindow.clear();
  }

  void _noteProbeAdcStreamSync(Uint8List chunk) {
    if (_probeRxBytes > _probeFrameDetectMaxBytes) {
      _probeFrameDetect = FrameDetect(channelCount: 1, minimumBytesToCheck: 50);
    }
    final detect = _probeFrameDetect;
    if (detect == null) {
      return;
    }
    if (detect.addData(chunk) != null) {
      _probeAdcFrameHits++;
    }
  }

  bool _probeReplyIdentifiesDevice(Uint8List msg) =>
      _probeBytesContainDeviceToken(msg);

  bool _probeBytesContainDeviceToken(
    Uint8List haystack, {
    int start = 0,
  }) {
    if (haystack.isEmpty || start >= haystack.length) {
      return false;
    }
    for (final needle in _probeAllReplyTokenBytes) {
      if (_probeBytesContains(haystack, needle, start)) {
        return true;
      }
    }
    return false;
  }

  bool _probeBytesContains(Uint8List haystack, Uint8List needle, int start) {
    if (needle.isEmpty || haystack.length - start < needle.length) {
      return false;
    }
    final maxStart = haystack.length - needle.length;
    for (var i = start; i <= maxStart; i++) {
      var match = true;
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) {
          match = false;
          break;
        }
      }
      if (match) {
        return true;
      }
    }
    return false;
  }

  bool _probeAdcStreamLooksLikeDevice() =>
      _probeRxBytes >= _probeAdcStreamMinRxBytes &&
      _probeAdcFrameHits >= _probeAdcSyncHitsRequired;

  Duration _probeQueryTimeout(int attempt, {required bool fastScan}) {
    if (fastScan && attempt == 1) {
      return _probeFrameTimeoutDeadDevice;
    }
    return _probeFrameTimeoutForBaud(_baudRate);
  }

  Future<bool> _sendQueryAndAwaitFrameProbe({
    bool fastScan = false,
    int attempt = 1,
  }) async {
    if (_probeSawCompleteFrame) {
      return true;
    }
    _resetProbeMessageAttemptState();
    _probeResponseCompleter = Completer<bool>();

    if (_probing) {
      _probeAcceptRx = true;
    }
    await _sendProbeQueryOnce();
    if (_probing) {
      _startQueryRepeatTimer();
    }

    final frameTimeout = _probeQueryTimeout(attempt, fastScan: fastScan);
    try {
      return await _probeResponseCompleter!.future.timeout(
        frameTimeout,
        onTimeout: () {
          print(
            'SerialUtilWeb: probe timeout (${frameTimeout.inMilliseconds}ms) — '
            'rawRx=$_probeRxBytes B, buf=${_frameParser.bufferedBytes} B, '
            'start=${_frameParser.hasStartMarker}, end=${_frameParser.hasEndMarker}, '
            'adcSyncs=$_probeAdcFrameHits',
          );
          return _probeSawCompleteFrame;
        },
      );
    } finally {
      _cancelQueryRepeatTimer();
      _probeResponseCompleter = null;
    }
  }

  Future<bool> _tryProbeBaud(
    int baud, {
    bool acceptAdcStream = false,
    bool fastScan = false,
  }) async {
    final port = serialPort;
    if (port == null) {
      return false;
    }

    if (_portOpen) {
      await _stopProbeReading();
      await _closeSerialPortWithSettle();
      if (!fastScan) {
        await Future<void>.delayed(_probeReopenDelay);
      }
    }

    _writableSession++;
    _baudRate = baud;
    _probeSawCompleteFrame = false;
    _probeAcceptRx = false;
    _resetProbeRxState();

    try {
      await _openSerialPortWithRetry(probing: true);
    } catch (e) {
      print('SerialUtilWeb: probe open @$baud failed: $e');
      if (isSerialPortUnavailableError(e)) {
        throw SerialConnectAborted(e);
      }
      return false;
    }

    _probing = true;
    _probeReading = true;
    // Drain the port during settle without heavy parsing (avoids starving timers).
    // Windows Chromium + FTDI often delivers very large read chunks when bufferSize
    // is high; macOS web tends to be less aggressive, so this hang was mainly Windows.
    _probeAcceptRx = false;
    final ReadableStreamReader probeReader;
    try {
      probeReader = port.readable.reader;
    } catch (e) {
      print('SerialUtilWeb: probe getReader @$baud failed: $e');
      await _releaseProbeReaderLock();
      await _closeSerialPortWithSettle();
      throw SerialConnectAborted(e);
    }
    _probeActiveReader = probeReader;
    final probePump = _probeReadLoop(port, probeReader);

    try {
      await Future<void>.delayed(
        fastScan ? const Duration(milliseconds: 150) : _probeSettleTime,
      );
      _probeAcceptRx = true;

      var success = false;
      for (var attempt = 1; attempt <= _probeAttemptsPerBaud; attempt++) {
        if (attempt > 1) {
          print(
            'SerialUtilWeb: probe @$baud no response in '
            '${_probeQueryTimeout(attempt - 1, fastScan: fastScan).inMilliseconds}ms — retry $attempt/$_probeAttemptsPerBaud',
          );
        }
        success = await _sendQueryAndAwaitFrameProbe(
          fastScan: fastScan,
          attempt: attempt,
        );
        if (success) {
          break;
        }
        if (fastScan && attempt == 1 && _probeRxBytes == 0) {
          break;
        }
      }
      // Read loop may clear [_probeActiveReader] in its finally before we stop;
      // prefer the latest reader, then fall back to the one we started with.
      final readerToStop = _probeActiveReader ?? probeReader;
      await _stopProbeReadLoop(readerToStop, probePump);

      if (!success && acceptAdcStream && _probeAdcStreamLooksLikeDevice()) {
        print(
          'SerialUtilWeb: probe @$baud accepted via ADC stream '
          '(rawRx=$_probeRxBytes B, adcSyncs=$_probeAdcFrameHits)',
        );
        success = true;
      }

      if (success) {
        _probing = false;
        await _fullyReleasePortStreams();
      } else {
        await _fullyReleasePortStreams();
        await _closeSerialPortWithSettle();
      }
      return success;
    } on SerialConnectAborted {
      await _releaseProbeReaderLock();
      await _closeSerialPortWithSettle();
      rethrow;
    } catch (e, st) {
      print('SerialUtilWeb: probe @$baud error: $e\n$st');
      await _stopProbeReading();
      await _closeSerialPortWithSettle();
      if (isSerialPortUnavailableError(e)) {
        throw SerialConnectAborted(e);
      }
      return false;
    } finally {
      _probeAcceptRx = false;
      _probeActiveReader = null;
      _probeResponseCompleter = null;
    }
  }

  /// Baud probe uses [_probeActiveReader]; cancel + [releaseLock] before [SerialPort.close].
  Future<void> _releaseProbeReaderLock() async {
    _cancelQueryRepeatTimer();
    _probing = false;
    _completeProbeResponse(false);
    if (!_probeReading && _probeActiveReader == null) {
      return;
    }
    _intentionalProbeStop = true;
    final probeReader = _probeActiveReader;
    try {
      if (probeReader != null) {
        try {
          final cancelResult = (probeReader as dynamic).cancel();
          if (cancelResult is Future) {
            await cancelResult.timeout(_readCancelTimeout, onTimeout: () {});
          }
        } catch (_) {}
        await _releaseReaderLock(probeReader);
      }
    } finally {
      _probeReading = false;
      _probeActiveReader = null;
      _intentionalProbeStop = false;
      await Future<void>.delayed(const Duration(milliseconds: 80));
    }
  }

  Future<void> _stopProbeReading() async {
    await _releaseProbeReaderLock();
  }

  Future<void> _sendProbeQueryOnce() async {
    while (_probeWriteInFlight != null) {
      await _probeWriteInFlight;
    }
    final write = _sendProbeQueryOnceBody();
    _probeWriteInFlight = write;
    try {
      await write;
    } finally {
      if (identical(_probeWriteInFlight, write)) {
        _probeWriteInFlight = null;
      }
    }
  }

  Future<void> _sendProbeQueryOnceBody() async {
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
    } catch (e) {
      print('SerialUtilWeb: probe query send failed: $e');
    } finally {
      try {
        await w?.close();
      } catch (_) {}
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
    // _probeRxBytes += chunk.length;

    _noteProbeAdcStreamSync(chunk);

    // Same path as graph_template [_preEscapeSequenceBuffer] → MessageIdentifier.
    _probeMessageId.addPacket(chunk);

    if (!_probeSawCompleteFrame && _probeBytesContainDeviceToken(chunk)) {
      print('SerialUtilWeb: probe ASCII token in chunk @ $_baudRate');
      _onProbeCompleteFrame();
      return;
    }

    final asciiLenBefore = _probeAsciiWindow.length;
    _probeAsciiWindow.add(chunk);
    var asciiTrimmed = false;
    if (_probeAsciiWindow.length > _probeAsciiWindowMax) {
      asciiTrimmed = true;
      final all = _probeAsciiWindow.toBytes();
      _probeAsciiWindow.clear();
      _probeAsciiWindow.add(
        Uint8List.sublistView(all, all.length - _probeAsciiWindowMax),
      );
    }
    if (!_probeSawCompleteFrame && _probeAsciiWindow.isNotEmpty) {
      final haystack = _probeAsciiWindow.toBytes();
      final searchFrom = asciiTrimmed
          ? 0
          : (asciiLenBefore - _probeMaxDeviceTokenBytes + 1)
              .clamp(0, haystack.length);
      if (_probeBytesContainDeviceToken(haystack, start: searchFrom)) {
        print('SerialUtilWeb: probe ASCII token in stream @ $_baudRate');
        _onProbeCompleteFrame();
        return;
      }
    }

    if (_frameParser.feed(chunk)) {
      final frame = _frameParser.lastCompleteFrame;
      final payload = _frameParser.lastPayload;
      if (frame != null && payload != null) {
        if (_probeReplyIdentifiesDevice(payload)) {
          print(
            'SerialUtilWeb: probe frame OK (${frame.length} B, '
            '${payload.length} B payload) @ $_baudRate',
          );
          _onProbeCompleteFrame();
        }
      }
    }
  }

  bool _isRecoverableProbeReadError(Object e) =>
      isSerialRecoverableLineError(e);

  Future<ReadableStreamReader> _freshProbeReader(
    SerialPort port,
    ReadableStreamReader old,
  ) async {
    try {
      final cancelResult = (old as dynamic).cancel();
      if (cancelResult is Future) {
        await cancelResult.timeout(_readCancelTimeout, onTimeout: () {});
      }
    } catch (_) {}
    await _releaseReaderLock(old);
    if (!_probing) {
      await Future<void>.delayed(const Duration(milliseconds: 30));
    }
    try {
      final reader = port.readable.reader;
      _probeActiveReader = reader;
      return reader;
    } catch (e) {
      if (isSerialPortUnavailableError(e)) {
        throw SerialConnectAborted(e);
      }
      rethrow;
    }
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
          if (isSerialBreakError(e)) {
            // Cancel/wrong-baud BREAK — skip this read, keep the probe loop alive.
            await Future<void>.delayed(const Duration(milliseconds: 10));
            continue;
          }
          if (_probing && _isRecoverableProbeReadError(e)) {
            if (!_probeReading || serialPort == null) {
              break;
            }
            activeReader = await _freshProbeReader(port, activeReader);
            continue;
          }
          if (isSerialPortUnavailableError(e)) {
            throw SerialConnectAborted(e);
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
    print("RUN SERIAL LIFECYCLE 1000: $previous");
    await previous;
    print("RUN PREVIOUS FIN");
    try {
      print("RUN AWAIT ACTION");
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
      // Already inside _runSerialLifecycle — use _closePortBody, not closePort().
      if (serialPort != null) {
        await _closePortBody();
      }
      print("REQUEST SERIAL PORT");
      
      serialPort = await window.navigator.serial.requestPort();
      // Brief settle after picker — some drivers reject immediate open().
      await Future<void>.delayed(const Duration(milliseconds: 150));
      print("DELAY SERIAL PORT: $serialPort");
      portInfo = serialPort?.getInfo();
      print("portInfo: ${portInfo?.usbVendorId} ${portInfo?.usbProductId}");
      vendorId = portInfo?.usbVendorId ?? 0;
      productId = portInfo?.usbProductId ?? 0;

      int? detectedBaud;
      try {
        detectedBaud = await _autoDetectBaudRate();
      } on SerialConnectAborted catch (e) {
        print('SerialUtilWeb: baud scan aborted: $e');
        await _closePortBody();
        throw Exception('device unavailable');
      }
      if (detectedBaud == null) {
        print("detected baud == null");
        await _closePortBody();
        throw Exception('device unavailable');
      }
      _baudRate = detectedBaud;
      _listenBaudRecoveryRounds = 0;
      _resetLineErrorTracking();
      print("baudRate serial web (auto-detected): $_baudRate");
      if (await openPortToListen(" ", _baudRate) == null) {
        await _closePortBody();
        throw Exception("getReader failed");
      }
    } catch (e) {
      print("Port cancelled1: $e");
      final msg = e.toString();
      if (msg.contains("Null check operator used on a null value") || msg.contains("NotFoundError: Failed to execute 'requestPort'")) {
        print('bypass');
        throw Exception(msg);
      }
      if (e is SerialConnectAborted ||
          msg.contains('device unavailable') ||
          msg.contains("Failed to execute 'getReader'")) {
        try {
          await _closePortBody();
        } catch (_) {}
        if (msg.contains('device unavailable') || e is SerialConnectAborted) {
          throw Exception('device unavailable');
        }
        throw Exception('getReader failed');
      }
      try {
        await _closePortBody();
      } catch (_) {}
      print("Port opening failed: $e");
      throw Exception("Serial connections require Chrome, or Edge..");
      
    }
  }

  @override
  Future<void> closePort() async {
    return _runSerialLifecycle(_closePortBody);
  }

  Future<void> _closePortBody() async {
    final portToClose = serialPort;
    print("closePort 1000 start: $portToClose");
    // Drop in-flight writes that might still touch the writer while we tear down.
    _writableSession++;
    await _fullyReleasePortStreams();
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
      // Avoid compounding a transport error with a null-callback crash.
      // Some call paths write before `getAvailablePortsWeb` finishes wiring the callback,
      // and ChromeOS disconnections can tear down the port mid-session.
      try {
        await _teardownSerialPortAfterReadFailure();
      } catch (_) {}
      final cb = audioCallback;
      if (cb != null) {
        cb(1, null);
      }
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
    String? name,
    int baudRate, {
    bool replaceDataStream = true,
    List<int>? baudProbeCandidates,
  }) async {
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
        print("readable.reader first attempt failed: $e");
        await _fullyReleasePortStreams();
        await Future<void>.delayed(const Duration(milliseconds: 60));
        reader = readable.reader;
      }
      print("READER2");
      if (replaceDataStream) {
        _replaceDataStream();
      }
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
    var scheduleBaudRecovery = false;
    try {
      while (reader == activeReader && !outbound.isClosed) {
        try {
          final ReadableStreamDefaultReadResult result =
              await activeReader.read();
          if (result.done) {
            print("RESULT DONEZ");
            break;
          }
          _resetLineErrorTracking();
          if (!outbound.isClosed) {
            outbound.add(result.value);
          }
        } catch (e) {
          if (_intentionalReaderStop ||
              isSerialBreakError(e) ||
              isSerialReaderReleaseError(e)) {
            break;
          }
          if (isSerialRecoverableLineError(e) &&
              reader == activeReader &&
              serialPort != null) {
            if (_shouldScheduleListenBaudRecovery()) {
              print(
                'SerialUtilWeb: sustained ${serialLineErrorLabel(e)} — '
                'scheduling baud recovery',
              );
              scheduleBaudRecovery = true;
              await _stopActiveReaderForRecovery(activeReader);
              break;
            }
            final backoff = _nextReacquireBackoff();
            print(
              'SerialUtilWeb: ${serialLineErrorLabel(e)} — '
              're-acquiring reader (${backoff.inMilliseconds}ms backoff)',
            );
            await Future<void>.delayed(backoff);
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
      if (_intentionalReaderStop ||
          isSerialBreakError(e) ||
          isSerialReaderReleaseError(e)) {
        return;
      }
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
    } finally {
      if (scheduleBaudRecovery &&
          serialPort != null &&
          !_listenBaudRecoveryInProgress &&
          _listenBaudRecoveryRounds < _maxListenBaudRecoveryAttempts) {
        unawaited(_runListenBaudRecovery());
      }
    }
  }

  void _resetLineErrorTracking() {
    _consecutiveLineErrors = 0;
    _lineErrorWindowStart = null;
    _reacquireBackoffStep = 0;
  }

  bool _shouldScheduleListenBaudRecovery() {
    if (_probing || _listenBaudRecoveryInProgress) {
      return false;
    }
    if (_listenBaudRecoveryRounds >= _maxListenBaudRecoveryAttempts) {
      return false;
    }
    final now = DateTime.now();
    _lineErrorWindowStart ??= now;
    if (now.difference(_lineErrorWindowStart!) > _lineErrorRecoveryWindow) {
      _consecutiveLineErrors = 0;
      _lineErrorWindowStart = now;
    }
    _consecutiveLineErrors++;
    return _consecutiveLineErrors >= _lineErrorsBeforeBaudRecovery;
  }

  Duration _nextReacquireBackoff() {
    final scaled =
        _reacquireBackoffBase.inMilliseconds * (1 << _reacquireBackoffStep);
    _reacquireBackoffStep++;
    final capped = scaled > _reacquireBackoffMax.inMilliseconds
        ? _reacquireBackoffMax.inMilliseconds
        : scaled;
    return Duration(milliseconds: capped);
  }

  List<int> _listenBaudRecoveryCandidates() {
    final current = _baudRate;
    final others =
        _probeBaudRates.where((b) => b != current).toList(growable: true);
    if (vendorId == 0x0403 && productId == 0x6015) {
      others.sort((a, b) {
        if (a == 500000) return -1;
        if (b == 500000) return 1;
        return _probeBaudRates.indexOf(a).compareTo(_probeBaudRates.indexOf(b));
      });
    }
    return [...others, current];
  }

  Future<void> _stopActiveReaderForRecovery(
      ReadableStreamReader activeReader) async {
    _intentionalReaderStop = true;
    if (identical(reader, activeReader)) {
      reader = null;
    }
    try {
      final cancelResult = (activeReader as dynamic).cancel();
      if (cancelResult is Future) {
        await cancelResult.timeout(_readCancelTimeout, onTimeout: () {});
      }
    } catch (_) {}
    await _releaseReaderLock(activeReader);
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }

  Future<void> _runListenBaudRecovery() async {
    if (_listenBaudRecoveryInProgress || serialPort == null) {
      return;
    }
    _listenBaudRecoveryInProgress = true;
    _listenBaudRecoveryRounds++;
    try {
      try {
        await (_readPumpFuture ?? Future<void>.value())
            .timeout(_readPumpJoinTimeout, onTimeout: () {});
      } catch (_) {}
      _readPumpFuture = null;
      final recovered = await _runSerialLifecycle(_recoverListenBaudBody);
      if (!recovered) {
        print('SerialUtilWeb: listen baud recovery exhausted');
        unawaited(_teardownSerialPortAfterReadFailure().then((_) {
          final cb = audioCallback;
          if (cb != null && !isOpeningFile) {
            try {
              cb(1, null);
            } catch (_) {}
          }
        }));
      }
    } finally {
      _listenBaudRecoveryInProgress = false;
      _intentionalReaderStop = false;
      _resetLineErrorTracking();
    }
  }

  Future<bool> _recoverListenBaudBody() async {
    if (serialPort == null) {
      return false;
    }
    print(
      'SerialUtilWeb: listen baud recovery (was $_baudRate, '
      'round $_listenBaudRecoveryRounds/$_maxListenBaudRecoveryAttempts)',
    );
    _writableSession++;
    await _fullyReleasePortStreams();

    for (final baud in _listenBaudRecoveryCandidates()) {
      print('SerialUtilWeb: listen recovery trying $baud');
      final ok = await _tryProbeBaud(baud, acceptAdcStream: false);
      if (!ok) {
        continue;
      }
      _baudRate = baud;
      await openPortToListen(' ', _baudRate, replaceDataStream: false);
      _notifyBaudRecovered();
      print('SerialUtilWeb: listen recovery OK @$_baudRate');
      return true;
    }
    return false;
  }

  void _notifyBaudRecovered() {
    final cb = audioCallback;
    if (cb == null || isOpeningFile) {
      return;
    }
    try {
      cb(2, null);
    } catch (e) {
      print('SerialUtilWeb: baud recovery callback error: $e');
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
    _probeActiveReader = null;
    _probeReading = false;
    portInfo = null;
    // After "device lost", the underlying handle is typically invalid; force a fresh
    // requestPort() next time instead of repeatedly failing open().
    serialPort = null;
    _portOpen = false;
    _replaceDataStream();
  }

  /// Connection is directly established with the selected port
  @override
  Future<void> getAvailablePorts(int baudRate, Function callback) async {
    audioCallback = callback;
    _baudRate = baudRate;
    try {
      await connectToPort();
    } catch (err) {
      throw Exception("Serial connections require Chrome, or Edge...");
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
        throw Exception(err.toString());
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
      if (err.toString().contains("Null check operator used on a null value") || err.toString().contains("NotFoundError: Failed to execute 'requestPort'")) {
        throw Exception("BYPASS");
      } else
      if (err.toString().contains("getReader failed")) {
        throw Exception("getReader failed");
      } else if (err.toString().contains("device unavailable")) {
        throw Exception("device unavailable");
      } else {
        throw Exception("Serial connections require Chrome, or Edge....");
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
    await _releaseProbeReaderLock();
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

  Future<void> _openSerialPortWithRetry({bool probing = false}) async {
    final port = serialPort;
    if (port == null || _portOpen) {
      return;
    }

    Object? lastError;
    print("openSerialPortWithRetry start: $_baudRate probing=$probing");
    // During probe, skip hardware flow control so hwTypeInquiry can be written.
    final flow = probing || !_useHardwareFlowControl
        ? FlowControl.none
        : FlowControl.hardware;
    final attempts = probing
        ? <Future<void> Function()>[
            () => port.open(
                  baudRate: _baudRate,
                  dataBits: DataBits.eight,
                  stopBits: StopBits.one,
                  parity: Parity.none,
                  bufferSize: _probeBufferSize,
                  flowControl: flow,
                ),
            () => port.open(baudRate: _baudRate),
          ]
        : <Future<void> Function()>[
            () => port.open(
                  baudRate: _baudRate,
                  dataBits: DataBits.eight,
                  stopBits: StopBits.one,
                  parity: Parity.none,
                  bufferSize: _serialBufferSize,
                  flowControl: flow,
                ),
            () => port.open(
                  baudRate: _baudRate,
                  dataBits: DataBits.eight,
                  stopBits: StopBits.one,
                  parity: Parity.none,
                  bufferSize: 8192,
                  flowControl: flow,
                ),
            () => port.open(baudRate: _baudRate),
          ];

    for (var i = 0; i < attempts.length; i++) {
      try {
        await attempts[i]();
        _portOpen = true;
        if (!probing) {
          await _trySetPortSignals(port);
        }
        if (i > 0) {
          print(
              'SerialUtilWeb: open @$_baudRate succeeded on attempt ${i + 1}');
        }
        return;
      } catch (e) {
        if (_isPortAlreadyOpenError(e)) {
          _portOpen = true;
          if (!probing) {
            await _trySetPortSignals(port);
          }
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
        requestToSend: true,
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
    _intentionalReaderStop = true;
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
    } catch (_) {
    } finally {
      _intentionalReaderStop = false;
    }
  }

  @override
  int get detectedBaudRate => _baudRate;
  
  /// Full unlock + close — use after getReader failures or USB disconnect.
  @override
  Future<void> resetPort() async {
    return _runSerialLifecycle(_closePortBody);
  }
}
