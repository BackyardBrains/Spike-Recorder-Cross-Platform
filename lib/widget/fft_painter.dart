import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

// You will need to define your FftDrawData class
// This is a placeholder for demonstration.
class FftDrawData {
  final Float32List vertices;
  final Int32List colors;
  final Uint16List indices;
  final int vertexCount;
  final int colorCount;
  final int indexCount;
  final double scaleX;
  final double scaleY;

  FftDrawData({
    required this.vertices,
    required this.colors,
    required this.indices,
    required this.vertexCount,
    required this.colorCount,
    required this.indexCount,
    required this.scaleX,
    required this.scaleY,
  });
}


// A placeholder for the Spectrogram
class SpectrogramPainter extends CustomPainter {
  final FftDrawData fftData;

  SpectrogramPainter({required this.fftData});

  @override
  void paint(Canvas canvas, Size size) {
    // Implement your spectrogram drawing logic here.
    // This would likely involve drawing a series of rectangles or lines
    // based on the FFT data.
    // For example, to draw a red rectangle:
    // final paint = Paint()..color = Colors.red;
    // canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);
  }

  @override
  bool shouldRepaint(covariant SpectrogramPainter oldDelegate) {
    return oldDelegate.fftData.scaleX != fftData.scaleX ||
        oldDelegate.fftData.scaleY != fftData.scaleY;
  }
}

class FftPainter extends CustomPainter {
  final FftDrawData fftData;

  FftPainter({required this.fftData});

  // Constants from the original code
  static const double _axisNotchSize1 = 5.0;
  static const double _axisNotchSize5 = 10.0;
  static const double _axisNotchSize10 = 15.0;
  static const double _axisValueXOffset = 20.0;
  static const double _axisValueYOffset = 5.0;
  static const double _axisValuesXDrawMargin = _axisNotchSize10 + _axisValueXOffset;
  static const double _axisValuesYDrawMargin = _axisNotchSize10 + _axisValueYOffset;

  static const String _timeAxisName = 'Time [S]';
  static const double _timeAxisNameXOffset = 30.0;
  static const double _timeAxisNameYOffset = 20.0;
  static const List<String> _timeAxisValues = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10'];
  static final int _timeAxisNotchCount = (_timeAxisValues.length - 1) * 10 + 1;

