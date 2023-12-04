import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:sound_stream_now/sound_stream_now.dart';
import 'package:permission_handler/permission_handler.dart';

import 'microphone_stream_check.dart';

class MicrophoneUtilAndroid implements MicrophoneUtil {
  // late ffi.Pointer<ffi.Pointer<ffi.Float>> audioData;
  @override
  StreamController<Uint8List> addListenAudioStreamController =
      StreamController();

  @override
  Stream<Uint8List>? micStream;

  List<double>? waveSamples;
  List<double>? intensitySamples;
  Stream<Uint8List>? stream;
  late StreamSubscription<Uint8List>? listen;

  final RecorderStream _recorder = RecorderStream();
  // PlayerStream _player = PlayerStream();
  late StreamSubscription _recorderStatus;

  @override
  Future<void> init() async {
    await requestMicrophonePermission();

    // _recorderStatus = _recorder.status.listen((status) {
    //   status == SoundStreamStatus.Playing;
    // });

    micStream = addListenAudioStreamController.stream.asBroadcastStream();

    _recorder.audioStream.listen((data) {
      addListenAudioStreamController.add(data);
    });

    await Future.wait([
      _recorder.initialize(showLogs: true),
      // _player.initialize(),
    ]);
    _recorder.audioStream.asBroadcastStream();

    await _recorder.start();
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
