import 'package:flutter_test/flutter_test.dart';
import 'package:spikerbox_architecture/models/serial_util/serial_line_errors.dart';

void main() {
  group('listen-mode line error classification', () {
    test('FramingError is recoverable for reader re-acquire', () {
      expect(
        isSerialRecoverableLineError(Exception('FramingError: Framing error')),
        isTrue,
      );
    });

    test('ParityError is recoverable', () {
      expect(
        isSerialRecoverableLineError(Exception('ParityError: Parity error')),
        isTrue,
      );
    });

    test('BreakError is not a recoverable line error', () {
      expect(
        isSerialRecoverableLineError(Exception('BreakError: Break received')),
        isFalse,
      );
    });
  });
}
