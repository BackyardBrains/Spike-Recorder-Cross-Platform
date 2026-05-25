import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_soloud/flutter_soloud.dart' as soloud;

/// Low-latency monitor: streams PCM through [flutter_soloud].
///
/// On native, pass chunks from [ProcessingUtil.processMicrophoneData] /
/// [ProcessingUtil.processSerialData]. On web, chunks arrive via
/// [ProcessingUtil.webLivePlaybackListener] from the WASM worker.
class ProcessedSamplePlayer {
  ProcessedSamplePlayer({
    this.enabled = false,
    this.lowLatencyBufferSeconds = 0.01,
  });

  /// When false, enqueue methods are no-ops.
  bool enabled;

  /// SoLoud waits for this much audio before un-pausing the stream handle.
  final double lowLatencyBufferSeconds;

  static const int _engineBufferSize = 256;

  int _sampleRate = 44100;
  int _channelCount = 1;
  bool _initialized = false;
  bool _playing = false;

  final soloud.SoLoud _engine = soloud.SoLoud.instance;
  final List<soloud.AudioSource?> _streams = [];
  final List<soloud.SoundHandle?> _handles = [];
  final List<bool> _channelMuted = List.filled(8, false);

  bool get isActive => _initialized && _playing;

  Future<void> init({
    required int sampleRate,
    required int channelCount,
  }) async {
    if (channelCount < 1) {
      throw ArgumentError.value(channelCount, 'channelCount', 'must be >= 1');
    }

    await stop();

    _sampleRate = sampleRate;
    _channelCount = channelCount;
    _channelMuted.fillRange(0, _channelMuted.length, false);

    if (!_engine.isInitialized) {
      await _engine.init(
        bufferSize: _engineBufferSize,
        sampleRate: _sampleRate,
        channels: soloud.Channels.mono,
      );
    }

    _streams.clear();
    for (var i = 0; i < _channelCount; i++) {
      _streams.add(_createBufferStream());
    }

    _initialized = true;
    _playing = false;
  }

  soloud.AudioSource _createBufferStream() {
    final bufferSeconds = lowLatencyBufferSeconds.clamp(0.005, 0.5);

    if (kIsWeb) {
      return _engine.setBufferStream(
        maxBufferSizeBytes:
            (_sampleRate * 2 * 2).clamp(4096, _sampleRate * 2 * 4).toInt(),
        bufferingTimeNeeds: bufferSeconds,
        bufferingType: soloud.BufferingType.released,
        sampleRate: _sampleRate,
        channels: soloud.Channels.mono,
        format: soloud.BufferType.s16le,
      );
    }

    return _engine.setBufferStream(
      bufferingType: soloud.BufferingType.released,
      bufferingTimeNeeds: bufferSeconds,
      sampleRate: _sampleRate,
      channels: soloud.Channels.mono,
      format: soloud.BufferType.s16le,
    );
  }

  Future<void> start() async {
    if (!_initialized) {
      throw StateError('ProcessedSamplePlayer.init() must be called first');
    }
    if (_playing) return;

    _handles.clear();
    for (var i = 0; i < _channelCount; i++) {
      final stream = _streams[i];
      if (stream == null) continue;
      final handle = await _engine.play(stream);
      _handles.add(handle);
    }
    _playing = _handles.isNotEmpty;
  }

  void setChannelMuted(int channelIndex, bool muted) {
    if (channelIndex < 0 || channelIndex >= _channelMuted.length) return;
    _channelMuted[channelIndex] = muted;
  }

  void enqueueProcessedChunk(List<Int16List> processedChannels) {
    if (!enabled || !_initialized || !_playing) return;

    final channelsToPlay = processedChannels.length < _channelCount
        ? processedChannels.length
        : _channelCount;

    for (var ch = 0; ch < channelsToPlay; ch++) {
      final stream = _streams[ch];
      final channelData = processedChannels[ch];
      if (stream == null || channelData.isEmpty) continue;

      final Uint8List bytes;
      if (_channelMuted[ch]) {
        bytes = Uint8List(channelData.lengthInBytes);
      } else {
        bytes = channelData.buffer.asUint8List(
          channelData.offsetInBytes,
          channelData.lengthInBytes,
        );
      }

      try {
        _engine.addAudioDataStream(stream, bytes);
      } catch (e) {
        debugPrint('ProcessedSamplePlayer: enqueue failed: $e');
      }
    }
  }

  void enqueueRawPcm(Uint8List pcmBytes, {int channelIndex = 0}) {
    if (!enabled || !_initialized || !_playing || pcmBytes.isEmpty) return;
    if (channelIndex < 0 || channelIndex >= _streams.length) return;

    final stream = _streams[channelIndex];
    if (stream == null) return;

    final bytes = _channelMuted[channelIndex]
        ? Uint8List(pcmBytes.length)
        : pcmBytes;

    try {
      _engine.addAudioDataStream(stream, bytes);
    } catch (e) {
      debugPrint('ProcessedSamplePlayer: enqueueRawPcm failed: $e');
    }
  }

  Future<void> stop() async {
    for (var i = 0; i < _handles.length; i++) {
      final handle = _handles[i];
      final stream = i < _streams.length ? _streams[i] : null;
      try {
        if (stream != null) {
          _engine.setDataIsEnded(stream);
        }
        if (handle != null) {
          _engine.stop(handle);
        }
      } catch (e) {
        debugPrint('ProcessedSamplePlayer: stop failed: $e');
      }
    }

    _handles.clear();
    _streams.clear();
    _playing = false;
    _initialized = false;
  }

  Future<void> dispose() => stop();
}