  static const List<String> _freqAxisValues = ['0', '10', '20', '30'];
  static const List<String> _freqAxisValuesZoomed =
      ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '10', '11', '12', '13', '14'];
  static final int _freqAxisNotchCount = (_freqAxisValues.length - 1) * 10 + 3;
  static final int _freqAxisNotchCountZoomed = (_freqAxisValuesZoomed.length - 1) * 10 + 3;
  static final double _freqAxisNotchZoomSwitchScale =
      _freqAxisNotchCount * 10.0 / _freqAxisNotchCountZoomed;

  // Replaces GLText.getHeight() and getLength()
  static Size getTextSize(String text, double fontSize, {TextAlign align = TextAlign.left}){
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        color: Colors.white,
        fontSize: fontSize,
        fontFamily: 'RobotoMono',
        fontWeight: FontWeight.bold,
      ),
    );    

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr, // Or TextDirection.rtl
    );
    textPainter.layout();
    return textPainter.size;

  }
  static ui.Paragraph _buildParagraph(String text, double fontSize, {TextAlign align = TextAlign.left}) {
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(
        textAlign: align,
        fontSize: fontSize,
        fontFamily: 'RobotoMono', // Use a monospaced font for consistent sizing
      ),
    )
      ..pushStyle(ui.TextStyle(color: Colors.white))
      ..addText(text);
    return builder.build()..layout(const ui.ParagraphConstraints(width: 1000.0));
  }

  void _drawText(Canvas canvas, String text, Offset position, double fontSize, {TextAlign align = TextAlign.left}) {
    final paragraph = _buildParagraph(text, fontSize, align: align);
    canvas.drawParagraph(paragraph, position);
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Save the canvas state before any transformations
    canvas.save();
    
    // --- Draw the Spectrogram ---
    // The original code used glRectangleMask and glSpectrogram.
    // In Flutter, we can use canvas.clipRect to create a drawing mask
    // and then use a custom painter to draw the spectrogram inside it.
    
    // Create a clipping rectangle (mask)
    canvas.clipRect(Rect.fromLTWH(0, 0, size.width, size.height));

    // Scale the canvas for the spectrogram drawing
    // canvas.scale(1.0, fftData.scaleY);
    // You would call your SpectrogramPainter here
    // For example: SpectrogramPainter(fftData: fftData).paint(canvas, size);
    _drawSpectrogram(canvas, size, fftData);

    // Restore the canvas state after drawing the spectrogram
    canvas.restore();
    
    // --- Draw the Time Axis ---
    // The original code translates the canvas to the bottom of the screen.
    // In Flutter, we can draw directly at the bottom using `size.height`.
    _drawTimeAxis(canvas, size, size.width, fftData.scaleX);

    // --- Draw the Frequency Axis ---
    _drawFrequencyAxis(canvas, size, size.height, fftData.scaleY);
  }

  void _drawSpectrogram(Canvas canvas, Size size, FftDrawData fft) {
    if (fft.vertices.isEmpty || fft.indices.isEmpty) {
      // print("EMPTY");
      return;
    }
    // final positions = Float32List.fromList([
    //   0.0, 0.0, // Top-left
    //   size.width, 0.0, // Top-right
    //   size.width, size.height, // Bottom-right
    //   0.0, size.height, // Bottom-left
    // ]);

    // final color = Int32List.fromList([
    //   0xFF00FF00, // Green (top-left)
    //   0xFF0000FF, // Blue (top-right)
    //   0xFFFFFF00, // Yellow (bottom-right)
    //   0xFFFF0000, // Red (bottom-left)
    // ]);
    // Flutter's Canvas.drawVertices requires ui.Vertices
    // print("fft.vertices.length: ${fft.vertices.length}");
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      fft.vertices,
      colors: fft.colors,
      indices: fft.indices,
      // positions,
      // colors: color,
      // indices: Uint16List.fromList([0,1,2, 3,2,1]),
    );

    // No need for a separate paint object, as the color is per-vertex
    final paint = Paint()
      ..color = Colors.blue
      ..style = PaintingStyle.fill;

    canvas.drawVertices(vertices, ui.BlendMode.srcOver, paint);
  }  

  void _drawTimeAxis(Canvas canvas, Size size, double width, double scaleX) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final path = Path();
    final valueStep = width / (_timeAxisNotchCount - 1) * scaleX;
    // final double textHeight = _buildParagraph('0', 16).height;
    final double textHeight = getTextSize('0', 16).height;
    final double timeAxisValueY = (textHeight - _axisNotchSize10 - _axisValueYOffset);
    final double timeAxisNameY = timeAxisValueY + (textHeight - _timeAxisNameYOffset / 2);
    // final double drawMarginX = _axisValuesXDrawMargin + getTextSize(_timeAxisValues[0], 16).width * 0.5;
    final double drawMarginX = 0;

    // Draw notches
    for (int i = 0; i < _timeAxisNotchCount; i++) {
      final double x = width - valueStep * i + drawMarginX;
      if (x >= 0) {
        double notchSize = _axisNotchSize1;
        if (i % 10 == 0) {
          notchSize = _axisNotchSize10;
        } else if (i % 5 == 0) {
          notchSize = _axisNotchSize5;
        }
        path.moveTo(x, 0);
        path.lineTo(x, -notchSize);
      }
    }
    canvas.drawPath(path, paint);

    // Draw scale values and axis name
    final textPaint = Paint()..color = Colors.white;
    int labelLength = _timeAxisValues.length;
    for (int i = 0; i < labelLength; i++) {
      final double x = valueStep * i * 10 - 4 + drawMarginX;
      if (x > _axisValuesXDrawMargin && width - x > _axisValuesXDrawMargin) {
        _drawText(canvas, _timeAxisValues[labelLength - i - 1], Offset(x, timeAxisValueY), 12, align: TextAlign.left);
      }
    }

    final String timeAxisName = 'Time [S]';
    // final double timeAxisNameW = _buildParagraph(timeAxisName, 16).width;
    final double timeAxisNameW = getTextSize(timeAxisName, 16).width;
    final double textX = width - (timeAxisNameW + _timeAxisNameXOffset);
    // print("width - (timeAxisNameW + _timeAxisNameXOffset) : $width - ($timeAxisNameW + $_timeAxisNameXOffset)");
    _drawText(canvas, timeAxisName, Offset(textX, timeAxisNameY), 14);
  }

  void _drawFrequencyAxis(Canvas canvas, Size size, double height, double scaleY) {
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;
    
    final path = Path();
    
    final bool isZoomed = scaleY < _freqAxisNotchZoomSwitchScale;
    final int notchCount = isZoomed ? _freqAxisNotchCount : _freqAxisNotchCountZoomed;
    final List<String> notchValues = isZoomed ? _freqAxisValues : _freqAxisValuesZoomed;

    double adjustedScaleY = scaleY;
    if (!isZoomed) {
      adjustedScaleY /= _freqAxisNotchZoomSwitchScale;
    }

    final double valueStep = height / (notchCount - 1) * adjustedScaleY;
    // final double textHeight = _buildParagraph('0', 16).height;
    final double textHeight = getTextSize("0", 12).height;
    // final double drawMarginYScaled = _axisValuesYDrawMargin + textHeight * 0.15 ;
    final double drawMarginYScaled = 0;

    // Draw notches
    for (int i = 0; i < notchCount; i++) {
      final double y = height - valueStep * i + drawMarginYScaled;
      if (y <= height) {
        double notchSize = _axisNotchSize1;
        if (i % 10 == 0) {
          notchSize = _axisNotchSize10;
        } else if (i % 5 == 0) {
          notchSize = _axisNotchSize5;
        }
        path.moveTo(0, y);
        path.lineTo(notchSize, y);
      }
    }
    canvas.drawPath(path, paint);

    // Draw scale values
    // final double freqAxisValuesXOffset = _axisNotchSize10 + _axisValueXOffset;
    double xMultiplier = 0.59;
    if (kIsWeb) {
      xMultiplier = 0.59;
    } else
    if (Platform.isAndroid || Platform.isIOS) {
      xMultiplier = 1.15;
    } else {
      xMultiplier = 0.59;
    }
    final double freqAxisValuesXOffset = -size.width * xMultiplier;
    for (int i = 0; i < notchValues.length; i++) {
      final double y = height - valueStep * i * 10 + drawMarginYScaled - textHeight / 2;
      if (y > drawMarginYScaled - textHeight && height - y > drawMarginYScaled) {
        _drawText(canvas, notchValues[i], Offset(freqAxisValuesXOffset, y), 12, align: TextAlign.center);
      }
    }
  }

  @override
  bool shouldRepaint(covariant FftPainter oldDelegate) {
    // Repaint only if the scale factors change.
    // return oldDelegate.fftData.scaleX != fftData.scaleX || oldDelegate.fftData.scaleY != fftData.scaleY;
    return true;
  }
}