import 'package:flutter/cupertino.dart';

class HumpCustomPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    Paint paint = Paint()
      ..color = const Color(0xFF1A1A1A) // Dark background color
      ..style = PaintingStyle.fill;

    Path path = Path();
    path.moveTo(0, 20); // Start slightly down from the top

    // Left side of the bar
    path.lineTo(size.width * 0.35, 20);

    // The Hump (using Cubic Bézier for smoothness)
    // Adjust these coordinates to change the steepness of the curve
    path.cubicTo(
      size.width * 0.40, 20, 
      size.width * 0.40, 0, 
      size.width * 0.50, 0,
    );
    path.cubicTo(
      size.width * 0.60, 0, 
      size.width * 0.60, 20, 
      size.width * 0.65, 20,
    );

    // Right side of the bar
    path.lineTo(size.width, 20);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}