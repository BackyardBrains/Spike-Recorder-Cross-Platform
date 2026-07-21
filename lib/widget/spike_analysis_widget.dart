import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:provider/provider.dart';
import 'package:spikerbox_architecture/constant/app_theme.dart';
import 'package:spikerbox_architecture/provider/provider_export.dart';

/// Full-screen overlay showing a spike raster for one channel at a time.
///
/// Peak candidates come from native [ProcessingUtil.findSampleSpike]
/// (Schmitt-trigger, same family as desktop SpikeSorter). Every peak is drawn
/// as a white square on the waveform; peaks whose amplitude falls between
/// [SpikeThreshold.lowValue] and [SpikeThreshold.highValue] are recolored and
/// counted (desktop window filter). The background waveform is a per-pixel
/// min/max envelope of the visible window. Zoom is anchored at the current
/// center via +/- / scroll / pinch; a scrub bar pans when zoomed in.
class SpikeAnalysisWidget extends StatefulWidget {
  const SpikeAnalysisWidget({super.key});

  @override
  State<SpikeAnalysisWidget> createState() => _SpikeAnalysisWidgetState();
}

class _SpikeAnalysisWidgetState extends State<SpikeAnalysisWidget> {
  static const double _defaultVisibleSeconds = 5.0;
  static const double _minVisibleSeconds = 0.02;
  static const double _zoomFactor = 1.5;

  double? _visibleSeconds;
  double? _centerSample;
  int? _initializedKey;

  // Tracks the visible-window duration at the start of an in-progress
  // pinch/trackpad zoom gesture so the zoom is relative to that gesture
  // rather than compounding per pointer-move event.
  double? _pinchGestureStartSeconds;
  double? _scaleGestureStartSeconds;

  double _domainMin = -1000;
  double _domainMax = 1000;
  Int16List? _domainForSamples;

  final Map<String, _CachedThresholdEvents> _eventCache = {};

  void _ensureDomain(Int16List samples) {
    if (identical(_domainForSamples, samples)) return;
    if (samples.isEmpty) {
      _domainMin = -1000;
      _domainMax = 1000;
      _domainForSamples = samples;
      return;
    }
    int minV = samples[0];
    int maxV = samples[0];
    for (int i = 1; i < samples.length; i++) {
      final v = samples[i];
      if (v < minV) minV = v;
      if (v > maxV) maxV = v;
    }
    if (maxV == minV) maxV = minV + 1;
    final double pad = max((maxV - minV) * 0.15, 1.0);
    _domainMin = minV - pad;
    _domainMax = maxV + pad;
    _domainForSamples = samples;
  }

  void _ensureViewInitialized(int channel, int totalSamples, int sampleRateHz) {
    final key = channel * 100000000 + totalSamples;
    if (_initializedKey == key) return;
    final totalSeconds = sampleRateHz > 0 ? totalSamples / sampleRateHz : 0.0;
    _visibleSeconds = (totalSeconds <= 0 || totalSeconds <= _defaultVisibleSeconds)
        ? max(totalSeconds, _minVisibleSeconds)
        : _defaultVisibleSeconds;
    // Focus on the middle of the file by default.
    _centerSample = totalSamples / 2;
    _initializedKey = key;
  }

  /// Returns the currently visible `[from, to)` sample index range given the
  /// zoom/pan state, clamped to the file bounds.
  List<int> _visibleRange(int totalSamples, int sampleRateHz) {
    if (totalSamples <= 1) return [0, max(totalSamples, 1)];
    final visibleSamples = ((_visibleSeconds ?? 0) * sampleRateHz)
        .clamp(2.0, totalSamples.toDouble());
    var center = (_centerSample ?? totalSamples / 2).clamp(0.0, totalSamples.toDouble());
    var from = center - visibleSamples / 2;
    var to = center + visibleSamples / 2;
    if (from < 0) {
      to -= from;
      from = 0;
    }
    if (to > totalSamples) {
      from -= (to - totalSamples);
      to = totalSamples.toDouble();
    }
    from = from.clamp(0.0, totalSamples.toDouble());
    to = to.clamp(from + 1, totalSamples.toDouble());
    return [from.floor(), to.ceil().clamp(from.floor() + 1, totalSamples)];
  }

