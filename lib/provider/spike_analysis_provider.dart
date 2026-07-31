import 'dart:async';
import 'dart:math' show max, min;
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// One user-adjustable threshold "window" within a channel's Spike Analysis
/// raster: spikes from [ProcessingUtil.findSampleSpike] whose peak amplitude
/// falls between [lowValue] and [highValue] are counted/drawn (desktop
/// SpikeSorter window filter).
class SpikeThreshold {
  SpikeThreshold({
    required this.id,
    required this.highValue,
    required this.lowValue,
    required this.color,
  });

  final String id;
  double highValue;
  double lowValue;
  final Color color;
}

/// A Schmitt-trigger peak from [ProcessingUtil.findSampleSpike].
class SpikePeak {
  const SpikePeak({required this.index, required this.value});
  final int index;
  final int value;
}

/// Controls the Spike Analysis overlay: which channel is currently active and
/// the set of threshold windows defined per channel. Every channel keeps its
/// own independent list of thresholds so switching channels preserves work
/// already done on the others.
class SpikeAnalysisProvider extends ChangeNotifier {
  bool _isEnabled = false;
  bool get isEnabled => _isEnabled;

  int _channelIndex = 0;
  int get channelIndex => _channelIndex;

  int _channelCount = 1;
  int get channelCount => _channelCount;

  static const List<Color> palette = [
    Color(0xFFB388FF),
    Color(0xFFFF8A65),
    Color(0xFF4FC3F7),
    Color(0xFF81C784),
    Color(0xFFFFF176),
    Color(0xFFF06292),
  ];

  final Map<int, List<SpikeThreshold>> _thresholdsByChannel = {};
  int _nextId = 0;

  /// Injected by the host screen (which owns the NWB file handle) so this
  /// provider can lazily pull a channel's full waveform straight from the
  /// currently opened file instead of the live rolling display buffer.
  /// Called with `this` and the requested channel; the loader is expected to
  /// eventually call [setChannelData] for that channel.
  Future<void> Function(SpikeAnalysisProvider provider, int channel)?
      channelDataLoader;

  final Map<int, Int16List> _channelSamples = {};
  final Map<int, List<SpikePeak>> _channelPeaks = {};
  int _sampleRateHz = 10000;
  int get sampleRateHz => _sampleRateHz;

  bool _isLoadingChannelData = false;
  bool get isLoadingChannelData => _isLoadingChannelData;

  /// Full-resolution samples for [channel] as read from the NWB file, or
  /// null if they haven't been loaded (yet).
  Int16List? samplesFor(int channel) => _channelSamples[channel];

  /// Peaks from [ProcessingUtil.findSampleSpike] for [channel], or empty.
  List<SpikePeak> peaksFor(int channel) =>
      List.unmodifiable(_channelPeaks[channel] ?? const []);

  bool hasDataFor(int channel) => _channelSamples.containsKey(channel);

  /// Called by [channelDataLoader] once it has read the samples for
  /// [channel] from the NWB file.
  void setChannelData(
    int channel,
    Int16List samples,
    int sampleRateHz, {
    List<SpikePeak> peaks = const [],
  }) {
    _channelSamples[channel] = samples;
    _channelPeaks[channel] = List<SpikePeak>.from(peaks);
    if (sampleRateHz > 0) _sampleRateHz = sampleRateHz;
    _isLoadingChannelData = false;
    notifyListeners();
  }

  Future<void> _ensureChannelData(int channel) async {
    if (_channelSamples.containsKey(channel)) return;
    final loader = channelDataLoader;
    if (loader == null) return;
    _isLoadingChannelData = true;
    notifyListeners();
    try {
      await loader(this, channel);
    } finally {
      if (!_channelSamples.containsKey(channel)) {
        // Loader failed (or the file no longer has this channel) - stop
        // showing a spinner forever.
        _isLoadingChannelData = false;
        notifyListeners();
      }
    }
  }

  /// Read-only view of the thresholds defined for [channel] (empty if none).
  List<SpikeThreshold> thresholdsFor(int channel) =>
      List.unmodifiable(_thresholdsByChannel[channel] ?? const []);

  /// Opens the overlay on [channel] (defaults to the first channel when
  /// negative) and, if that channel has no threshold yet, creates one so
  /// there is always something to look at right away. Always re-fetches the
  /// channel data from the file so switching between files/sessions can
  /// never show stale samples from a previously opened file.
  void openFor(int channel, {int channelCount = 1}) {
    _channelCount = channelCount < 1 ? 1 : channelCount;
    _channelIndex = channel < 0 ? 0 : channel;
    _isEnabled = true;
    _channelSamples.clear();
    _channelPeaks.clear();
    if ((_thresholdsByChannel[_channelIndex] ?? const []).isEmpty) {
      _addThreshold(_channelIndex);
    }
    notifyListeners();
    unawaited(_ensureChannelData(_channelIndex));
  }

  void close() {
    _isEnabled = false;
    // Drop the loaded raw samples (can be a few MB per channel) now that the
    // overlay is closed; they'll be re-fetched fresh next time it's opened.
    _channelSamples.clear();
    _channelPeaks.clear();
    _isLoadingChannelData = false;
    notifyListeners();
  }

  void setChannel(int channel) {
    if (channel == _channelIndex) return;
    _channelIndex = channel;
    notifyListeners();
    unawaited(_ensureChannelData(channel));
  }

  SpikeThreshold addThreshold(int channel) {
    final threshold = _addThreshold(channel);
    _channelIndex = channel;
    notifyListeners();
    return threshold;
  }

  SpikeThreshold _addThreshold(int channel) {
    final list = _thresholdsByChannel.putIfAbsent(channel, () => []);
    final color = palette[list.length % palette.length];
    final threshold = SpikeThreshold(
      id: _newId(),
      highValue: 400,
      lowValue: 150,
      color: color,
    );
    list.add(threshold);
    return threshold;
  }

  void removeThreshold(int channel, String id) {
    _thresholdsByChannel[channel]?.removeWhere((threshold) => threshold.id == id);
    notifyListeners();
  }

  void updateThresholdHigh(int channel, String id, double value) {
    final threshold = _find(channel, id);
    if (threshold == null) return;
    threshold.highValue = max(value, threshold.lowValue);
    notifyListeners();
  }

  void updateThresholdLow(int channel, String id, double value) {
    final threshold = _find(channel, id);
    if (threshold == null) return;
    threshold.lowValue = min(value, threshold.highValue);
    notifyListeners();
  }

  SpikeThreshold? _find(int channel, String id) {
    final list = _thresholdsByChannel[channel];
    if (list == null) return null;
    for (final threshold in list) {
      if (threshold.id == id) return threshold;
    }
    return null;
  }

  String _newId() => 'spike_th_${_nextId++}';
}
