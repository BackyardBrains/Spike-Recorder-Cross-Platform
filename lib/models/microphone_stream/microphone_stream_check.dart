import 'dart:async';

import 'package:native_add/model/sending_data.dart';
import 'package:spikerbox_architecture/models/microphone_stream/microphone_stream.dart'
    if (dart.library.io) 'package:spikerbox_architecture/models/microphone_stream/microphone_stream_native.dart'
    if (dart.library.html) 'package:spikerbox_architecture/models/microphone_stream/microphone_stream_web.dart';

abstract class MicrophoneUtil {
  factory MicrophoneUtil() => getMicrophoneStreams();

  final StreamController<SendingDataToDart> addListenAudioStreamController =
      StreamController();
  Stream<SendingDataToDart>? micStream;

  Future<void> init() async {}

  Future<void> checkPointerValue() async {}
}
