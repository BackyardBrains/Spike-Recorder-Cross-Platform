import 'package:flutter_test/flutter_test.dart';
import 'package:byb_accessory/byb_accessory.dart';
import 'package:byb_accessory/byb_accessory_platform_interface.dart';
import 'package:byb_accessory/byb_accessory_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockBybAccessoryPlatform
    with MockPlatformInterfaceMixin
    implements BybAccessoryPlatform {

  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final BybAccessoryPlatform initialPlatform = BybAccessoryPlatform.instance;

  test('$MethodChannelBybAccessory is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelBybAccessory>());
  });

  test('getPlatformVersion', () async {
    BybAccessory bybAccessoryPlugin = BybAccessory();
    MockBybAccessoryPlatform fakePlatform = MockBybAccessoryPlatform();
    BybAccessoryPlatform.instance = fakePlatform;

    expect(await bybAccessoryPlugin.getPlatformVersion(), '42');
  });
}
