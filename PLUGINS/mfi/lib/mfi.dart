import 'dart:typed_data';
import 'mfi_platform_interface.dart';

class Mfi {
  Future<String?> getPlatformVersion() {
    return MfiPlatform.instance.getPlatformVersion();
  }
  void initMfi() async {
    MfiPlatform.instance.initMfi();
  }
  Future<String> getSpikeStatus() async {
    return await MfiPlatform.instance.getSpikeStatus();
  }
  Future<String> setDeviceStatus(String s) async {
    return await MfiPlatform.instance.setDeviceStatus(s);
  }
  Future<String> setSpikeStatus(String s) async {
    return await MfiPlatform.instance.setSpikeStatus(s);
  }
  Stream<Uint8List> getSpikeStatusStream() {
    return MfiPlatform.instance.getSpikeStatusStream();
  }
  Stream<String> getDeviceStatusStream() {
    return MfiPlatform.instance.getDeviceStatusStream();
  }
}
