import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;

/// Web loaded-file speaker output via [AudioContext] (not SoLoud buffer streams).
class WebLoadedFilePlayer {
  WebLoadedFilePlayer._();

  static final WebLoadedFilePlayer instance = WebLoadedFilePlayer._();

  VoidCallback? onPlaybackEnded;

  /// Invalidates in-flight ended callbacks when stop/play races (issue #75).
  int _endedSession = 0;

  bool get isActive {
    if (!kIsWeb) return false;
    try {
      return js.context.callMethod('loadedFilePlaybackIsActive') == true;
    } catch (_) {
      return false;
    }
  }

  int currentSamplePosition() {
    if (!kIsWeb) return 0;
    try {
      final v = js.context.callMethod('loadedFilePlaybackGetSamplePosition');
      if (v is num) return v.round();
    } catch (e) {
      debugPrint('WebLoadedFilePlayer.currentSamplePosition: $e');
    }
    return 0;
  }

  void registerEndedCallback(VoidCallback? callback) {
    if (!kIsWeb) return;
    onPlaybackEnded = callback;
    if (callback == null) {
      js.context['dartLoadedFilePlaybackEnded'] = null;
      return;
    }
    final session = ++_endedSession;
    js.context['dartLoadedFilePlaybackEnded'] = js.allowInterop(() {
      // Capture session so a stop()/replay cannot run a stale ended handler.
      final endedSession = session;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (endedSession != _endedSession) return;
        onPlaybackEnded?.call();
      });
    });
  }

  void stop() {
    if (!kIsWeb) return;
    // Invalidate before JS stop so any residual ended notification is dropped.
    _endedSession++;
    onPlaybackEnded = null;
    js.context['dartLoadedFilePlaybackEnded'] = null;
    try {
      js.context.callMethod('loadedFilePlaybackStop');
    } catch (e) {
      debugPrint('WebLoadedFilePlayer.stop: $e');
    }
  }

  /// Plays [samples] from [startSampleIndex] using the browser audio clock.
  bool play({
    required Int16List samples,
    required int sampleRate,
    int startSampleIndex = 0,
  }) {
    if (!kIsWeb || samples.isEmpty || sampleRate < 1) return false;

    final bytes = samples.buffer.asUint8List(
      samples.offsetInBytes,
      samples.lengthInBytes,
    );

    try {
      final ok = js.context.callMethod('loadedFilePlaybackPlay', [
        bytes,
        sampleRate,
        startSampleIndex,
      ]);
      return ok == true;
    } catch (e, st) {
      debugPrint('WebLoadedFilePlayer.play failed: $e\n$st');
      return false;
    }
  }

  /// Channel index used for speaker output during file playback.
  static int speakerChannelIndex({
    required int channelCount,
    required bool isMicrophoneRecording,
    required List<bool> speakerChannelMuted,
  }) {
    if (channelCount < 1) return 0;
    if (isMicrophoneRecording) return 0;

    for (var i = channelCount - 1; i >= 0; i--) {
      if (i < speakerChannelMuted.length && !speakerChannelMuted[i]) {
        return i;
      }
    }
    return channelCount - 1;
  }

  /// Pause live SoLoud monitor; file play on web does not use [soloud.SoLoud] streams.
}
