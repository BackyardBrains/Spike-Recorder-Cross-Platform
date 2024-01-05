import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:sound_stream_now/sound_stream_now.dart';
import 'package:permission_handler/permission_handler.dart';

import 'package:native_add/model/sending_data.dart';
import 'package:spikerbox_architecture/models/debugging.dart';
import 'microphone_stream_check.dart';

class MicrophoneUtilAndroid implements MicrophoneUtil {
  // late ffi.Pointer<ffi.Pointer<ffi.Float>> audioData;
  @override
  StreamController<SendingDataToDart> addListenAudioStreamController =
      StreamController();

  @override
  Stream<SendingDataToDart>? micStream;

  List<double>? waveSamples;
  List<double>? intensitySamples;
  Stream<Uint8List>? stream;
  int _counter = 0;
  Stopwatch stopwatch = Stopwatch();
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
    stopwatch.start();
    _recorder.audioStream.listen((data) {
      _counter++;
      Debugging.printing(
          "the time taken ${stopwatch.elapsedMilliseconds} and packet size ${data.length}");
      stopwatch.reset();
      SendingDataToDart sendingDataToDart = SendingDataToDart(
          int16list: Int16List.fromList(data),
          elapseTime: 0,
          maxTime: 0,
          minTime: 0);
      addListenAudioStreamController.add(sendingDataToDart);
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
