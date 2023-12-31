import 'dart:async';
import 'dart:typed_data';

import 'package:spikerbox_architecture/models/microphone_stream/microphone_stream.dart'
    if (dart.library.io) 'package:spikerbox_architecture/models/microphone_stream/microphone_stream_native.dart'
    if (dart.library.html) 'package:spikerbox_architecture/models/microphone_stream/microphone_stream_web.dart';

abstract class MicrophoneUtil {
  factory MicrophoneUtil() => getMicrophoneStreams();

  final StreamController<Uint8List> addListenAudioStreamController =
      StreamController();
  Stream<Uint8List>? micStream;

  Future<void> init() async {}

  Future<void> checkPointerValue() async {}
}
