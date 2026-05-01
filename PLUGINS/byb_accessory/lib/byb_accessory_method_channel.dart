import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'byb_accessory_platform_interface.dart';

/// An implementation of [BybAccessoryPlatform] that uses method channels.
class MethodChannelBybAccessory extends BybAccessoryPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('byb_accessory');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>('getPlatformVersion');
    return version;
  }
}
