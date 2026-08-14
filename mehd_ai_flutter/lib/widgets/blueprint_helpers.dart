import 'dart:math' as math;
import 'package:flutter/material.dart';

class BlueprintCategory {
  final String title;
  final String description;
  final Color color;
  final List<BlueprintNode> nodes;

  BlueprintCategory(
      {required this.title,
      required this.description,
      required this.color,
      required this.nodes});
}

class BlueprintNode {
  final String id;
  final String title;
  final String subtitle;
  final String description;
  final IconData icon;
  final Color color;
  final Widget Function(BuildContext)? routeBuilder;

  BlueprintNode(
      {required this.id,
      required this.title,
      required this.subtitle,
      required this.description,
      required this.icon,
      required this.color,
      this.routeBuilder});
}

// Hacker Style Typewriter Animation Widget
class TypewriterText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Duration typingSpeed;

  const TypewriterText(
      {super.key,
      required this.text,
      required this.style,
      this.typingSpeed = const Duration(milliseconds: 20)});

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText> {
  String _displayedText = "";
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _startTyping();
  }

  void _startTyping() async {
    while (_currentIndex < widget.text.length) {
      if (!mounted) return;
      await Future.delayed(widget.typingSpeed);
      setState(() {
        int charsToAdd = 4;
        if (_currentIndex + charsToAdd > widget.text.length) {
          charsToAdd = widget.text.length - _currentIndex;
        }
        _displayedText +=
            widget.text.substring(_currentIndex, _currentIndex + charsToAdd);
        _currentIndex += charsToAdd;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Text(_displayedText, style: widget.style);
  }
}

// Background Blueprint Grid
class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.015)
      ..strokeWidth = 1.0;

    double gridSpace = 60.0;
    for (double i = 0; i < size.width; i += gridSpace) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += gridSpace) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class DataParticle {
  final double startX;
  final double startY;
  final double vx;
  final double vy;
  final double size;
  final double blinkOffset;
  final Color color;

  DataParticle(
      {required this.startX,
      required this.startY,
      required this.vx,
      required this.vy,
      required this.size,
      required this.blinkOffset,
      required this.color});
}

// Sparkles / Galaxy Stars Background Animation
class CyberStarsPainter extends CustomPainter {
  final List<DataParticle> particles;
  final Animation<double> pulse;
  final Animation<double> drift;

  CyberStarsPainter(
      {required this.particles, required this.pulse, required this.drift})
      : super(repaint: Listenable.merge([pulse, drift]));

  @override
  void paint(Canvas canvas, Size size) {
    // Only particles are drawn here in this top layer!

    for (var p in particles) {
      double baseX = p.startX + (p.vx * drift.value);
      double baseY = p.startY + (p.vy * drift.value);
      double swirlX =
          math.sin((drift.value * 20 * math.pi) + (p.blinkOffset * 20)) *
              (p.size * 30);
      double swirlY =
          math.cos((drift.value * 15 * math.pi) + (p.blinkOffset * 20)) *
              (p.size * 30);

      double currentX = (baseX + swirlX) % size.width;
      double currentY = (baseY + swirlY) % size.height;

      if (currentX < 0) currentX += size.width;
      if (currentY < 0) currentY += size.height;

      double blink = (pulse.value + p.blinkOffset) % 1.0;
      double opacity = (blink > 0.5 ? 1.0 - blink : blink) * 2.0;

      final paint = Paint()
        ..color = p.color.withOpacity(opacity * 0.8)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.size * 2);

      canvas.drawCircle(Offset(currentX, currentY), p.size + 1.0, paint);

      final corePaint = Paint()..color = Colors.white.withOpacity(opacity);
      canvas.drawCircle(Offset(currentX, currentY), p.size / 1.5, corePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