  void _zoomIn(int totalSamples, int sampleRateHz) {
    final totalSeconds = sampleRateHz > 0 ? totalSamples / sampleRateHz : 0.0;
    setState(() {
      final current = _visibleSeconds ?? totalSeconds;
      _visibleSeconds = (current / _zoomFactor)
          .clamp(_minVisibleSeconds, max(totalSeconds, _minVisibleSeconds));
    });
  }

  void _zoomOut(int totalSamples, int sampleRateHz) {
    final totalSeconds = sampleRateHz > 0 ? totalSamples / sampleRateHz : 0.0;
    setState(() {
      final current = _visibleSeconds ?? totalSeconds;
      _visibleSeconds = (current * _zoomFactor)
          .clamp(_minVisibleSeconds, max(totalSeconds, _minVisibleSeconds));
    });
  }

  void _setVisibleSeconds(double seconds, int totalSamples, int sampleRateHz) {
    final totalSeconds = sampleRateHz > 0 ? totalSamples / sampleRateHz : 0.0;
    setState(() {
      _visibleSeconds = seconds.clamp(_minVisibleSeconds, max(totalSeconds, _minVisibleSeconds));
    });
  }

  /// Mouse scroll wheel: scrolling up zooms in, down zooms out - anchored at
  /// the current center, same as the +/- control.
  void _handlePointerSignal(
      PointerSignalEvent event, int totalSamples, int sampleRateHz) {
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
    if (event.scrollDelta.dy < 0) {
      _zoomIn(totalSamples, sampleRateHz);
    } else {
      _zoomOut(totalSamples, sampleRateHz);
    }
  }

  /// Trackpad pinch/pan-zoom gesture (macOS/Windows/web trackpads deliver
  /// this as native pan-zoom pointer events rather than multi-touch pointers).
  void _handlePanZoomStart(PointerPanZoomStartEvent event) {
    _pinchGestureStartSeconds = _visibleSeconds;
  }

  void _handlePanZoomUpdate(
      PointerPanZoomUpdateEvent event, int totalSamples, int sampleRateHz) {
    final start = _pinchGestureStartSeconds;
    if (start == null || event.scale <= 0) return;
    _setVisibleSeconds(start / event.scale, totalSamples, sampleRateHz);
  }

  void _handlePanZoomEnd(PointerPanZoomEndEvent event) {
    _pinchGestureStartSeconds = null;
  }

  /// Two-finger touch pinch (mobile/tablet). Ignored for single-pointer
  /// gestures so it doesn't compete with dragging a threshold handle.
  void _handleScaleStart(ScaleStartDetails details) {
    _scaleGestureStartSeconds = details.pointerCount >= 2 ? _visibleSeconds : null;
  }

  void _handleScaleUpdate(
      ScaleUpdateDetails details, int totalSamples, int sampleRateHz) {
    final start = _scaleGestureStartSeconds;
    if (start == null || details.pointerCount < 2 || details.scale <= 0) return;
    _setVisibleSeconds(start / details.scale, totalSamples, sampleRateHz);
  }

  void _handleScaleEnd(ScaleEndDetails details) {
    _scaleGestureStartSeconds = null;
  }

  void _panBySamples(double deltaSamples, int totalSamples) {
    setState(() {
      final current = _centerSample ?? totalSamples / 2;
      _centerSample = (current + deltaSamples).clamp(0.0, totalSamples.toDouble());
    });
  }

  void _panToFraction(double fraction, int totalSamples) {
    setState(() {
      _centerSample = fraction.clamp(0.0, 1.0) * totalSamples;
    });
  }

  /// Filters [findSampleSpike] peaks into the threshold amplitude window for
  /// the sidebar spike count. Peak *markers* on the waveform show every
  /// detected peak (desktop SpikeSorter style); only the count uses this
  /// window filter.
  _CachedThresholdEvents _eventsFor(
      List<SpikePeak> peaks, SpikeThreshold threshold) {
    final cached = _eventCache[threshold.id];
    if (cached != null &&
        identical(cached.peaks, peaks) &&
        cached.highValue == threshold.highValue &&
        cached.lowValue == threshold.lowValue) {
      return cached;
    }
    final low = min(threshold.lowValue, threshold.highValue);
    final high = max(threshold.lowValue, threshold.highValue);
    final events = <_SpikeEvent>[];
    for (final peak in peaks) {
      final v = peak.value.toDouble();
      if (v >= low && v <= high) {
        events.add(_SpikeEvent(peak.index, v));
      }
    }
    final result =
        _CachedThresholdEvents(peaks, threshold.highValue, threshold.lowValue, events);
    _eventCache[threshold.id] = result;
    return result;
  }

