import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spikerbox_architecture/models/serial_util/serial_device_frame_parser.dart';

void main() {
  group('SerialDeviceFrameParser', () {
    late SerialDeviceFrameParser parser;

    setUp(() {
      parser = SerialDeviceFrameParser();
    });

    test('detects a complete frame in one chunk', () {
      final payload = Uint8List.fromList([0x62, 0x3A, 0x3B, 0x0A]); // b:;\n
      final frame = Uint8List.fromList([
        ...SerialDeviceFrameParser.startMarker,
        ...payload,
        ...SerialDeviceFrameParser.endMarker,
      ]);

      expect(parser.feed(frame), isTrue);
      expect(parser.lastPayload, payload);
      expect(parser.lastCompleteFrame, frame);
    });

    test('reassembles a frame split across chunks', () {
      final payload = Uint8List.fromList([1, 2, 3]);
      final frame = Uint8List.fromList([
        ...SerialDeviceFrameParser.startMarker,
        ...payload,
        ...SerialDeviceFrameParser.endMarker,
      ]);

      expect(parser.feed(Uint8List.sublistView(frame, 0, 4)), isFalse);
      expect(parser.feed(Uint8List.sublistView(frame, 4)), isTrue);
      expect(parser.lastPayload, payload);
    });

    test('keeps tail bytes when start marker is incomplete', () {
      final partialStart = Uint8List.fromList([0xFF, 0xFF, 0x01]);
      expect(parser.feed(partialStart), isFalse);
      expect(parser.lastCompleteFrame, isNull);

      final rest = Uint8List.fromList([
        0x01,
        0x80,
        0xFF,
        0xAA,
        ...SerialDeviceFrameParser.endMarker,
      ]);
      expect(parser.feed(rest), isTrue);
      expect(parser.lastPayload, Uint8List.fromList([0xAA]));
    });

    test('reset clears buffered state', () {
      parser.feed(Uint8List.fromList([0xFF, 0xFF]));
      parser.reset();
      expect(parser.feed(Uint8List(0)), isFalse);
      expect(parser.lastCompleteFrame, isNull);
    });

    test('reports partial marker state', () {
      parser.feed(SerialDeviceFrameParser.startMarker);
      expect(parser.bufferedBytes, 6);
      expect(parser.hasStartMarker, isTrue);
      expect(parser.hasEndMarker, isFalse);
    });
  });
}
