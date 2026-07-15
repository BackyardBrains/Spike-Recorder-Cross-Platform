/// Web-serial line error helpers (no `dart:html` / `package:serial` imports).
const String kSerialUtilWebBuildId = 'serial-web-2026-07-15-fast-fail-wrong-baud-v2';

bool isSerialBufferOverrunError(Object error) {
  final message = error.toString();
  return message.contains('BufferOverrunError') ||
      message.contains('Buffer overrun');
}

bool isSerialFramingError(Object error) {
  final message = error.toString();
  return message.contains('FramingError') || message.contains('Framing error');
}

/// UART parity mismatch — common when baud rate is wrong during auto-probe.
bool isSerialParityError(Object error) {
  final message = error.toString();
  return message.contains('ParityError') || message.contains('Parity error');
}

/// Read cancelled because we released the reader (not a baud-rate mismatch).
bool isSerialBreakError(Object error) {
  final message = error.toString();
  return message.contains('BreakError') || message.contains('Break received');
}

bool isSerialReaderReleaseError(Object error) {
  final message = error.toString();
  return message.contains('Releasing Default reader') ||
      message.contains('Releasing');
}

String serialLineErrorLabel(Object error) {
  if (isSerialBufferOverrunError(error)) {
    return 'BufferOverrun';
  }
  if (isSerialFramingError(error)) {
    return 'FramingError';
  }
  if (isSerialParityError(error)) {
    return 'ParityError';
  }
  if (isSerialBreakError(error)) {
    return 'Break';
  }
  return error.runtimeType.toString();
}

bool isSerialRecoverableLineError(Object error) =>
    isSerialFramingError(error) ||
    isSerialParityError(error) ||
    isSerialBufferOverrunError(error);

/// [SerialPort.close] on a port that was never opened or is already closed.
bool isSerialPortAlreadyClosedError(Object error) {
  final message = error.toString();
  return message.contains('already closed') ||
      (message.contains('InvalidStateError') &&
          message.contains("'close'") &&
          message.contains('SerialPort'));
}

/// Port missing, powered off, or Web Serial stream not usable — do not keep probing.
bool isSerialPortUnavailableError(Object error) {
  final message = error.toString();
  return message.contains('NetworkError') ||
      message.contains('device has been lost') ||
      message.contains('device was disconnected') ||
      message.contains('Failed to execute \'getReader\'') ||
      message.contains('locked stream') ||
      message.contains('Cannot cancel a locked stream');
}

/// Thrown to stop baud scan immediately and reset to initial state.
final class SerialConnectAborted implements Exception {
  SerialConnectAborted([this.cause]);
  final Object? cause;

  @override
  String toString() => cause == null
      ? 'SerialConnectAborted'
      : 'SerialConnectAborted: $cause';
}
