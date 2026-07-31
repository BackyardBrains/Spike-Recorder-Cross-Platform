import 'dart:typed_data';

import 'package:flutter/foundation.dart';
/// Non-web stub for [WebLoadedFilePlayer].
class WebLoadedFilePlayer {
  WebLoadedFilePlayer._();

  static final WebLoadedFilePlayer instance = WebLoadedFilePlayer._();

  VoidCallback? onPlaybackEnded;

  bool get isActive => false;

  int currentSamplePosition() => 0;

  void registerEndedCallback(VoidCallback? callback) {
    onPlaybackEnded = callback;
  }

  void stop() {}

  bool play({
    required Int16List samples,
    required int sampleRate,
    int startSampleIndex = 0,
  }) =>
      false;

  static int speakerChannelIndex({
    required int channelCount,
    required bool isMicrophoneRecording,
    required List<bool> speakerChannelMuted,
  }) =>
      channelCount > 0 ? channelCount - 1 : 0;

}
