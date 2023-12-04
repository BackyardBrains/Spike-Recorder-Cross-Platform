import 'package:flutter/material.dart';

class DropletPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    var paint = Paint()
      ..color = Colors.green
      ..style = PaintingStyle.fill;

    var path = Path();
    path.moveTo(0, size.height * 0.5); // Start from the middle left
    path.quadraticBezierTo(
        size.width * 0.2,
        size.height * 1.4, // Curve outward to the bottom
        size.width,
        size.height * 0.5); // Pointed edge to the right
    path.quadraticBezierTo(
        size.width * 0.2,
        size.height * -0.4, // Curve inward to the top
        0,
        size.height * 0.5); // Back to start

    path.close();

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) {
    return false;
  }
}
