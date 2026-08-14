import 'package:flutter/material.dart';

class MilestoneCardGridPainter extends CustomPainter {
  final Color color;

  MilestoneCardGridPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.04)
      ..strokeWidth = 0.8;

    const spacing = 24.0;
    for (double x = 0; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class MilestoneMarbleVeinsPainter extends CustomPainter {
  final Color color;

  MilestoneMarbleVeinsPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color.withOpacity(0.03)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final path = Path();
    path.moveTo(0, size.height * 0.2);
    path.cubicTo(
      size.width * 0.3, size.height * 0.1,
      size.width * 0.6, size.height * 0.4,
      size.width, size.height * 0.3,
    );
    path.moveTo(size.width * 0.1, size.height);
    path.cubicTo(
      size.width * 0.4, size.height * 0.7,
      size.width * 0.7, size.height * 0.9,
      size.width * 0.9, size.height * 0.5,
    );

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
