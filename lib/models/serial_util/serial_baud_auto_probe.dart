import 'dart:async';
import 'dart:typed_data';

import 'package:spikerbox_architecture/message_identifier.dart';
import 'package:spikerbox_architecture/models/usb_protocol/commands.dart';

/// Shared BYB baud auto-detection (same rates/timeouts as [SerialUtilWeb]).
///
/// Probe success requires an hwType device-identification reply (e.g.
/// `HWT:MUSCUSB1;`), not a bare ADC escape frame.
class SerialBaudAutoProbe {
  SerialBaudAutoProbe({this.logTag = 'SerialBaudAutoProbe'});

  final String logTag;

  static const List<int> probeBaudRates = [500000, 230400, 222222];
  static final Uint8List probeQueryBytes =
      UsbCommand.hwTypeInquiry.cmdAsBytes();
  static const Duration probeSettleTime = Duration(milliseconds: 400);
  static const Duration probeReopenDelay = Duration(milliseconds: 300);
  static const Duration probeFrameTimeoutDefault =
      Duration(milliseconds: 3000);
  static const Duration probeFrameTimeout500k = Duration(milliseconds: 3000);
  static const int probeAttemptsPerBaud = 2;
  static const int probeBaudScanRounds = 5;

  Duration _probeFrameTimeoutForBaud(int baud) =>
      baud == 500000 ? probeFrameTimeout500k : probeFrameTimeoutDefault;
  static const int _maxAsciiWindowBytes = 512;

