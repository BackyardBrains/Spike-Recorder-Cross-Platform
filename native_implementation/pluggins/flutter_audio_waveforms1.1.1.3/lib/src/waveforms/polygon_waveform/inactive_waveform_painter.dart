// ignore_for_file: omit_local_variable_types

import 'package:flutter/material.dart';
import 'package:flutter_audio_waveforms/src/core/waveform_painters_ab.dart';
import 'package:flutter_audio_waveforms/src/util/waveform_alignment.dart';
import 'package:flutter_audio_waveforms/src/waveforms/polygon_waveform/polygon_waveform.dart';

///InActiveWaveformPainter for the [PolygonWaveform]
class PolygonInActiveWaveformPainter extends InActiveWaveformPainter {
  // ignore: public_member_api_docs
  PolygonInActiveWaveformPainter({
    Color color = Colors.red,
    Gradient? gradient,
    required List<double> samples,
    required WaveformAlignment waveformAlignment,
    required PaintingStyle style,
    required double sampleWidth,
    this.channelIdx = 0,
    this.channelActive = 1,
    this.gain = 100,
    this.levelMedian = -1,
    this.strokeWidth = 0.5,
    this.eventMarkersNumber = 1,
    this.eventMarkersPosition = const [],
  }) : super(
          samples: samples,
          color: color,
          gradient: gradient,
          waveformAlignment: waveformAlignment,
          sampleWidth: sampleWidth,
          style: style,
        ) {
    mypaint = Paint()
      ..style = style
      ..isAntiAlias = false
      ..shader = null
      ..color = color
      ..strokeWidth = strokeWidth;

    // ignore: omit_local_variable_types
    for (int i = 0; i < 10; i++) {
      final strMarkerNumber = ' $i ';
      final TextSpan span = TextSpan(
        style:
            TextStyle(color: Colors.black, backgroundColor: MARKER_COLORS[i]),
        text: strMarkerNumber,
      );
      final TextPainter tp = TextPainter(
        text: span,
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
      );
      tp.layout();
      textPainters.add(tp);
    }
  }

  // ignore: public_member_api_docs
  final int channelIdx;
  final int channelActive;
  final double gain;
  final double levelMedian;
  final double strokeWidth;
  final int eventMarkersNumber;
  final List<double> eventMarkersPosition;

  double prevMax = 0;
  double curMax = 0;

  List<TextPainter> textPainters = [];
  late Paint mypaint;

  @override
  bool shouldRepaint(PolygonInActiveWaveformPainter oldDelegate) {
    if (oldDelegate.gain != gain ||
        oldDelegate.samples != samples ||
        oldDelegate.levelMedian != levelMedian ||
        oldDelegate.eventMarkersPosition != eventMarkersPosition) {
      return true;
    }
    return false;
  }

  /// Style of the waveform
  int sign = 1;

  // https://groups.google.com/g/flutter-dev/c/Za4M3U_MaAo?pli=1
  // Performance textPainter vs Paragraph https://stackoverflow.com/questions/51640388/flutter-textpainter-vs-paragraph-for-drawing-book-page
  @override
  void paint(Canvas canvas, Size size) {
    try {
      // final Rect clipRect = Rect.fromPoints(
      //   Offset.zero,
      //   Offset(size.width, size.height),
      // );

      // canvas.clipRect(clipRect);

      final path = Path();
      int i = 0;
      for (; i < samples.length - 1; i++) {
        final x = sampleWidth * i;
        final y = samples[i] * gain;
        path.lineTo(x, y);
        // if (i < 10) {
        //   print("values at index $i : ${samples[i]}");
        // }
        // if (i == 0) {
        //   path.moveTo(x, y);
        // } else {
        //   path.lineTo(x, y);
        // }
      }

      final shiftedPath = path.shift(Offset(0, levelMedian));
      canvas.drawPath(shiftedPath, mypaint);
      if (eventMarkersPosition.isNotEmpty && channelIdx == channelActive) {
        var n = eventMarkersPosition.length;
        double prevX = -1;
        double counterStacked = 10;
        double evY = 0;
        if (channelIdx == 2) {
          evY = -50;
        }

        // try{
        for (i = 0; i < n; i++) {
          if (eventMarkersPosition[i] == 0) {
            continue;
          }
          final evX = eventMarkersPosition[i];
          final offset1 = Offset(evX, evY);
          final offset2 = Offset(evX, 2900);

          canvas.drawLine(
            offset1,
            offset2,
            MARKER_PAINT[eventMarkersNumber],
          );
          final TextPainter tp = textPainters[eventMarkersNumber];
          counterStacked = i > 0 && evX - 20 <= prevX ? 30 : 100;
          prevX = evX;
          tp.paint(canvas, Offset(evX - 3, counterStacked));
        }
      }
    } catch (err) {
      print("errx");
      print(err);
    }
  }
}

List<Color> MARKER_COLORS = const [
  Color.fromARGB(255, 216, 180, 231),
  Color.fromARGB(255, 176, 229, 124),
  Color.fromARGB(255, 255, 80, 0), //orange
  Color.fromARGB(255, 255, 236, 148),
  Color.fromARGB(255, 255, 174, 174),
  Color.fromARGB(255, 180, 216, 231),
  Color.fromARGB(255, 193, 218, 214),
  Color.fromARGB(255, 172, 209, 233),
  Color.fromARGB(255, 174, 255, 174),
  Color.fromARGB(255, 255, 236, 255),
];
List<Paint> MARKER_PAINT = [
  Paint()
    ..style = PaintingStyle.stroke
    ..color = MARKER_COLORS[0]
    ..strokeWidth = 1,
  Paint()
    ..style = PaintingStyle.stroke
    ..color = MARKER_COLORS[1]
    ..strokeWidth = 1,
  Paint()
    ..style = PaintingStyle.stroke
    ..color = MARKER_COLORS[2]
    ..strokeWidth = 1,
  Paint()
    ..style = PaintingStyle.stroke
    ..color = MARKER_COLORS[3]
    ..strokeWidth = 1,
  Paint()
    ..style = PaintingStyle.stroke
    ..color = MARKER_COLORS[4]
    ..strokeWidth = 1,
  Paint()
    ..style = PaintingStyle.stroke
    ..color = MARKER_COLORS[5]
    ..strokeWidth = 1,
  Paint()
    ..style = PaintingStyle.stroke
    ..color = MARKER_COLORS[6]
    ..strokeWidth = 1,
  Paint()
    ..style = PaintingStyle.stroke
    ..color = MARKER_COLORS[7]
    ..strokeWidth = 1,
  Paint()
    ..style = PaintingStyle.stroke
    ..color = MARKER_COLORS[8]
    ..strokeWidth = 1,
  Paint()
    ..style = PaintingStyle.stroke
    ..color = MARKER_COLORS[9]
    ..strokeWidth = 1,
];
