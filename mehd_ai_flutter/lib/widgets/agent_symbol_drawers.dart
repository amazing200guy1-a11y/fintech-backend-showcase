import 'dart:math';
import 'package:flutter/material.dart';

class AgentSymbolDrawers {
  static void drawPhantomRing(Canvas canvas, Offset c, double r, double a, [Color color = Colors.cyan, double pulse = 0.0]) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // Outer ring — dashed / dissolving effect
    for (int i = 0; i < 24; i++) {
      final angle = (i / 24) * 2 * pi + (pulse * 0.5);
      final opacity = (sin(angle * 3 + pulse * pi) * 0.5 + 0.5) * a;
      paint.color = color.withOpacity(opacity * 0.8);

      final p1 = Offset(
        c.dx + cos(angle) * r * 0.85,
        c.dy + sin(angle) * r * 0.85,
      );
      final p2 = Offset(
        c.dx + cos(angle) * r,
        c.dy + sin(angle) * r,
      );
      canvas.drawLine(p1, p2, paint);
    }

    // Inner ring — solid
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = color.withOpacity(0.3 * a + pulse * 0.2);
    canvas.drawCircle(c, r * 0.55, paint);

    // Center void dot
    paint
      ..style = PaintingStyle.fill
      ..color = color.withOpacity(0.15 * a + pulse * 0.1);
    canvas.drawCircle(c, r * 0.15, paint);

