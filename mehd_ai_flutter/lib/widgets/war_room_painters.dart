import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:mehd_ai_flutter/models/consensus_result.dart';

/// Procedural painters for War Room Screen.
/// NeuralConnectionPainter renders the glowing AI neural network lines.
/// RadarPainter renders the rotating sonar/radar sweep.

class NeuralConnectionPainter extends CustomPainter {
  final Animation<double> pulse;
  final Set<String> activeNodes;
  final Color baseColor;

  NeuralConnectionPainter({required this.pulse, required this.activeNodes, required this.baseColor}) : super(repaint: pulse);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = baseColor.withOpacity(0.2 + (pulse.value * 0.3))
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);
    final nodes = [
      Offset(center.dx, center.dy - 110),
      Offset(center.dx - 80, center.dy - 50),
      Offset(center.dx + 80, center.dy - 50),
      Offset(center.dx - 120, center.dy + 50),
      Offset(center.dx + 120, center.dy + 50),
      Offset(center.dx, center.dy - 20),
      Offset(center.dx - 80, center.dy + 150),
      Offset(center.dx, center.dy + 130),
      Offset(center.dx + 80, center.dy + 150),
    ];

    // Connect nodes to The Don (center offset 0, 45)
    final theDon = Offset(center.dx, center.dy + 45);
    
    for (var node in nodes) {
      canvas.drawLine(theDon, node, paint);
    }
  }

  @override
  bool shouldRepaint(NeuralConnectionPainter oldDelegate) => true;
}

class RadarPainter extends CustomPainter {
  final double angle;
  final double pulse;
  final ConsensusResult? consensus;
  final Color baseColor;

