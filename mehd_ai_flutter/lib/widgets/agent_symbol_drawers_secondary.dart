import 'dart:math';
import 'package:flutter/material.dart';

class AgentSymbolDrawersSecondary {
  // ── TITAN: Rotating wireframe data cube ──
  static void drawTitanCube(Canvas canvas, Offset c, double r, double a, [Color color = Colors.cyan, double pulse = 0.0]) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = color.withOpacity(0.6 * a);

    final s = r * 0.65;
    final angle = pulse * 0.4;

    // 3D cube vertices projected to 2D with slight rotation
    final cosA = cos(angle);
    final sinA = sin(angle);

    // Front face
    final List<Offset> front = [
      Offset(c.dx - s + sinA * s * 0.3, c.dy - s),
      Offset(c.dx + s + sinA * s * 0.3, c.dy - s),
      Offset(c.dx + s + sinA * s * 0.3, c.dy + s),
      Offset(c.dx - s + sinA * s * 0.3, c.dy + s),
    ];

    // Back face (offset for depth)
    final d = s * 0.4;
    final List<Offset> back = [
      Offset(front[0].dx + d * cosA, front[0].dy - d * 0.3),
      Offset(front[1].dx + d * cosA, front[1].dy - d * 0.3),
      Offset(front[2].dx + d * cosA, front[2].dy - d * 0.3),
      Offset(front[3].dx + d * cosA, front[3].dy - d * 0.3),
    ];

    // Draw back face (dimmer)
    paint.color = color.withOpacity(0.25 * a);
    for (int i = 0; i < 4; i++) {
      canvas.drawLine(back[i], back[(i + 1) % 4], paint);
    }

    // Draw connecting lines
    paint.color = color.withOpacity(0.35 * a);
    for (int i = 0; i < 4; i++) {
      canvas.drawLine(front[i], back[i], paint);
    }

    // Draw front face (brighter)
    paint.color = color.withOpacity(0.6 * a + pulse * 0.1);
    for (int i = 0; i < 4; i++) {
      canvas.drawLine(front[i], front[(i + 1) % 4], paint);
    }