  static const List<String> deviceReplyTokens = [
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

  /// Probe success requires an hwType device-identification reply (e.g.
  /// `HWT:MUSCUSB1;` / `HWT:HBLEOSB;`). Bare board ids are rejected — they
  /// appear by chance in wrong-baud UART noise.
  static final List<Uint8List> _replyTokenBytes = [
    ...deviceReplyTokens.map((t) => Uint8List.fromList('HWT:$t'.codeUnits)),
  ];

  bool _probing = false;
  bool _probeAcceptRx = false;
  bool _probeSawDeviceReply = false;
  int _probeRxBytes = 0;
  int _probeBaud = 0;
  Completer<bool>? _probeResponseCompleter;
  Timer? _queryRepeatTimer;
  StreamSubscription<Uint8List>? _probeSubscription;
  final BytesBuilder _asciiWindow = BytesBuilder(copy: false);
  late final MessageIdentifier _messageId = MessageIdentifier(
    onDeviceData: (_) {},
    onDeviceMessage: (Uint8List msg) {
      if (!_probing || !_probeAcceptRx || _probeSawDeviceReply) {
        return;
      }
      if (bytesContainDeviceReplyToken(msg)) {
        _onProbeDeviceReply();
      }
    },
  );

  static bool bytesContainDeviceReplyToken(
    Uint8List haystack, {
    int start = 0,
  }) {
    if (haystack.isEmpty || start >= haystack.length) {
      return false;
    }
    for (final needle in _replyTokenBytes) {
      if (_bytesContains(haystack, needle, start)) {
        return true;
      }
    }
    return false;
  }

  static bool _bytesContains(Uint8List haystack, Uint8List needle, int start) {
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

  Future<int?> detect({
    required Future<bool> Function(int baud) tryProbeBaud,
  }) {
    return detectWithCandidates(probeBaudRates, tryProbeBaud: tryProbeBaud);
  }

  /// Tries [candidates] first (deduped), then remaining [probeBaudRates].
  Future<int?> detectWithCandidates(
    List<int> candidates, {
    required Future<bool> Function(int baud) tryProbeBaud,
  }) async {
    final ordered = _normalizeCandidates(candidates);
    try {
      for (var round = 1; round <= probeBaudScanRounds; round++) {
        if (round > 1) {
          print(
            '$logTag: all baud rates failed — rescan round $round/$probeBaudScanRounds',
          );
        }
        for (final baud in ordered) {
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

  List<int> _normalizeCandidates(List<int> raw) {
    final ordered = <int>[];
    for (final baud in raw) {
      if (baud > 0 && !ordered.contains(baud)) {
        ordered.add(baud);
      }
    }
    for (final baud in probeBaudRates) {
      if (!ordered.contains(baud)) {
        ordered.add(baud);
      }
    }
    return ordered;
  }

  Future<bool> probeAtBaud({
    required int baud,
    required Future<bool> Function(int baud) openAtBaud,
    required Future<void> Function() closePort,
    required Future<void> Function() writeQuery,
    required Stream<Uint8List>? Function() rxStream,
    Future<void> Function()? stopRxStream,
  }) async {
    await closePort();
    await Future<void>.delayed(probeReopenDelay);

    _asciiWindow.clear();
    _messageId.reset();
    _probeSawDeviceReply = false;
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
        _completeProbeResponse(_probeSawDeviceReply);
      },
      onDone: () {
        _completeProbeResponse(_probeSawDeviceReply);
      },
    );

    try {
      await Future<void>.delayed(probeSettleTime);
      var success = false;
      for (var attempt = 1; attempt <= probeAttemptsPerBaud; attempt++) {
        if (attempt > 1) {
          print(
            '$logTag: probe @$baud no response in '
            '${_probeFrameTimeoutForBaud(baud).inMilliseconds}ms — retry $attempt/$probeAttemptsPerBaud',
          );
        }
        success = await _sendQueryAndAwaitReply(writeQuery);
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
      if (stopRxStream != null) {
        await stopRxStream();
      }
      if (!_probeSawDeviceReply) {
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

  Future<bool> _sendQueryAndAwaitReply(
    Future<void> Function() writeQuery,
  ) async {
    _probeSawDeviceReply = false;
    _asciiWindow.clear();
    _messageId.reset();
    _probeResponseCompleter = Completer<bool>();

    await writeQuery();
    if (_probing) {
      _probeAcceptRx = true;
      _startQueryRepeatTimer(writeQuery);
    }

    try {
      final timeout = _probeFrameTimeoutForBaud(_probeBaud);
      return await _probeResponseCompleter!.future.timeout(
        timeout,
        onTimeout: () {
          print(
            '$logTag: probe timeout (${timeout.inMilliseconds}ms) @ $_probeBaud — '
            'rawRx=$_probeRxBytes B',
          );
          return _probeSawDeviceReply;
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

  void _onProbeDeviceReply() {
    _probeSawDeviceReply = true;
    _cancelQueryRepeatTimer();
    print('$logTag: probe hwType reply OK @ $_probeBaud');
    _completeProbeResponse(true);
  }

  void _onProbeRxChunk(Uint8List chunk) {
    _probeRxBytes += chunk.length;
    if (_probing && !_probeAcceptRx) {
      return;
    }

    _messageId.addPacket(chunk);
    if (_probeSawDeviceReply) {
      return;
    }

    if (bytesContainDeviceReplyToken(chunk)) {
      _onProbeDeviceReply();
      return;
    }

    final lenBefore = _asciiWindow.length;
    _asciiWindow.add(chunk);
    if (_asciiWindow.length > _maxAsciiWindowBytes) {
      final tail = _asciiWindow.toBytes();
      _asciiWindow.clear();
      _asciiWindow.add(
        tail.sublist(tail.length - _maxAsciiWindowBytes ~/ 2),
      );
    }
    final haystack = _asciiWindow.toBytes();
    final searchFrom =
        (lenBefore - _maxAsciiWindowBytes + 1).clamp(0, haystack.length);
    if (bytesContainDeviceReplyToken(haystack, start: searchFrom)) {
      _onProbeDeviceReply();
    }
  }

  Future<void> _stopProbeSubscription() async {
    await _probeSubscription?.cancel();
    _probeSubscription = null;
  }
}
