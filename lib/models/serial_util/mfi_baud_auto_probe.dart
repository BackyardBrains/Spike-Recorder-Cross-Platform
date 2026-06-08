import 'dart:async';
import 'dart:typed_data';

import 'package:byb_accessory/byb_accessory.dart';
import 'package:spikerbox_architecture/message_identifier.dart';
import 'package:spikerbox_architecture/models/usb_protocol/commands.dart';

/// MFi baud auto-scan — same rate list and hwType probe as Android/Web.
///
/// Unlike USB serial, MFi continuously streams ADC escape frames, so we must
/// not treat a bare frame as success (that always matches at the first baud,
/// usually 500000 from [ConstantProvider]). Probe succeeds only on an hwType
/// device-identification reply (HWT:…; / board tokens), matching [SerialUtilWeb].
class MfiBaudAutoProbe {
  MfiBaudAutoProbe({this.logTag = 'MfiBaudAutoProbe'});

  final String logTag;

  static const List<int> probeBaudRates = [500000, 230400, 222222];
  static final Uint8List probeQueryBytes =
      UsbCommand.hwTypeInquiry.cmdAsBytes();

  static const Duration probeSettleTime = Duration(milliseconds: 150);
  static const Duration probeReopenDelay = Duration(milliseconds: 300);
  static const Duration probeFrameTimeout = Duration(seconds: 1);
  static const int probeAttemptsPerBaud = 2;
  static const int probeBaudScanRounds = 5;
  static const int _maxAsciiWindowBytes = 512;

  static const List<String> _deviceReplyTokens = [
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

  static final List<Uint8List> _replyTokenBytes = [
    ..._deviceReplyTokens
        .map((t) => Uint8List.fromList(t.codeUnits)),
    ..._deviceReplyTokens
        .map((t) => Uint8List.fromList('HWT:$t'.codeUnits)),
  ];

  int _detectedBaud = 0;
  int get detectedBaudRate => _detectedBaud;

  bool _probing = false;
  bool _probeAcceptRx = false;
  bool _probeSawReply = false;
  Completer<bool>? _probeCompleter;
  Timer? _queryRepeatTimer;
  StreamSubscription<Uint8List>? _probeSubscription;
  final BytesBuilder _asciiWindow = BytesBuilder(copy: false);
  late final MessageIdentifier _messageId = MessageIdentifier(
    onDeviceData: (_) {},
    onDeviceMessage: (Uint8List msg) {
      if (!_probing || !_probeAcceptRx || _probeSawReply) {
        return;
      }
      if (_bytesContainDeviceToken(msg)) {
        _onProbeDeviceReply();
      }
    },
  );

  /// Tries [candidates] in order (deduped), then full [probeBaudRates] rescan.
  Future<int?> detectWithCandidates(List<int> candidates) async {
    if (!await BybAccessory.isConnected()) {
      print('$logTag: accessory not connected');
      return null;
    }

    final ordered = _normalizeCandidates(candidates);
    try {
      for (final baud in ordered) {
        if (await _probeAtBaud(baud)) {
          return baud;
        }
        await Future<void>.delayed(probeReopenDelay);
      }

      print('$logTag: candidate bauds failed — trying full auto-detect');
      for (var round = 1; round <= probeBaudScanRounds; round++) {
        if (round > 1) {
          print('$logTag: rescan round $round/$probeBaudScanRounds');
        }
        for (final baud in probeBaudRates) {
          if (await _probeAtBaud(baud)) {
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

  Future<bool> _probeAtBaud(int baud) async {
    print('$logTag: probing baud $baud');
    _detectedBaud = baud;
    _probeSawReply = false;
    _probeAcceptRx = false;
    _asciiWindow.clear();
    _messageId.reset();

    if (!await BybAccessory.isConnected()) {
      print('$logTag: probe @$baud — not connected');
      return false;
    }

    _probing = true;
    _probeSubscription = BybAccessory.rxBytesStream.listen(
      _onProbeRxChunk,
      onError: (Object e) {
        print('$logTag: probe read error @$baud: $e');
        _completeProbe(_probeSawReply);
      },
      onDone: () => _completeProbe(_probeSawReply),
    );

    try {
      await Future<void>.delayed(probeSettleTime);
      for (var attempt = 1; attempt <= probeAttemptsPerBaud; attempt++) {
        if (attempt > 1) {
          print(
            '$logTag: probe @$baud retry $attempt/$probeAttemptsPerBaud',
          );
        }
        if (await _sendQueryAndAwaitReply()) {
          print('$logTag: probe OK @ $baud');
          return true;
        }
      }
      return false;
    } catch (e, st) {
      print('$logTag: probe @$baud error: $e\n$st');
      return false;
    } finally {
      _probing = false;
      _probeAcceptRx = false;
      await _stopProbeSubscription();
      _probeCompleter = null;
    }
  }

  Future<bool> _sendQueryAndAwaitReply() async {
    _probeSawReply = false;
    _asciiWindow.clear();
    _messageId.reset();
    _probeCompleter = Completer<bool>();

    await BybAccessory.sendBytes(probeQueryBytes);
    _probeAcceptRx = true;
    _startQueryRepeatTimer();

    try {
      return await _probeCompleter!.future.timeout(
        probeFrameTimeout,
        onTimeout: () => _probeSawReply,
      );
    } finally {
      _cancelQueryRepeatTimer();
      _probeAcceptRx = false;
    }
  }

  void _onProbeRxChunk(Uint8List chunk) {
    if (!_probing || !_probeAcceptRx || _probeSawReply) {
      return;
    }

    _messageId.addPacket(chunk);

    if (_bytesContainDeviceToken(chunk)) {
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
    if (_bytesContainDeviceToken(haystack, start: searchFrom)) {
      _onProbeDeviceReply();
    }
  }

  void _onProbeDeviceReply() {
    _probeSawReply = true;
    _cancelQueryRepeatTimer();
    _completeProbe(true);
  }

  bool _bytesContainDeviceToken(Uint8List haystack, {int start = 0}) {
    if (haystack.isEmpty || start >= haystack.length) {
      return false;
    }
    for (final needle in _replyTokenBytes) {
      if (_containsSublist(haystack, needle, start)) {
        return true;
      }
    }
    return false;
  }

  bool _containsSublist(Uint8List haystack, Uint8List needle, int start) {
    if (needle.isEmpty || haystack.length - start < needle.length) {
      return false;
    }
    outer:
    for (var i = start; i <= haystack.length - needle.length; i++) {
      for (var j = 0; j < needle.length; j++) {
        if (haystack[i + j] != needle[j]) {
          continue outer;
        }
      }
      return true;
    }
    return false;
  }

  void _startQueryRepeatTimer() {
    _cancelQueryRepeatTimer();
    if (!_probing) {
      return;
    }
    _queryRepeatTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final c = _probeCompleter;
      if (!_probing || c == null || c.isCompleted) {
        timer.cancel();
        _queryRepeatTimer = null;
        return;
      }
      unawaited(BybAccessory.sendBytes(probeQueryBytes));
    });
  }

  void _cancelQueryRepeatTimer() {
    _queryRepeatTimer?.cancel();
    _queryRepeatTimer = null;
  }

  void _completeProbe(bool success) {
    final c = _probeCompleter;
    if (c == null || c.isCompleted) {
      return;
    }
    c.complete(success);
  }

  Future<void> _stopProbeSubscription() async {
    await _probeSubscription?.cancel();
    _probeSubscription = null;
  }
}
