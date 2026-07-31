import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:mic_stream/mic_stream.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:spikerbox_architecture/screen/graph_template.dart';

import 'microphone_stream_check.dart';

class MicrophoneUtilAndroid implements MicrophoneUtil {
  @override
  ValueNotifier<Uint8List> addListenAudioStreamController =
      ValueNotifier(Uint8List(0));

  @override
  double sampleRate = 44100;

  @override
  ValueNotifier<Uint8List> micStream = ValueNotifier(Uint8List(0));

  @override
  StreamSubscription? micStatus;

  @override
  Future<void> stopListeningToMicrophone({bool resetStream = false}) async {
    await micStatus?.cancel();
    micStatus = null;
    micStream.value = Uint8List(0);
    addListenAudioStreamController.value = Uint8List(0);
    if (resetStream) {
      MicStream.resetCachedStream();
    }
  }

  @override
  Future<void> init({bool forceRestart = false}) async {
    await requestMicrophonePermission();

    if (forceRestart) {
      await stopListeningToMicrophone(resetStream: true);
    } else {
      await micStatus?.cancel();
      micStatus = null;
    }

    final microphoneStream = await MicStream.microphone(
      audioSource: AudioSource.DEFAULT,
      sampleRate: 44100,
      channelConfig: ChannelConfig.CHANNEL_IN_MONO,
      audioFormat: AudioFormat.ENCODING_PCM_16BIT,
    );
    try {
      micStream = addListenAudioStreamController;
      micStatus = microphoneStream?.listen((onData) {
        if (GraphTemplate.isLoadingFile < 3) {
          micStream.value = onData;
        }
      });
    } catch (err) {
      print('microphone init listen failed: $err');
    }
  }

  Future<void> requestMicrophonePermission() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    PermissionStatus status = await Permission.microphone.request();

    if (status.isGranted) {
      // Microphone permission granted
    } else if (status.isDenied) {
      // Microphone permission denied
    } else if (status.isPermanentlyDenied) {
      openAppSettings();
    }
  }

  @override
  Future<void> checkPointerValue() async {}
}