    // Center accent
    paint
      ..style = PaintingStyle.fill
      ..color = color.withOpacity(0.08 * a);
    canvas.drawCircle(c, r * 0.25, paint);
  }

  // ── ORACLE: Crystal prism eye ──
  static void drawOraclePrism(Canvas canvas, Offset c, double r, double a, [Color color = Colors.cyan, double pulse = 0.0]) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = color.withOpacity(0.8 * a);

    // Diamond/rhombus shape
    final path = Path()
      ..moveTo(c.dx, c.dy - r * 0.9)
      ..lineTo(c.dx + r * 0.6, c.dy)
      ..lineTo(c.dx, c.dy + r * 0.9)
      ..lineTo(c.dx - r * 0.6, c.dy)
      ..close();
    canvas.drawPath(path, paint);

    // Inner diamond
    paint.color = color.withOpacity(0.4 * a);
    final inner = Path()
      ..moveTo(c.dx, c.dy - r * 0.5)
      ..lineTo(c.dx + r * 0.35, c.dy)
      ..lineTo(c.dx, c.dy + r * 0.5)
      ..lineTo(c.dx - r * 0.35, c.dy)
      ..close();
    canvas.drawPath(inner, paint);

    // Central eye circle
    paint
      ..style = PaintingStyle.fill
      ..color = color.withOpacity(0.2 * a + pulse * 0.15);
    canvas.drawCircle(c, r * 0.15, paint);

    // Light refraction lines
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = color.withOpacity(0.25 * a);
    canvas.drawLine(
      Offset(c.dx - r * 0.6, c.dy),
      Offset(c.dx + r * 0.6, c.dy),
      paint,
    );
    canvas.drawLine(
      Offset(c.dx, c.dy - r * 0.9),
      Offset(c.dx, c.dy + r * 0.9),
      paint,
    );

    // Inner accent
    paint
      ..style = PaintingStyle.fill
      ..color = color.withOpacity(0.1 * a + pulse * 0.05);
    canvas.drawCircle(c, r * 0.2, paint);
  }

  // ── DON (Research): Crown circuit ──
  static void drawDonCrown(Canvas canvas, Offset c, double r, double a, [Color color = Colors.cyan, double pulse = 0.0]) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = color.withOpacity(0.8 * a);

    // Crown shape — 5 points
    final crown = Path();
    final baseY = c.dy + r * 0.3;
    final topY = c.dy - r * 0.6;
    final midY = c.dy - r * 0.1;

    crown.moveTo(c.dx - r * 0.8, baseY);
    crown.lineTo(c.dx - r * 0.6, topY);
    crown.lineTo(c.dx - r * 0.3, midY);
    crown.lineTo(c.dx, topY - r * 0.15);
    crown.lineTo(c.dx + r * 0.3, midY);
    crown.lineTo(c.dx + r * 0.6, topY);
    crown.lineTo(c.dx + r * 0.8, baseY);

    canvas.drawPath(crown, paint);

    // Base line
    canvas.drawLine(
      Offset(c.dx - r * 0.8, baseY),
      Offset(c.dx + r * 0.8, baseY),
      paint,
    );

    // Circuit nodes at crown tips
    paint
      ..style = PaintingStyle.fill
      ..color = color.withOpacity(0.5 * a + pulse * 0.3);
    canvas.drawCircle(Offset(c.dx - r * 0.6, topY), 2.5, paint);
    canvas.drawCircle(Offset(c.dx, topY - r * 0.15), 3, paint);
    canvas.drawCircle(Offset(c.dx + r * 0.6, topY), 2.5, paint);
  }

  // ── CAESAR: Imperial command sigil ──
  static void drawCaesarSigil(Canvas canvas, Offset c, double r, double a, [Color color = Colors.cyan, double pulse = 0.0]) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = color.withOpacity(0.8 * a);

    // Outer octagon
    final path = Path();
    for (int i = 0; i < 8; i++) {
      final angle = (i / 8) * 2 * pi - pi / 2;
      final x = c.dx + cos(angle) * r * 0.9;
      final y = c.dy + sin(angle) * r * 0.9;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);

    // Inner star cross — 4 lines through center
    paint.color = color.withOpacity(0.4 * a);
    for (int i = 0; i < 4; i++) {
      final angle = (i / 4) * pi;
      canvas.drawLine(
        Offset(c.dx + cos(angle) * r * 0.85, c.dy + sin(angle) * r * 0.85),
        Offset(c.dx - cos(angle) * r * 0.85, c.dy - sin(angle) * r * 0.85),
        paint,
      );
    }

    // Center command node
    paint
      ..style = PaintingStyle.fill
      ..color = color.withOpacity(0.3 * a + pulse * 0.2);
    canvas.drawCircle(c, r * 0.18, paint);

    // Command ring
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = color.withOpacity(0.5 * a + pulse * 0.2);
    canvas.drawCircle(c, r * 0.35, paint);
  }

  // ── SAGE: Nested wisdom sphere (icosahedron wireframe) ──
  static void drawSageSphere(Canvas canvas, Offset c, double r, double a, [Color color = Colors.cyan, double pulse = 0.0]) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color.withOpacity(0.6 * a);

    // Three concentric circles with slight rotation offset
    for (int layer = 0; layer < 3; layer++) {
      final layerR = r * (0.4 + layer * 0.25);
      paint.color = color.withOpacity((0.3 + layer * 0.15) * a);

      // Rotated hexagons to simulate 3D sphere
      final rotation = layer * (pi / 6) + pulse * 0.3;
      final hex = Path();
      for (int i = 0; i < 6; i++) {
        final angle = (i / 6) * 2 * pi + rotation;
        final x = c.dx + cos(angle) * layerR;
        final y = c.dy + sin(angle) * layerR * 0.7; // Perspective squash
        if (i == 0) {
          hex.moveTo(x, y);
        } else {
          hex.lineTo(x, y);
        }
      }
      hex.close();
      canvas.drawPath(hex, paint);
    }

    // Center dot
    paint
      ..style = PaintingStyle.fill
      ..color = color.withOpacity(0.4 * a + pulse * 0.2);
    canvas.drawCircle(c, 3, paint);
  }

  // ── GUARDIAN: Hexagonal shield matrix ──
  static void drawGuardianShield(Canvas canvas, Offset c, double r, double a, [Color color = Colors.cyan, double pulse = 0.0]) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = color.withOpacity(0.6 * a);

    // Main hexagon
    _drawHexagon(canvas, c, r * 0.9, paint);

    // Inner hexagon
    paint.color = color.withOpacity(0.35 * a);
    _drawHexagon(canvas, c, r * 0.55, paint);

    // Connecting lines from inner to outer vertices
    paint
      ..strokeWidth = 1.0
      ..color = color.withOpacity(0.2 * a);
    for (int i = 0; i < 6; i++) {
      final angle = (i / 6) * 2 * pi - pi / 2;
      final inner =
          Offset(c.dx + cos(angle) * r * 0.55, c.dy + sin(angle) * r * 0.55);
      final outer =
          Offset(c.dx + cos(angle) * r * 0.9, c.dy + sin(angle) * r * 0.9);
      canvas.drawLine(inner, outer, paint);
    }
  }

  static void _drawHexagon(Canvas canvas, Offset c, double r, Paint paint) {
    final path = Path();
    for (int i = 0; i < 6; i++) {
      final angle = (i / 6) * 2 * pi - pi / 2;
      final x = c.dx + cos(angle) * r;
      final y = c.dy + sin(angle) * r;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }
}
