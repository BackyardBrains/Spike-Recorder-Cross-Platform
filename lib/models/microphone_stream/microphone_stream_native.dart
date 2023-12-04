import 'dart:io';

import 'package:spikerbox_architecture/models/microphone_stream/microphone_stream_android.dart';

import 'microphone_stream_check.dart';
import 'package:spikerbox_architecture/models/microphone_stream/microphone_stream_window.dart';

MicrophoneUtil getMicrophoneStreams() {
  if (Platform.isAndroid || Platform.isIOS) {
    return MicrophoneUtilAndroid();
  } else if (Platform.isMacOS || Platform.isWindows) {
    return MicrophoneUtilWindow();
  }
  return MicrophoneUtilWindow();
}
