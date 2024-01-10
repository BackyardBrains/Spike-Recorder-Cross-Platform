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
  StreamController<Uint8List> addListenAudioStreamController =
      StreamController();

  @override
  Stream<Uint8List>? micStream;

  @override
  Stream<PacketAddDetailModel>? packetAddDetail;

  @override
  StreamController<PacketAddDetailModel> addPacketDetailCalculate =
      StreamController();

  List<double>? waveSamples;
  List<double>? intensitySamples;
  Stream<Uint8List>? stream;
  int _counter = 0;
  int totalTimeAudio = 0;
  int maxTimeAudio = 0;
  int minTimeAudio = int.parse('9223372036854775807');
  int avgTimeAudio = 0;
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
    packetAddDetail = addPacketDetailCalculate.stream.asBroadcastStream();

    micStream = addListenAudioStreamController.stream.asBroadcastStream();
    stopwatch.start();
    _recorder.audioStream.listen((data) {
      Debugging.printing(
          "the time taken ${stopwatch.elapsedMilliseconds} and packet size ${data.length}");

      int elapsedTime = stopwatch.elapsedMilliseconds;
      addElapsedTime(elapsedTime);
      stopwatch.reset();
      PacketAddDetailModel packetAddDetailModel = PacketAddDetailModel(
          averageTime: avgTimeAudio,
          maxTime: maxTimeAudio,
          minTime: minTimeAudio);
      addPacketDetailCalculate.add(packetAddDetailModel);

      addListenAudioStreamController.add(data);
    });

    await Future.wait([
      _recorder.initialize(showLogs: true, sampleRate: 44100),
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

  void setMaxTime(int latestTime) {
    if (maxTimeAudio < latestTime) {
      maxTimeAudio = latestTime;
    }
  }

  int setMinTime(int latestTime) {
    if (latestTime < minTimeAudio) {
      minTimeAudio = latestTime;
    }
    return minTimeAudio;
  }

  void averageCalculateTime(int latestTime) {
    _counter++;
    totalTimeAudio += latestTime;
    avgTimeAudio = (totalTimeAudio ~/ _counter);
  }

  void addElapsedTime(int latestTime) {
    setMaxTime(latestTime);
    setMinTime(latestTime);
    averageCalculateTime(latestTime);
  }

  Future<void> checkPointerValue() async {}
}
