import 'package:flutter/services.dart';
import 'dart:typed_data';

class BybAccessory {
  static const MethodChannel _channel = MethodChannel('byb_accessory');
  static const EventChannel _rxChannel = EventChannel('byb_accessory/rx');

  Future<String?> getPlatformVersion() async {
    return _channel.invokeMethod<String>('getPlatformVersion');
  }

  static Future<void> initWithProtocol(String protocol) async {
    await _channel.invokeMethod('initWithProtocol', {'protocol': protocol});
  }

  /// Emits native EA diagnostics (connectedAccessories, protocols, session state).
  static Future<void> logAccessoryDiagnostics() async {
    await _channel.invokeMethod<void>('logAccessoryDiagnostics');
  }

  static Future<void> setProtocol(String protocol) async {
    await _channel.invokeMethod('setProtocol', {'protocol': protocol});
  }

  static Future<List<String>> getConnectedAccessories() async {
    final List<dynamic> accessories = await _channel.invokeMethod('getConnectedAccessories');
    return accessories.cast<String>();
  }

  static Future<bool> connect({String? name}) async {
    final bool? connected = await _channel.invokeMethod(
      'connect',
      name == null ? <String, dynamic>{} : {'name': name},
    );
    return connected ?? false;
  }

  static Future<void> disconnect() async {
    await _channel.invokeMethod('disconnect');
  }

  static Future<bool> isConnected() async {
    final bool? connected = await _channel.invokeMethod('isConnected');
    return connected ?? false;
  }

  static Future<String> getAccessoryInfo() async {
    final String? info = await _channel.invokeMethod('getAccessoryInfo');
    return info ?? 'Accessory Not Connected';
  }

  /// Sends raw bytes to the iOS ExternalAccessory output stream.
  static Future<void> sendBytes(Uint8List bytes) async {
    await _channel.invokeMethod('sendBytes', {'bytes': bytes});
  }

  /// Stream of raw bytes received from iOS ExternalAccessory input stream.
  static Stream<Uint8List> get rxBytesStream {
    return _rxChannel.receiveBroadcastStream().map((dynamic event) {
      if (event is Uint8List) {
        return event;
      }
      if (event is ByteData) {
        return event.buffer.asUint8List();
      }
      if (event is List<int>) {
        return Uint8List.fromList(event);
      }
      throw StateError('Unexpected rx event type: ${event.runtimeType}');
    });
  }
}