  static List<_RasterPoint> _visiblePeaks(
      List<SpikePeak> peaks, int from, int to) {
    final len = to - from;
    if (len <= 0) return const [];
    final pts = <_RasterPoint>[];
    for (final peak in peaks) {
      if (peak.index >= from && peak.index < to) {
        pts.add(_RasterPoint((peak.index - from) / len, peak.value.toDouble()));
      }
    }
    return pts;
  }

  static List<_RasterPoint> _visibleEvents(
      List<_SpikeEvent> events, int from, int to) {
    final len = to - from;
    if (len <= 0) return const [];
    final pts = <_RasterPoint>[];
    for (final e in events) {
      if (e.index >= from && e.index < to) {
        pts.add(_RasterPoint((e.index - from) / len, e.value));
      }
    }
    return pts;
  }

  static List<_RasterPoint> _visibleRawSamples(
      Int16List samples, int from, int to) {
    final len = to - from;
    if (len <= 0) return const [];
    final pts = <_RasterPoint>[];
    for (int i = from; i < to; i++) {
      pts.add(_RasterPoint((i - from) / len, samples[i].toDouble()));
    }
    return pts;
  }

  /// Per-pixel-column min/max envelope of the visible window - the same
  /// downsampling idea as the native `DrawingUtils::prepareSignalForDrawing`
  /// uses to paint the main graph, reimplemented here in Dart so the
  /// background waveform stays legible (and cheap to draw) no matter how
  /// many raw samples are zoomed out into view.
  static List<_Stem> _computeStems(Int16List samples, int from, int to, int columns) {
    final len = to - from;
    if (len <= 0 || columns <= 0) return const [];
    final stems = <_Stem>[];
    for (int col = 0; col < columns; col++) {
      final startIdx = from + (col * len / columns).floor();
      if (startIdx >= to) break;
      var endIdx = from + ((col + 1) * len / columns).floor();
      if (endIdx <= startIdx) endIdx = startIdx + 1;
      if (endIdx > to) endIdx = to;
      int mn = samples[startIdx];
      int mx = samples[startIdx];
      for (int i = startIdx + 1; i < endIdx; i++) {
        final v = samples[i];
        if (v < mn) mn = v;
        if (v > mx) mx = v;
      }
      stems.add(_Stem(col / columns, mn.toDouble(), mx.toDouble()));
    }
    return stems;
  }

