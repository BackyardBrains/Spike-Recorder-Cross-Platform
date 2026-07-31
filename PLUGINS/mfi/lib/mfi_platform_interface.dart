import 'package:flutter/services.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'mfi_method_channel.dart';

abstract class MfiPlatform extends PlatformInterface {
  static const MethodChannel _channel = MethodChannel('mfi');
  static late EventChannel spikeStatusChannel;
  static late EventChannel deviceStatusChannel;
  static late Stream<Uint8List> _spikeStatusStream;
  static late Stream<String> _deviceStatusStream;



  /// Constructs a MfiPlatform.
  MfiPlatform() : super(token: _token);

  static final Object _token = Object();

  static MfiPlatform _instance = MethodChannelMfi();

  /// The default instance of [MfiPlatform] to use.
  ///
  /// Defaults to [MethodChannelMfi].
  static MfiPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [MfiPlatform] when
  /// they register themselves.
  static set instance(MfiPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }

  void initMfi() async {
    deviceStatusChannel = EventChannel('devicestatus/event');
    spikeStatusChannel = EventChannel('spikestatus/event');
    await _channel.invokeMethod('initMfi', {"status": "init"});
  }

  Future<String> getSpikeStatus() async {
    await _channel.invokeMethod('getSpikeStatus');
    return "";
  }

  Future<String> setDeviceStatus(String s) async {
    await _channel.invokeMethod('setDeviceStatus', {"status": s});
    return "";
  }

  Future<String> setSpikeStatus(String s) async {
    await _channel.invokeMethod('setSpikeStatus', {"status": s});
    return "";
  }

  Stream<Uint8List> getSpikeStatusStream() {
    _spikeStatusStream =
        spikeStatusChannel.receiveBroadcastStream().cast<Uint8List>();
    // .map<Uint8List>((value) => value);
    return _spikeStatusStream;
  }

  Stream<String> getDeviceStatusStream() {
    _deviceStatusStream = deviceStatusChannel
        .receiveBroadcastStream()
        .map<String>((value) => value);
    return _deviceStatusStream;
  }
}
