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
/// Each threshold is a window discriminator: a spike is counted/drawn
/// whenever the signal is inside the band between [SpikeThreshold.lowValue]
/// and [SpikeThreshold.highValue]. Detection and the background waveform run
/// against the channel's full-resolution samples as read straight from the
/// currently opened NWB file (see [SpikeAnalysisProvider.samplesFor]). The
/// background waveform is a per-pixel-column min/max envelope of the
/// currently visible time window, the same technique as the native
/// `DrawingUtils::prepareSignalForDrawing` uses to draw the main graph. The
/// visible time window can be zoomed in/out - anchored at its current
/// center - via the +/- control, mouse scroll wheel, or a pinch/trackpad
/// gesture; a scrub bar below lets you pan once zoomed in.
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

  /// Full-channel event detection (entering the [low, high] band with a
  /// refractory period), cached per threshold so dragging one threshold's
  /// handle doesn't force re-scanning every other threshold on each frame.
  _CachedThresholdEvents _eventsFor(Int16List samples, SpikeThreshold threshold) {
    final cached = _eventCache[threshold.id];
    if (cached != null &&
        identical(cached.samples, samples) &&
        cached.highValue == threshold.highValue &&
        cached.lowValue == threshold.lowValue) {
      return cached;
    }
    final events = _detectEvents(
        samples, (v) => v >= threshold.lowValue && v <= threshold.highValue);
    final result =
        _CachedThresholdEvents(samples, threshold.highValue, threshold.lowValue, events);
    _eventCache[threshold.id] = result;
    return result;
  }

  static List<_SpikeEvent> _detectEvents(
      Int16List samples, bool Function(int) qualifies) {
    final events = <_SpikeEvent>[];
    if (samples.isEmpty) return events;
    final refractory = max(2, (samples.length * 0.0004).round());
    bool wasQualifying = qualifies(samples[0]);
    int lastEntry = -refractory * 2;
    for (int i = 1; i < samples.length; i++) {
      final bool q = qualifies(samples[i]);
      if (q && !wasQualifying && (i - lastEntry) > refractory) {
        events.add(_SpikeEvent(i, samples[i].toDouble()));
        lastEntry = i;
      }
      wasQualifying = q;
    }
    return events;
  }

  static List<_RasterPoint> _visibleQualifying(
      Int16List samples, int from, int to, bool Function(int) qualifies) {
    final len = to - from;
    if (len <= 0) return const [];
    final pts = <_RasterPoint>[];
    for (int i = from; i < to; i++) {
      if (qualifies(samples[i])) {
        pts.add(_RasterPoint((i - from) / len, samples[i].toDouble()));
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
        final events = _eventsFor(samples, threshold);
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
                        child: _buildLane(context, channel, thresholds[i], samples,
                            visibleFrom, visibleTo),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            top: 0,
            bottom: 40,
            child: Center(
              child: _buildZoomControl(appColors, samples.length, sampleRateHz),
            ),
          ),
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

  /// "1 s" time scale ruler plus a scrub bar showing/controlling which part
  /// of the file is currently visible (only meaningfully draggable once
  /// zoomed in past the full file duration).
  Widget _buildScrubAndScale(
    AppThemeColors appColors,
    int totalSamples,
    int visibleFrom,
    int visibleTo,
    double visibleSeconds,
  ) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      final pxPerSecond = visibleSeconds > 0 ? width / visibleSeconds : 0.0;
      final scaleBarWidth = pxPerSecond.clamp(16.0, width);

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
                Text('1 s',
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
    int visibleFrom,
    int visibleTo,
  ) {
    final events = _eventsFor(samples, threshold);
    final raster = _visibleQualifying(samples, visibleFrom, visibleTo,
        (v) => v >= threshold.lowValue && v <= threshold.highValue);
    final eventMarkers = _visibleEvents(events.events, visibleFrom, visibleTo);

    return LayoutBuilder(
      builder: (context, constraints) {
        final height = constraints.maxHeight;
        final width = constraints.maxWidth;
        final columns = width.round().clamp(1, 1200);
        final stems = _computeStems(samples, visibleFrom, visibleTo, columns);

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
                    stems: stems,
                    raster: raster,
                    events: eventMarkers,
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
  const _CachedThresholdEvents(this.samples, this.highValue, this.lowValue, this.events);
  final Int16List samples;
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
    required this.raster,
    required this.events,
  });

  final double domainMin;
  final double domainMax;
  final double highValue;
  final double lowValue;
  final Color color;
  final List<_Stem> stems;
  final List<_RasterPoint> raster;
  final List<_RasterPoint> events;

  double _mapY(double value, double height) {
    final range = (domainMax - domainMin).abs() < 1e-6 ? 1.0 : (domainMax - domainMin);
    final normalized = ((value - domainMin) / range).clamp(0.0, 1.0);
    return height * (1 - normalized);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final highY = _mapY(highValue, size.height);
    final lowY = _mapY(lowValue, size.height);

    // Active band: spikes are counted whenever the signal is inside
    // [lowValue, highValue] (a window discriminator).
    canvas.drawRect(
      Rect.fromLTRB(0, highY, size.width, lowY),
      Paint()..color = color.withOpacity(0.10),
    );

    // Background waveform (per-pixel min/max envelope of the visible window).
    final stemPaint = Paint()
      ..color = Colors.white.withOpacity(0.16)
      ..strokeWidth = 1;
    for (final s in stems) {
      final x = s.xFraction * size.width;
      canvas.drawLine(
          Offset(x, _mapY(s.maxV, size.height)), Offset(x, _mapY(s.minV, size.height)), stemPaint);
    }

    // Dense raster cloud of every raw in-band sample in the visible window.
    final dotPaint = Paint()..color = color.withOpacity(0.6);
    for (final p in raster) {
      canvas.drawCircle(
          Offset(p.xFraction * size.width, _mapY(p.value, size.height)), 1.3, dotPaint);
    }

    // Distinct square markers at each detected spike event (refractory-spaced
    // entries into the band).
    final eventPaint = Paint()..color = color;
    for (final p in events) {
      final center = Offset(p.xFraction * size.width, _mapY(p.value, size.height));
      canvas.drawRect(Rect.fromCenter(center: center, width: 5, height: 5), eventPaint);
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