    // Corner nodes
    paint
      ..style = PaintingStyle.fill
      ..color = color.withOpacity(0.5 * a + pulse * 0.2);
    for (final p in front) {
      canvas.drawCircle(p, 1.8, paint);
    }
  }

  // ── ATLAS: Quantum web — interconnected sphere ──
  static void drawAtlasWeb(Canvas canvas, Offset c, double r, double a, [Color color = Colors.cyan, double pulse = 0.0]) {

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = color.withOpacity(0.3 * a);

    final rng = Random(42); // Fixed seed for consistency
    final nodes = <Offset>[];

    // Generate nodes in a circular pattern
    for (int i = 0; i < 12; i++) {
      final angle = (i / 12) * 2 * pi;
      final dist = r * (0.4 + rng.nextDouble() * 0.5);
      nodes.add(Offset(
        c.dx + cos(angle) * dist,
        c.dy + sin(angle) * dist,
      ));
    }

    // Draw connections between nearby nodes
    for (int i = 0; i < nodes.length; i++) {
      for (int j = i + 1; j < nodes.length; j++) {
        final dist = (nodes[i] - nodes[j]).distance;
        if (dist < r * 1.2) {
          final opacity = (1.0 - dist / (r * 1.2)) * 0.4 * a;
          paint.color = color.withOpacity(opacity);
          canvas.drawLine(nodes[i], nodes[j], paint);
        }
      }
    }

    // Draw nodes
    paint
      ..style = PaintingStyle.fill
      ..color = color.withOpacity(0.5 * a + pulse * 0.2);
    for (final node in nodes) {
      canvas.drawCircle(node, 2, paint);
    }
  }

  // ── FORGE: Code anvil with binary streams ──
  static void drawForgeAnvil(Canvas canvas, Offset c, double r, double a, [Color color = Colors.cyan, double pulse = 0.0]) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = color.withOpacity(0.6 * a);

    // Anvil shape — simplified geometric
    final anvil = Path();
    // Top surface
    anvil.moveTo(c.dx - r * 0.5, c.dy - r * 0.2);
    anvil.lineTo(c.dx + r * 0.7, c.dy - r * 0.2);
    // Right horn
    anvil.lineTo(c.dx + r * 0.9, c.dy - r * 0.4);
    anvil.lineTo(c.dx + r * 0.9, c.dy - r * 0.1);
    anvil.lineTo(c.dx + r * 0.5, c.dy + r * 0.1);
    // Base
    anvil.lineTo(c.dx + r * 0.4, c.dy + r * 0.6);
    anvil.lineTo(c.dx - r * 0.4, c.dy + r * 0.6);
    anvil.lineTo(c.dx - r * 0.5, c.dy + r * 0.1);
    anvil.close();

    canvas.drawPath(anvil, paint);

    // Binary streams — falling particles
    paint
      ..style = PaintingStyle.fill
      ..color = color.withOpacity(0.35 * a);
    for (int i = 0; i < 5; i++) {
      final x = c.dx - r * 0.3 + i * r * 0.2;
      final yOff = (pulse * r * 2 + i * r * 0.5) % (r * 2) - r;
      final opacity = (1.0 - (yOff.abs() / r)) * 0.4 * a;
      if (opacity > 0) {
        paint.color = color.withOpacity(opacity);
        canvas.drawCircle(Offset(x, c.dy - r * 0.5 + yOff), 1.2, paint);
      }
    }
  }

  // ── THE DON (Supreme): Radiating polyhedron star ──
  static void drawSupremeStar(Canvas canvas, Offset c, double r, double a, [Color color = Colors.cyan, double pulse = 0.0]) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    // 8-pointed star
    final star = Path();
    for (int i = 0; i < 16; i++) {
      final angle = (i / 16) * 2 * pi - pi / 2;
      final dist = i.isEven ? r * 0.9 : r * 0.4;
      final x = c.dx + cos(angle) * dist;
      final y = c.dy + sin(angle) * dist;
      if (i == 0) {
        star.moveTo(x, y);
      } else {
        star.lineTo(x, y);
      }
    }
    star.close();

    paint.color = color.withOpacity(0.7 * a + pulse * 0.15);
    canvas.drawPath(star, paint);

    // Inner ring
    paint
      ..strokeWidth = 2.0
      ..color = color.withOpacity(0.5 * a + pulse * 0.2);
    canvas.drawCircle(c, r * 0.3, paint);

    // Center blazing dot
    paint
      ..style = PaintingStyle.fill
      ..color = color.withOpacity(0.6 * a + pulse * 0.3);
    canvas.drawCircle(c, r * 0.1, paint);
  }

  // ── SENTINEL: Scanning paradox eye ──
  static void drawSentinelEye(Canvas canvas, Offset c, double r, double a, [Color color = Colors.cyan, double pulse = 0.0]) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = color.withOpacity(0.6 * a);

    // Eye outline — two curved arcs
    final eye = Path();
    eye.moveTo(c.dx - r * 0.95, c.dy);
    eye.quadraticBezierTo(c.dx, c.dy - r * 0.8, c.dx + r * 0.95, c.dy);
    canvas.drawPath(eye, paint);

    final eyeBottom = Path();
    eyeBottom.moveTo(c.dx - r * 0.95, c.dy);
    eyeBottom.quadraticBezierTo(c.dx, c.dy + r * 0.8, c.dx + r * 0.95, c.dy);
    canvas.drawPath(eyeBottom, paint);

    // Iris circle
    paint
      ..strokeWidth = 1.5
      ..color = color.withOpacity(0.5 * a + pulse * 0.2);
    canvas.drawCircle(c, r * 0.35, paint);

    // Pupil
    paint
      ..style = PaintingStyle.fill
      ..color = color.withOpacity(0.4 * a + pulse * 0.25);
    canvas.drawCircle(c, r * 0.15, paint);

    // Scanning beam — horizontal line pulsing
    paint
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color.withOpacity(0.3 * a * pulse);
    final scanY = c.dy + (pulse - 0.5) * r * 0.6;
    canvas.drawLine(
      Offset(c.dx - r * 0.8, scanY),
      Offset(c.dx + r * 0.8, scanY),
      paint,
    );
  }

  // ── Default fallback ──
  static void drawDefaultSymbol(Canvas canvas, Offset c, double r, double a, [Color color = Colors.cyan]) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = color.withOpacity(0.5 * a);
    canvas.drawCircle(c, r * 0.7, paint);
    paint
      ..style = PaintingStyle.fill
      ..color = color.withOpacity(0.2 * a);
    canvas.drawCircle(c, r * 0.2, paint);
  }
}
