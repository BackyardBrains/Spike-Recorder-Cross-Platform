import 'dart:async';
import 'dart:typed_data';
import 'microphone_stream_check.dart';
import 'dart:js' as js;

import 'package:native_add/model/model.dart';

MicrophoneUtil getMicrophoneStreams() => MicrophoneUtilWeb();

class MicrophoneUtilWeb implements MicrophoneUtil {
  Int16List? _micDataBuffer;
  int sampleRateFromWeb = 0;

  @override
  StreamController<Uint8List> addListenAudioStreamController =
      StreamController();

  @override
  Stream<PacketAddDetailModel>? packetAddDetail;

  @override
  StreamController<PacketAddDetailModel> addPacketDetailCalculate =
      StreamController();

  @override
  Stream<Uint8List>? micStream;

  @override
  Future<void> init() async {
    packetAddDetail = addPacketDetailCalculate.stream.asBroadcastStream();
    micStream = addListenAudioStreamController.stream.asBroadcastStream();
    js.context['onDataBufferAllocated'] = onDataBufferAllocated;
    js.context['onDataReceived'] = onDataReceived;
    js.context['getSampleRate'] = getSampleRate;
    Future.delayed(const Duration(seconds: 1), () {
      js.context.callMethod('startListeningToMicrophone', []);
    });
  }

  @override
  void resetTheClass() {
    // native_MicListen.resetClassInstance();
  }

  void getSampleRate(int sampleRate) {
    sampleRateFromWeb = sampleRate;
    print("the sample rate from the web $sampleRate");
  }

  /// Called only once in the beginning to send address of buffer to dart
  void onDataBufferAllocated(Int16List dataBuffer) {
    _micDataBuffer = dataBuffer;
  }

  void onDataReceived() {
    if (_micDataBuffer == null) {
      return;
    }

    // Convert Int16List to Uint8List

    // Add Uint8List to the stream
    Uint8List uList = Uint8List.fromList(_micDataBuffer!.buffer.asUint8List());
    addListenAudioStreamController.add(uList);
  }

  @override
  Future<void> checkPointerValue() async {}
}