  @override
  Widget build(BuildContext context) {
    final appColors = AppThemeColors.of(context.watch<ThemeModeProvider>().isDarkMode);
    final provider = context.watch<SpikeAnalysisProvider>();
    final channel = provider.channelIndex;
    final thresholds = provider.thresholdsFor(channel);
    final samples = provider.samplesFor(channel);
    final peaks = provider.peaksFor(channel);
    final sampleRateHz = provider.sampleRateHz;

    // Spike counts shown in the side panel always match the number of event
    // markers actually drawn in the currently visible time window (not a
    // whole-file total), so the number on screen never disagrees with what
    // you can see/count in the raster yourself.
    final visibleCounts = <String, int>{};

    Widget content;
    if (samples == null) {
      content = Center(
        child: provider.isLoadingChannelData
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text('Loading channel ${channel + 1} from file…',
                      style: TextStyle(color: appColors.textSecondary)),
                ],
              )
            : Text(
                'Could not load data for this channel.',
                style: TextStyle(color: appColors.textSecondary),
              ),
      );
    } else if (samples.isEmpty) {
      content = Center(
        child: Text(
          'This channel has no recorded samples.',
          style: TextStyle(color: appColors.textSecondary),
        ),
      );
    } else if (thresholds.isEmpty) {
      content = Center(
        child: Text(
          'Add a threshold from the panel on the right\nto start the raster for this channel.',
          textAlign: TextAlign.center,
          style: TextStyle(color: appColors.textSecondary),
        ),
      );
    } else {
      _ensureDomain(samples);
      _ensureViewInitialized(channel, samples.length, sampleRateHz);
      final range = _visibleRange(samples.length, sampleRateHz);
      final visibleFrom = range[0];
      final visibleTo = range[1];
      final visibleSeconds = _visibleSeconds ?? 1.0;

      for (final threshold in thresholds) {
        final events = _eventsFor(peaks, threshold);
        visibleCounts[threshold.id] =
            _visibleEvents(events.events, visibleFrom, visibleTo).length;
      }

      content = Stack(
        children: [
          Listener(
            behavior: HitTestBehavior.translucent,
            onPointerSignal: (event) =>
                _handlePointerSignal(event, samples.length, sampleRateHz),
            onPointerPanZoomStart: _handlePanZoomStart,
            onPointerPanZoomUpdate: (event) =>
                _handlePanZoomUpdate(event, samples.length, sampleRateHz),
            onPointerPanZoomEnd: _handlePanZoomEnd,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onScaleStart: _handleScaleStart,
              onScaleUpdate: (details) =>
                  _handleScaleUpdate(details, samples.length, sampleRateHz),
              onScaleEnd: _handleScaleEnd,
              child: Padding(
                padding: const EdgeInsets.only(left: 34, bottom: 40),
                child: Column(
                  children: [
                    for (int i = 0; i < thresholds.length; i++) ...[
                      if (i > 0) const SizedBox(height: 10),
                      Expanded(
                        child: _buildLane(
                            context,
                            channel,
                            thresholds[i],
                            samples,
                            peaks,
                            visibleFrom,
                            visibleTo),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          // Positioned(
          //   left: 0,
          //   top: 0,
          //   bottom: 40,
          //   child: Center(
          //     child: _buildZoomControl(appColors, samples.length, sampleRateHz),
          //   ),
          // ),
          Positioned(
            left: 34,
            right: 0,
            bottom: 0,
            height: 36,
            child: _buildScrubAndScale(appColors, samples.length, visibleFrom,
                visibleTo, visibleSeconds),
          ),
        ],
      );
    }

    return Material(
      color: appColors.panelBackground,
      borderRadius: BorderRadius.circular(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Column(
              children: [
                _buildHeader(appColors, provider, channel),
                Divider(height: 1, color: appColors.divider),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: content,
                  ),
                ),
              ],
            ),
          ),
          VerticalDivider(width: 1, color: appColors.divider),
          _buildChannelPanel(context, appColors, provider, channel, visibleCounts),
        ],
      ),
    );
  }

  Widget _buildHeader(
    AppThemeColors appColors,
    SpikeAnalysisProvider provider,
    int channel,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 10, 16, 10),
      child: Row(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => provider.close(),
            child: Padding(
              padding: const EdgeInsets.all(6.0),
              child: Icon(Icons.arrow_back, color: appColors.iconPrimary),
            ),
          ),
          const SizedBox(width: 6),
          SvgPicture.asset(
            'assets/icons/raw/button_flask.svg',
            width: 22,
            height: 22,
            colorFilter: ColorFilter.mode(appColors.iconPrimary, BlendMode.srcIn),
          ),
          const SizedBox(width: 8),
          Text(
            'Spike Analysis',
            style: TextStyle(
              color: appColors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  /// A small +/- control that zooms the visible time window in/out while
  /// keeping it centered on its current midpoint.
  Widget _buildZoomControl(AppThemeColors appColors, int totalSamples, int sampleRateHz) {
    return Container(
      width: 26,
      decoration: BoxDecoration(
        color: appColors.cardBackground,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: appColors.divider),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(13)),
            onTap: () => _zoomIn(totalSamples, sampleRateHz),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Icon(Icons.add, size: 15, color: appColors.iconPrimary),
            ),
          ),
          Divider(height: 1, color: appColors.divider),
          InkWell(
            borderRadius: const BorderRadius.vertical(bottom: Radius.circular(13)),
            onTap: () => _zoomOut(totalSamples, sampleRateHz),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Icon(Icons.remove, size: 15, color: appColors.iconPrimary),
            ),
          ),
        ],
      ),
    );
  }

  /// Picks a "nice" scale-bar duration for the current zoom (same idea as
  /// desktop Spike Analysis: 1 s → 0.1 s → 0.01 s as you zoom in).
  static double _niceScaleSeconds(double visibleSeconds) {
    const candidates = <double>[
      10, 5, 2, 1, 0.5, 0.2, 0.1, 0.05, 0.02, 0.01, 0.005, 0.002, 0.001,
    ];
    // Aim for a bar roughly 1/5–1/3 of the view width.
    final target = visibleSeconds / 4;
    for (final c in candidates) {
      if (c <= target) return c;
    }
    return max(visibleSeconds / 4, 0.001);
  }

  static String _formatScaleLabel(double seconds) {
    if (seconds >= 1) {
      return seconds == seconds.roundToDouble()
          ? '${seconds.toInt()} s'
          : '${seconds.toStringAsFixed(1)} s';
    }
    if (seconds >= 0.1) return '${seconds.toStringAsFixed(1)} s';
    if (seconds >= 0.01) return '${seconds.toStringAsFixed(2)} s';
    return '${seconds.toStringAsFixed(3)} s';
  }

  /// Adaptive time-scale ruler plus a scrub bar showing/controlling which
  /// part of the file is currently visible (thumb shrinks as you zoom in).
  Widget _buildScrubAndScale(
    AppThemeColors appColors,
    int totalSamples,
    int visibleFrom,
    int visibleTo,
    double visibleSeconds,
  ) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final safeVisible =
          visibleSeconds > 0 ? visibleSeconds : _minVisibleSeconds;
      final scaleSeconds = _niceScaleSeconds(safeVisible);
      final scaleBarWidth =
          ((scaleSeconds / safeVisible) * width).clamp(16.0, width * 0.55);

      final fromFrac = totalSamples > 0 ? visibleFrom / totalSamples : 0.0;
      final toFrac = totalSamples > 0 ? visibleTo / totalSamples : 1.0;
      final thumbLeft = (fromFrac * width).clamp(0.0, width);
      final thumbWidth = ((toFrac - fromFrac) * width).clamp(8.0, width);

      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4, right: 2),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                    width: scaleBarWidth,
                    height: 1.5,
                    color: appColors.textSecondary.withOpacity(0.7)),
                const SizedBox(height: 2),
                Text(_formatScaleLabel(scaleSeconds),
                    style: TextStyle(color: appColors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragUpdate: (details) {
              if (width <= 0) return;
              final deltaFraction = details.delta.dx / width;
              _panBySamples(deltaFraction * totalSamples, totalSamples);
            },
            onTapDown: (details) {
              if (width <= 0) return;
              _panToFraction(details.localPosition.dx / width, totalSamples);
            },
            child: Container(
              height: 10,
              width: width,
              decoration: BoxDecoration(
                color: appColors.textSecondary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(5),
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: thumbLeft,
                    width: thumbWidth,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      decoration: BoxDecoration(
                        color: appColors.textSecondary.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    });
  }

  /// Single-channel side panel: only the currently active channel's
  /// thresholds are shown/edited here. Prev/next arrows switch which one
  /// channel is being analyzed; the raster never shows more than one
  /// channel's data at a time.
  Widget _buildChannelPanel(
    BuildContext context,
    AppThemeColors appColors,
    SpikeAnalysisProvider provider,
    int channel,
    Map<String, int> visibleCounts,
  ) {
    // Use the channel count captured when the overlay was opened (the
    // authoritative count for the current session/file) rather than the raw
    // drawing-buffer list, which can be stale/oversized from a previous
    // session and would otherwise expose a channel that isn't really there.
    final totalChannels = provider.channelCount;
    final thresholds = provider.thresholdsFor(channel);
    return Container(
      width: 190,
      color: appColors.cardBackground,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: channel > 0
                      ? () => provider.setChannel(channel - 1)
                      : null,
                  child: Icon(
                    Icons.chevron_left,
                    size: 20,
                    color: channel > 0
                        ? appColors.iconPrimary
                        : appColors.textSecondary.withOpacity(0.3),
                  ),
                ),
                Expanded(
                  child: Text(
                    'Channel ${channel + 1}',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: appColors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: channel < totalChannels - 1
                      ? () => provider.setChannel(channel + 1)
                      : null,
                  child: Icon(
                    Icons.chevron_right,
                    size: 20,
                    color: channel < totalChannels - 1
                        ? appColors.iconPrimary
                        : appColors.textSecondary.withOpacity(0.3),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            for (final threshold in thresholds)
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    Container(
                      width: 14,
                      height: 14,
                      decoration:
                          BoxDecoration(color: threshold.color, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '${visibleCounts[threshold.id] ?? 0} spikes',
                        style: TextStyle(
                            color: threshold.color, fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    InkWell(
                      onTap: () => provider.removeThreshold(channel, threshold.id),
                      child: Padding(
                        padding: const EdgeInsets.all(4.0),
                        child: Icon(Icons.remove,
                            size: 14, color: appColors.textSecondary),
                      ),
                    ),
                  ],
                ),
              ),
            InkWell(
              onTap: () => provider.addThreshold(channel),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: appColors.buttonBackground,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(Icons.add, size: 16, color: appColors.iconPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLane(
    BuildContext context,
    int channel,
    SpikeThreshold threshold,
    Int16List samples,
    List<SpikePeak> peaks,
    int visibleFrom,
    int visibleTo,
  ) {
    final events = _eventsFor(peaks, threshold);
    // Desktop AnalysisAudioView: draw EVERY sorter peak as a white square,
    // then recolor those inside the amplitude window.
    final allPeakMarkers = _visiblePeaks(peaks, visibleFrom, visibleTo);
    final selectedPeakMarkers =
        _visibleEvents(events.events, visibleFrom, visibleTo);

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final width = constraints.maxWidth;
        final columns = width.round().clamp(1, 1200);
        final visibleLen = visibleTo - visibleFrom;
        // When zoomed in enough for ≤1 sample/pixel, draw the raw polyline
        // (desktop AudioView path when samplesPerPixel == 1). Otherwise use
        // the min/max envelope path.
        final List<_Stem>? stems = visibleLen > columns
            ? _computeStems(samples, visibleFrom, visibleTo, columns)
            : null;
        final List<_RasterPoint>? rawWave = visibleLen <= columns
            ? _visibleRawSamples(samples, visibleFrom, visibleTo)
            : null;

        void dragHigh(DragUpdateDetails details) {
          if (height <= 0) return;
          final deltaValue = -(details.delta.dy / height) * (_domainMax - _domainMin);
          context.read<SpikeAnalysisProvider>().updateThresholdHigh(
              channel, threshold.id, threshold.highValue + deltaValue);
        }

        void dragLow(DragUpdateDetails details) {
          if (height <= 0) return;
          final deltaValue = -(details.delta.dy / height) * (_domainMax - _domainMin);
          context.read<SpikeAnalysisProvider>().updateThresholdLow(
              channel, threshold.id, threshold.lowValue + deltaValue);
        }

        return Stack(
          children: [
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  size: Size(width, height),
                  painter: _ThresholdPanePainter(
                    domainMin: _domainMin,
                    domainMax: _domainMax,
                    highValue: threshold.highValue,
                    lowValue: threshold.lowValue,
                    color: threshold.color,
                    stems: stems ?? const [],
                    rawWave: rawWave ?? const [],
                    allPeaks: allPeakMarkers,
                    selectedPeaks: selectedPeakMarkers,
                  ),
                ),
              ),
            ),
            _buildHandleRow(width, height, threshold.highValue, threshold.color, dragHigh),
            _buildHandleRow(width, height, threshold.lowValue, threshold.color, dragLow),
          ],
        );
      },
    );
  }

  Widget _buildHandleRow(
    double width,
    double height,
    double value,
    Color color,
    GestureDragUpdateCallback onDrag,
  ) {
    final range =
        (_domainMax - _domainMin).abs() < 1e-6 ? 1.0 : (_domainMax - _domainMin);
    final normalized = ((value - _domainMin) / range).clamp(0.0, 1.0);
    final y = height * (1 - normalized);
    return Positioned(
      left: 0,
      right: 0,
      top: (y - 12).clamp(0.0, max(height - 24, 0.0)),
      height: 24,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onVerticalDragUpdate: onDrag,
        child: Row(
          children: [
            Expanded(child: Container()),
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: CustomPaint(
                size: const Size(20, 20),
                painter: _HandlePainter(color: color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpikeEvent {
  const _SpikeEvent(this.index, this.value);
  final int index;
  final double value;
}

class _CachedThresholdEvents {
  const _CachedThresholdEvents(this.peaks, this.highValue, this.lowValue, this.events);
  final List<SpikePeak> peaks;
  final double highValue;
  final double lowValue;
  final List<_SpikeEvent> events;
}

class _RasterPoint {
  const _RasterPoint(this.xFraction, this.value);
  final double xFraction;
  final double value;
}

/// One pixel column's min/max amplitude within the visible window - mirrors
/// what `DrawingUtils::prepareSignalForDrawing` computes natively for the
/// main graph, used here to draw a lightweight background waveform.
class _Stem {
  const _Stem(this.xFraction, this.minV, this.maxV);
  final double xFraction;
  final double minV;
  final double maxV;
}

class _ThresholdPanePainter extends CustomPainter {
  _ThresholdPanePainter({
    required this.domainMin,
    required this.domainMax,
    required this.highValue,
    required this.lowValue,
    required this.color,
    required this.stems,
    required this.rawWave,
    required this.allPeaks,
    required this.selectedPeaks,
  });

  final double domainMin;
  final double domainMax;
  final double highValue;
  final double lowValue;
  final Color color;
  final List<_Stem> stems;
  final List<_RasterPoint> rawWave;
  final List<_RasterPoint> allPeaks;
  final List<_RasterPoint> selectedPeaks;

  static const Color _waveColor = Color(0xFF9E9E9E);

  double _mapY(double value, double height) {
    final range = (domainMax - domainMin).abs() < 1e-6 ? 1.0 : (domainMax - domainMin);
    final normalized = ((value - domainMin) / range).clamp(0.0, 1.0);
    return height * (1 - normalized);
  }

  void _drawWaveform(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = _waveColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..strokeJoin = StrokeJoin.round
      ..isAntiAlias = true;

    if (rawWave.isNotEmpty) {
      final path = Path();
      for (var i = 0; i < rawWave.length; i++) {
        final p = rawWave[i];
        final o = Offset(p.xFraction * size.width, _mapY(p.value, size.height));
        if (i == 0) {
          path.moveTo(o.dx, o.dy);
        } else {
          path.lineTo(o.dx, o.dy);
        }
      }
      canvas.drawPath(path, paint);
      return;
    }

    if (stems.isEmpty) return;
    // Desktop AudioView::drawData: GL_LINE_STRIP with (max, min) at each x.
    final path = Path();
    var started = false;
    for (final s in stems) {
      final x = s.xFraction * size.width;
      final yMax = _mapY(s.maxV, size.height);
      final yMin = _mapY(s.minV, size.height);
      if (!started) {
        path.moveTo(x, yMax);
        started = true;
      } else {
        path.lineTo(x, yMax);
      }
      path.lineTo(x, yMin);
    }
    canvas.drawPath(path, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final highY = _mapY(highValue, size.height);
    final lowY = _mapY(lowValue, size.height);

    // Soft band between the two threshold handles (window discriminator).
    canvas.drawRect(
      Rect.fromLTRB(0, highY, size.width, lowY),
      Paint()..color = color.withOpacity(0.08),
    );

    _drawWaveform(canvas, size);

    // All findSampleSpike peaks as white 3x3 squares (desktop AnalysisAudioView).
    final allPaint = Paint()..color = Colors.white;
    for (final p in allPeaks) {
      final center = Offset(p.xFraction * size.width, _mapY(p.value, size.height));
      canvas.drawRect(Rect.fromCenter(center: center, width: 3, height: 3), allPaint);
    }

    // Peaks inside the amplitude window get the train color (selected).
    final selectedPaint = Paint()..color = color;
    for (final p in selectedPeaks) {
      final center = Offset(p.xFraction * size.width, _mapY(p.value, size.height));
      canvas.drawRect(Rect.fromCenter(center: center, width: 5, height: 5), selectedPaint);
    }

    final linePaint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(0, highY), Offset(size.width, highY), linePaint);
    canvas.drawLine(Offset(0, lowY), Offset(size.width, lowY), linePaint);
  }

  @override
  bool shouldRepaint(covariant _ThresholdPanePainter oldDelegate) => true;
}

class _HandlePainter extends CustomPainter {
  _HandlePainter({required this.color});
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    canvas.drawCircle(center, size.width / 2 - 1, Paint()..color = color);
    canvas.drawCircle(center, size.width / 2 - 1, Paint()
      ..color = Colors.black
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5);
    canvas.drawCircle(center, 2.6, Paint()..color = Colors.black);
  }

  @override
  bool shouldRepaint(covariant _HandlePainter oldDelegate) => oldDelegate.color != color;
}