  RadarPainter({required this.angle, required this.pulse, this.consensus, required this.baseColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // ── Background fill ──
    canvas.drawCircle(
      center, radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.black.withOpacity(0.5),
            baseColor.withOpacity(0.04),
            Colors.black.withOpacity(0.85),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );

    // ── Subtle wireframe terrain grid ──
    final gridPaint = Paint()
      ..color = baseColor.withOpacity(0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (double i = 0; i < size.width; i += 22) {
      final path = Path()..moveTo(i, 0);
      for (double j = 0; j < size.height; j += 22) {
        path.quadraticBezierTo(i + 7 * math.sin(j / 40), j + 11, i, j + 22);
      }
      canvas.drawPath(path, gridPaint);
    }

    // ── Concentric rings ──
    final ringPaint = Paint()
      ..color = baseColor.withOpacity(0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final brightRingPaint = Paint()
      ..color = baseColor.withOpacity(0.65 + pulse * 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;

    canvas.drawCircle(center, radius * 0.95, brightRingPaint);
    canvas.drawCircle(center, radius * 0.70, ringPaint);
    canvas.drawCircle(center, radius * 0.46, ringPaint);
    canvas.drawCircle(center, radius * 0.23, ringPaint);

    // ── Crosshairs ──
    canvas.drawLine(Offset(center.dx, radius * 0.04), Offset(center.dx, size.height - radius * 0.04), ringPaint);
    canvas.drawLine(Offset(radius * 0.04, center.dy), Offset(size.width - radius * 0.04, center.dy), ringPaint);

    // ── Ring distance labels ──
    _label(canvas, '1KM', Offset(center.dx + radius * 0.23 + 3, center.dy + 3), baseColor, 7.5);
    _label(canvas, '2KM', Offset(center.dx + radius * 0.46 + 3, center.dy + 3), baseColor, 7.5);
    _label(canvas, '3KM', Offset(center.dx + radius * 0.70 + 3, center.dy + 3), baseColor, 7.5);
    _label(canvas, '4KM', Offset(center.dx + radius * 0.95 + 2, center.dy + 3), baseColor, 7.5);

    // ── Degree labels ──
    _label(canvas, '0°',   Offset(center.dx - 6,  3),                       baseColor, 7.5);
    _label(canvas, '90°',  Offset(size.width - 24, center.dy - 8),           baseColor, 7.5);
    _label(canvas, '180°', Offset(center.dx - 9,   size.height - 14),        baseColor, 7.5);
    _label(canvas, '270°', Offset(3,               center.dy - 8),           baseColor, 7.5);

    // ── Header / footer labels (all on canvas) ──
    _label(canvas, 'ACTIVE SCAN | 3D HUD',
        Offset(center.dx - 62, 5), Colors.white70, 8.5);
    _label(canvas, 'SYSTEM: READY | SENSORS: ONLINE',
        Offset(8, size.height - 14), baseColor.withOpacity(0.7), 7);
    _label(canvas, 'HDG: 047° | ALT: 210M',
        Offset(size.width - 108, size.height - 14), baseColor.withOpacity(0.7), 7);

    // ── Degree tick marks ──
    final tickPaint = Paint()
      ..color = baseColor.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (int i = 0; i < 360; i += 10) {
      final tickAngle = i * math.pi / 180;
      final isMajor = i % 30 == 0;
      final inner = isMajor ? radius * 0.91 : radius * 0.94;
      canvas.drawLine(
        Offset(center.dx + math.cos(tickAngle) * inner, center.dy + math.sin(tickAngle) * inner),
        Offset(center.dx + math.cos(tickAngle) * (radius * 0.96), center.dy + math.sin(tickAngle) * (radius * 0.96)),
        isMajor ? brightRingPaint : tickPaint,
      );
    }

    // ── Narrow sweep wedge ──
    canvas.drawCircle(
      center, radius * 0.95,
      Paint()
        ..shader = SweepGradient(
          center: Alignment.center,
          startAngle: 0.0,
          endAngle: math.pi / 5,
          colors: [
            baseColor.withOpacity(0.0),
            baseColor.withOpacity(0.18),
            baseColor.withOpacity(0.85),
          ],
          stops: const [0.0, 0.6, 1.0],
          transform: GradientRotation(angle - (math.pi / 5)),
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..style = PaintingStyle.fill,
    );

    // ── Leading edge bright line ──
    canvas.drawLine(
      center,
      Offset(center.dx + math.cos(angle) * radius * 0.95, center.dy + math.sin(angle) * radius * 0.95),
      Paint()
        ..color = baseColor
        ..strokeWidth = 4.0
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 3),
    );

    // ── Metallic hub (drawn entirely on canvas) ──
    final hubR = radius * 0.13;
    // Outer metallic ring
    canvas.drawCircle(center, hubR,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.5),
          colors: const [Color(0xFFCCCCCC), Color(0xFF333333)],
        ).createShader(Rect.fromCircle(center: center, radius: hubR))
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(center, hubR, Paint()..color = Colors.black..style = PaintingStyle.stroke..strokeWidth = 2);
    // Inner gloss
    canvas.drawCircle(center, hubR * 0.75,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: const [Color(0xFFEEEEEE), Color(0xFF555555)],
        ).createShader(Rect.fromCircle(center: center, radius: hubR * 0.75))
        ..style = PaintingStyle.fill,
    );
    // Glow on hub
    canvas.drawCircle(center, hubR * 0.6,
      Paint()
        ..color = baseColor.withOpacity(0.15 + pulse * 0.2)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    // Hub label
    _label(canvas, 'HUB', Offset(center.dx - 9, center.dy - 5), Colors.black87, 7);

    // ── Agent / target nodes ──
    final int activeCount = consensus?.votes.length ?? 0;
    final bracketPaint = Paint()
      ..color = baseColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (int i = 0; i < 11; i++) {
      final nodeAngle = (i * (math.pi * 2) / 11) - (math.pi / 2);
      final dist = i < activeCount ? radius * 0.62 : radius * 0.38;
      final alpha = i < activeCount ? 1.0 : 0.22;
      final nc = Offset(center.dx + math.cos(nodeAngle) * dist, center.dy + math.sin(nodeAngle) * dist);

      // Glow orb
      canvas.drawCircle(nc, 7.0,
        Paint()
          ..color = baseColor.withOpacity(alpha * 0.45)
          ..style = PaintingStyle.fill
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      // Solid core
      canvas.drawCircle(nc, 3.0,
        Paint()..color = Colors.white.withOpacity(alpha)..style = PaintingStyle.fill,
      );

      // Targeting brackets on every 3rd active node
      if (i < activeCount && i % 3 == 0) {
        const s = 11.0;
        canvas.drawLine(Offset(nc.dx - s, nc.dy - s), Offset(nc.dx - s + 5, nc.dy - s), bracketPaint);
        canvas.drawLine(Offset(nc.dx - s, nc.dy - s), Offset(nc.dx - s, nc.dy - s + 5), bracketPaint);
        canvas.drawLine(Offset(nc.dx + s, nc.dy + s), Offset(nc.dx + s - 5, nc.dy + s), bracketPaint);
        canvas.drawLine(Offset(nc.dx + s, nc.dy + s), Offset(nc.dx + s, nc.dy + s - 5), bracketPaint);
        _label(canvas, 'TGT-${String.fromCharCode(65 + i)} [${(dist / 45).toStringAsFixed(1)}KM]',
            Offset(nc.dx + s + 3, nc.dy - s), baseColor.withOpacity(0.85), 7);
      }
    }

    // ── Outer ring clip (hide anything drawn outside) ──
    final clipPath = Path()..addOval(Rect.fromCircle(center: center, radius: radius * 0.975));
    canvas.clipPath(clipPath);
  }

  void _label(Canvas canvas, String text, Offset offset, Color color, double fontSize) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: fontSize, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(RadarPainter oldDelegate) => true;
}
