import 'dart:async';
import 'dart:typed_data';
import 'package:native_add/model/model.dart';

import 'microphone_stream_check.dart';
// ignore: library_prefixes

import 'package:native_add/mic_listening_isolate.dart' as native_MicListen;

class MicrophoneUtilWindow implements MicrophoneUtil {
  @override
  Stream<Uint8List>? micStream;

  @override
  Stream<PacketAddDetailModel>? packetAddDetail;

  @override
  StreamController<PacketAddDetailModel> addPacketDetailCalculate =
      StreamController();

  @override
  StreamController<Uint8List> addListenAudioStreamController =
      StreamController();

  // List<int> intList = List<int>.generate(2000, (index) => index);
  Int16List? data;

  @override
  Future<void> init() async {
    packetAddDetail = addPacketDetailCalculate.stream.asBroadcastStream();
    micStream = addListenAudioStreamController.stream.asBroadcastStream();
    // await native_add.setTheMicData();
    // await native_add.listenMic(_bufferData);
    await native_MicListen.mainIsolateForMic(
        addListenAudioStreamController, addPacketDetailCalculate);
    await native_MicListen.listenMicOfAudio();
  }

  @override
  Future<void> checkPointerValue() async {
    // Int16List _bufferData = Int16List.fromList(intList);
    // final valueis = await native_add.setTheMicData(_bufferData);
    // print("the value is getted $valueis");
  }
}
