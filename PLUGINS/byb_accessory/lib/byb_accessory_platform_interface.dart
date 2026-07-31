import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'byb_accessory_method_channel.dart';

abstract class BybAccessoryPlatform extends PlatformInterface {
  /// Constructs a BybAccessoryPlatform.
  BybAccessoryPlatform() : super(token: _token);

  static final Object _token = Object();

  static BybAccessoryPlatform _instance = MethodChannelBybAccessory();

  /// The default instance of [BybAccessoryPlatform] to use.
  ///
  /// Defaults to [MethodChannelBybAccessory].
  static BybAccessoryPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [BybAccessoryPlatform] when
  /// they register themselves.
  static set instance(BybAccessoryPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
