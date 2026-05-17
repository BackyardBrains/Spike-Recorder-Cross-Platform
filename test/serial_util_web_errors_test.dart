import 'package:flutter_test/flutter_test.dart';
import 'package:spikerbox_architecture/models/serial_util/serial_line_errors.dart';

void main() {
  test('detects BufferOverrunError message forms', () {
    expect(isSerialBufferOverrunError(Exception('BufferOverrunError')), isTrue);
    expect(isSerialBufferOverrunError(Exception('Buffer overrun')), isTrue);
  });

  test('detects FramingError message forms', () {
    expect(isSerialFramingError(Exception('FramingError: Framing error')), isTrue);
  });

  test('detects BreakError from reader cancel', () {
    expect(isSerialBreakError(Exception('BreakError: Break received')), isTrue);
    expect(isSerialBreakError(Exception('Break received')), isTrue);
  });

  test('detects reader release race message', () {
    expect(
      isSerialReaderReleaseError(
          Exception('TypeError: Releasing Default reader')),
      isTrue,
    );
  });

  test('detects already-closed port on close', () {
    expect(
      isSerialPortAlreadyClosedError(Exception(
          "InvalidStateError: Failed to execute 'close' on 'SerialPort': The port is already closed.")),
      isTrue,
    );
  });

  test('build id is set for deployment verification', () {
    expect(kSerialUtilWebBuildId, contains('serial-web'));
  });
}
