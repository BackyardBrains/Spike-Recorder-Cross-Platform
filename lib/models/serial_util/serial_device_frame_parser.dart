import 'dart:typed_data';

/// Parses BYB device frames:
/// start  FF FF 01 01 80 FF  |  payload  |  end  FF FF 01 01 81 FF
class SerialDeviceFrameParser {
  SerialDeviceFrameParser();

  static final Uint8List startMarker = Uint8List.fromList([
    0xFF,
    0xFF,
    0x01,
    0x01,
    0x80,
    0xFF,
  ]);

  static final Uint8List endMarker = Uint8List.fromList([
    0xFF,
    0xFF,
    0x01,
    0x01,
    0x81,
    0xFF,
  ]);

  final BytesBuilder _buffer = BytesBuilder(copy: false);

  Uint8List? lastCompleteFrame;
  Uint8List? lastPayload;

  int get bufferedBytes => _buffer.length;

  bool get hasStartMarker => _indexOf(_buffer.toBytes(), startMarker) >= 0;

  bool get hasEndMarker {
    final data = _buffer.toBytes();
    final start = _indexOf(data, startMarker);
    if (start < 0) {
      return false;
    }
    return _indexOf(data, endMarker, start + startMarker.length) >= 0;
  }

  void reset() {
    _buffer.clear();
    lastCompleteFrame = null;
    lastPayload = null;
  }

  /// Returns true when a new full frame (start + payload + end) is ready.
  bool feed(Uint8List chunk) {
    if (chunk.isNotEmpty) {
      _buffer.add(chunk);
    }
    return _scan();
  }

  bool _scan() {
    var data = _buffer.toBytes();
    var found = false;

    while (true) {
      final start = _indexOf(data, startMarker);
      if (start < 0) {
        _keepTail(data, startMarker.length - 1);
        return found;
      }

      final payloadStart = start + startMarker.length;
      final end = _indexOf(data, endMarker, payloadStart);
      if (end < 0) {
        if (start > 0) {
          data = Uint8List.sublistView(data, start);
          _buffer.clear();
          _buffer.add(data);
        }
        return found;
      }

      final frameEnd = end + endMarker.length;
      lastCompleteFrame = Uint8List.sublistView(data, start, frameEnd);
      lastPayload = Uint8List.sublistView(data, payloadStart, end);
      found = true;

      if (frameEnd >= data.length) {
        _buffer.clear();
        return true;
      }

      data = Uint8List.sublistView(data, frameEnd);
      _buffer.clear();
      _buffer.add(data);
    }
  }

  void _keepTail(Uint8List data, int maxLen) {
    if (maxLen <= 0 || data.length <= maxLen) {
      return;
    }
    _buffer.clear();
    _buffer.add(Uint8List.sublistView(data, data.length - maxLen));
  }

  static int _indexOf(Uint8List data, Uint8List pattern, [int from = 0]) {
    if (pattern.isEmpty || data.length < pattern.length) {
      return -1;
    }
    final last = data.length - pattern.length;
    for (var i = from; i <= last; i++) {
      var matched = true;
      for (var j = 0; j < pattern.length; j++) {
        if (data[i + j] != pattern[j]) {
          matched = false;
          break;
        }
      }
      if (matched) {
        return i;
      }
    }
    return -1;
  }
}
