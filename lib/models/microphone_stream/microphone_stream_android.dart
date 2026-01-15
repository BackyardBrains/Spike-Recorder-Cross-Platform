import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:mic_stream/mic_stream.dart';
import 'package:sound_stream_now/sound_stream_now.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:spikerbox_architecture/screen/graph_template.dart';

import 'microphone_stream_check.dart';

class MicrophoneUtilAndroid implements MicrophoneUtil {
  // late ffi.Pointer<ffi.Pointer<ffi.Float>> audioData;
  @override
  // StreamController<Uint8List> addListenAudioStreamController =
  //     StreamController();
  ValueNotifier<Uint8List> addListenAudioStreamController = ValueNotifier(Uint8List(0));

  @override
  double sampleRate = 44100;

  @override
  ValueNotifier<Uint8List> micStream = ValueNotifier(Uint8List(0));

  List<double>? waveSamples;
  List<double>? intensitySamples;
  Stream<Uint8List>? stream;
  late StreamSubscription<Uint8List>? listen;

  late final RecorderStream _recorder;
  // PlayerStream _player = PlayerStream();
  @override
  StreamSubscription? micStatus;

  @override
  Future<void> init() async {
    await requestMicrophonePermission();
    
    // _recorder = RecorderStream();

    // _recorderStatus = _recorder.status.listen((status) {
    //   status == SoundStreamStatus.Playing;
    // });

    // micStream = addListenAudioStreamController.stream.asBroadcastStream();
    micStatus?.cancel();
    var microphoneStream = (await MicStream.microphone(
            audioSource: AudioSource.DEFAULT,
            sampleRate: 44100,
            channelConfig: ChannelConfig.CHANNEL_IN_MONO,
            audioFormat: AudioFormat.ENCODING_PCM_16BIT));
    try{
      micStream = addListenAudioStreamController;
      micStatus = microphoneStream?.listen((onData) {
        if (GraphTemplate.isLoadingFile < 3) {
          micStream?.value = onData;
        }
      });
    }catch(err) {

    }

    // _recorder.audioStream.listen((data) {
    //   // addListenAudioStreamController.add(data);
    //   addListenAudioStreamController.value = (data);
    // });

    // await Future.wait([
    //   _recorder.initialize(showLogs: true),
    //   // _player.initialize(),
    // ]);
    // _recorder.audioStream.asBroadcastStream();

    // await _recorder.start();
  }

  Future<void> requestMicrophonePermission() async {
    if (!Platform.isAndroid && !Platform.isIOS) return;
    PermissionStatus status = await Permission.microphone.request();

    if (status.isGranted) {
      // Microphone permission granted
    } else if (status.isDenied) {
      // Microphone permission denied
    } else if (status.isPermanentlyDenied) {
      // The user opted to never again see the permission request dialog for this
      // app. The only way to change the permission's status now is to let the
      // user manually enable it in the system settings.
      openAppSettings();
    }
  }

  Future<void> checkPointerValue() async {}
}
