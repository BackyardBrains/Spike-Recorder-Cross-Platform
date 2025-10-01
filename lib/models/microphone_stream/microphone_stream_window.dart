import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:mic_stream/mic_stream.dart';
import 'package:spikerbox_architecture/screen/graph_template.dart';
// import 'package:record/record.dart';

import 'microphone_stream_check.dart';
// ignore: library_prefixes
import 'package:native_add/mic_listening_isolate.dart' as native_MicListen;

class MicrophoneUtilWindow implements MicrophoneUtil {
  @override
  // Stream<Uint8List>? micStream;
  ValueNotifier<Uint8List> micStream = ValueNotifier(Uint8List(0));

  @override
  // StreamController<Uint8List> addListenAudioStreamController =  StreamController();
  ValueNotifier<Uint8List> addListenAudioStreamController = ValueNotifier(Uint8List(0));

  // List<int> intList = List<int>.generate(2000, (index) => index);
  Int16List? data;

  @override
  double sampleRate = 44100;

  @override
  Future<void> init() async {
    MicStream.shouldRequestPermission(true);
    var microphoneStream = (await MicStream.microphone(
            audioSource: AudioSource.DEFAULT,
            sampleRate: 44100,
            channelConfig: ChannelConfig.CHANNEL_IN_MONO,
            audioFormat: AudioFormat.ENCODING_PCM_16BIT));
    micStream = addListenAudioStreamController;
    microphoneStream?.listen((onData) {
      if (GraphTemplate.isLoadingFile < 3) {
        micStream?.value = onData;
      }
    });


    double? tempSampleRate = await MicStream.sampleRate;
    if (tempSampleRate != null) {
      sampleRate = tempSampleRate;
    }
    // double? sampleRate = await MicStream.sampleRate;
    // print("MICSTREAM $sampleRate");
    // micStream = addListenAudioStreamController.stream.asBroadcastStream();
    // await native_add.setTheMicData();

    // await native_add.listenMic(_bufferData);

    // final record = AudioRecorder();
    // if (await record.hasPermission()) {
    //   micStream = await record.startStream(const RecordConfig(numChannels: 1, sampleRate: 44100, encoder: AudioEncoder.pcm16bits));
    // }
    // await native_MicListen.mainIsolateForMic(addListenAudioStreamController);
    // await native_MicListen.listenMicOfAudio();
  }

  @override
  Future<void> checkPointerValue() async {
    // Int16List _bufferData = Int16List.fromList(intList);
    // final valueis = await native_add.setTheMicData(_bufferData);
    // print("the value is getted $valueis");
  }
}
