import 'dart:async';
import 'dart:typed_data';

import 'package:spikerbox_architecture/models/serial_util/serial_device_frame_parser.dart';
import 'package:spikerbox_architecture/models/usb_protocol/commands.dart';

/// Shared BYB baud auto-detection (same rates/timeouts as [SerialUtilWeb]).
class SerialBaudAutoProbe {
  SerialBaudAutoProbe({this.logTag = 'SerialBaudAutoProbe'});

  final String logTag;

  static const List<int> probeBaudRates = [500000, 230400, 222222];
  static final Uint8List probeQueryBytes =
      UsbCommand.hwTypeInquiry.cmdAsBytes();
  static const Duration probeSettleTime = Duration(milliseconds: 150);
  static const Duration probeReopenDelay = Duration(milliseconds: 300);
  static const Duration probeFrameTimeout = Duration(seconds: 1);
  static const int probeAttemptsPerBaud = 2;
  static const int probeBaudScanRounds = 5;

  final SerialDeviceFrameParser _frameParser = SerialDeviceFrameParser();
  bool _probing = false;
  bool _probeAcceptRx = false;
  bool _probeSawCompleteFrame = false;
  int _probeRxBytes = 0;
  int _probeBaud = 0;
  Completer<bool>? _probeResponseCompleter;
  Timer? _queryRepeatTimer;
  StreamSubscription<Uint8List>? _probeSubscription;

  /// Tries [probeBaudRates] in order; first baud with a valid escape frame wins.
  Future<int?> detect({
    required Future<bool> Function(int baud) tryProbeBaud,
  }) async {
    try {
      for (var round = 1; round <= probeBaudScanRounds; round++) {
        if (round > 1) {
          print(
            '$logTag: all baud rates failed — rescan round $round/$probeBaudScanRounds',
          );
        }
        for (final baud in probeBaudRates) {
          print('$logTag: probing baud $baud (round $round)');
          final ok = await tryProbeBaud(baud);
          if (ok) {
            return baud;
          }
          await Future<void>.delayed(probeReopenDelay);
        }
      }
      return null;
    } finally {
      _cancelQueryRepeatTimer();
      _probing = false;
      await _stopProbeSubscription();
    }
  }

  /// Opens at [baud], listens on [rxStream], sends hw inquiry, waits for a frame.
  Future<bool> probeAtBaud({
    required int baud,
    required Future<bool> Function(int baud) openAtBaud,
    required Future<void> Function() closePort,
    required Future<void> Function() writeQuery,
    required Stream<Uint8List>? Function() rxStream,
  }) async {
    await closePort();
    await Future<void>.delayed(probeReopenDelay);

    _frameParser.reset();
    _probeSawCompleteFrame = false;
    _probeAcceptRx = false;
    _probeRxBytes = 0;
    _probeBaud = baud;

    if (!await openAtBaud(baud)) {
      print('$logTag: probe open @$baud failed');
      await closePort();
      return false;
    }

    _probing = true;
    final stream = rxStream();
    if (stream == null) {
      print('$logTag: probe @$baud — no RX stream');
      _probing = false;
      await closePort();
      return false;
    }

    _probeSubscription = stream.listen(
      _onProbeRxChunk,
      onError: (Object e) {
        print('$logTag: probe read error @$baud: $e');
        _completeProbeResponse(_probeSawCompleteFrame);
      },
      onDone: () {
        _completeProbeResponse(_probeSawCompleteFrame);
      },
    );

    try {
      await Future<void>.delayed(probeSettleTime);
      var success = false;
      for (var attempt = 1; attempt <= probeAttemptsPerBaud; attempt++) {
        if (attempt > 1) {
          print(
            '$logTag: probe @$baud no response in '
            '${probeFrameTimeout.inSeconds}s — retry $attempt/$probeAttemptsPerBaud',
          );
        }
        success = await _sendQueryAndAwaitFrame(writeQuery);
        if (success) {
          break;
        }
      }
      return success;
    } catch (e, st) {
      print('$logTag: probe @$baud error: $e\n$st');
      return false;
    } finally {
      _probing = false;
      _probeAcceptRx = false;
      await _stopProbeSubscription();
      if (!_probeSawCompleteFrame) {
        await closePort();
      }
      _probeResponseCompleter = null;
    }
  }

  void _cancelQueryRepeatTimer() {
    _queryRepeatTimer?.cancel();
    _queryRepeatTimer = null;
  }

  void _startQueryRepeatTimer(Future<void> Function() writeQuery) {
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
      unawaited(writeQuery());
    });
  }

  Future<bool> _sendQueryAndAwaitFrame(
    Future<void> Function() writeQuery,
  ) async {
    _probeSawCompleteFrame = false;
    _frameParser.reset();
    _probeResponseCompleter = Completer<bool>();

    await writeQuery();
    if (_probing) {
      _frameParser.reset();
      _probeAcceptRx = true;
      _startQueryRepeatTimer(writeQuery);
    }

    try {
      return await _probeResponseCompleter!.future.timeout(
        probeFrameTimeout,
        onTimeout: () {
          print(
            '$logTag: probe timeout (${probeFrameTimeout.inSeconds}s) — '
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
    final frame = _frameParser.lastCompleteFrame;
    final payload = _frameParser.lastPayload;
    if (frame != null && payload != null) {
      print(
        '$logTag: probe frame OK (${frame.length} B, '
        '${payload.length} B payload) @ $_probeBaud',
      );
    }
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
        _onProbeCompleteFrame();
      }
    }
  }

  Future<void> _stopProbeSubscription() async {
    await _probeSubscription?.cancel();
    _probeSubscription = null;
  }
}
