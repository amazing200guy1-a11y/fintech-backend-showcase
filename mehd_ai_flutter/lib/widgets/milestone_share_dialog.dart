import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mehd_ai_flutter/utils/file_exporter.dart';
import 'package:mehd_ai_flutter/utils/native_share.dart';
import 'package:mehd_ai_flutter/core/theme.dart';

class MilestoneShareDialog extends StatefulWidget {
  final int initialStage; // 1, 2, or 3
  final int protectionScore;

  const MilestoneShareDialog({
    super.key,
    this.initialStage = 1,
    this.protectionScore = 92,
  });

  @override
  State<MilestoneShareDialog> createState() => _MilestoneShareDialogState();
}

class _MilestoneShareDialogState extends State<MilestoneShareDialog> {
  late int _selectedStage;
  final GlobalKey _globalKey = GlobalKey();
  bool _isSharing = false;

  @override
  void initState() {
    super.initState();
    _selectedStage = widget.initialStage.clamp(1, 3);
  }

  Future<void> _shareCard() async {
    if (_isSharing) return;
    setState(() => _isSharing = true);

    try {
      // 1. Capture the card widget as a high-res PNG
      final boundary = _globalKey.currentContext?.findRenderObject()
          as RenderRepaintBoundary?;
      if (boundary == null) throw Exception('Repaint boundary not found');

      final image = await boundary.toImage(pixelRatio: 3.0);
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      if (byteData == null) throw Exception('Failed to encode PNG');
      final pngBytes = byteData.buffer.asUint8List();
      final filename = 'mehd_milestone_stage$_selectedStage.png';

      if (kIsWeb) {
        // 2a. Web — trigger browser download via dart:html Blob
        savePngBytes(pngBytes, filename);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Color(0xFF1A2A1A),
              content: Text(
                '✅ Card downloaded to your Downloads folder!',
                style: TextStyle(color: Color(0xFF00FF88)),
              ),
            ),
          );
        }
      } else {
        // 2b. Native (Android/iOS) — save to temp dir and share via share_plus
        await nativeSharePng(
            pngBytes, filename, _selectedStage, widget.protectionScore);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.red,
            content: Text('Failed to generate card: $e',
                style: const TextStyle(fontFamily: 'JetBrains Mono')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 420),
        decoration: BoxDecoration(
          color: const Color(0xFF0A0A0A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(0.08)),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'SHARE MILESTONE',
                    style: MehdAiTheme.headingStyle.copyWith(fontSize: 14, letterSpacing: 1.5),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white60, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  )
                ],
              ),
            ),

            // Tab Selectors for Card Themes
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _buildThemeButton(1, 'BRONZE', const Color(0xFFCD7F32)),
                  const SizedBox(width: 8),
                  _buildThemeButton(2, 'SILVER', const Color(0xFFCCCCCC)),
                  const SizedBox(width: 8),
                  _buildThemeButton(3, 'GOLD', const Color(0xFFFFD700)),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // RepaintBoundary wrapping the preview card itself
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: RepaintBoundary(
                key: _globalKey,
                child: _buildMilestoneCardPreview(),
              ),
            ),
            const SizedBox(height: 24),

            // Action Button
            Padding(
              padding: const EdgeInsets.only(left: 20, right: 20, bottom: 24),
              child: SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _getPrimaryColor().withOpacity(0.12),
                    foregroundColor: _getPrimaryColor(),
                    side: BorderSide(color: _getPrimaryColor()),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: _isSharing ? null : _shareCard,
                  child: _isSharing
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: const [
                              Icon(Icons.ios_share, size: 16),
                              SizedBox(width: 8),
                              Text(
                                'EXPORT & SHARE CARD',
                                style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5),
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildThemeButton(int stage, String label, Color color) {
    final isSelected = _selectedStage == stage;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedStage = stage),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.1) : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected ? color : Colors.white.withOpacity(0.1),
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                color: isSelected ? color : Colors.grey[600],
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _getPrimaryColor() {
    switch (_selectedStage) {
      case 1:
        return const Color(0xFFCD7F32); // Bronze
      case 2:
        return const Color(0xFFC0C0C0); // Silver
      case 3:
        return const Color(0xFFFFD700); // Gold
      default:
        return Colors.blue;
    }
  }

  Widget _buildMilestoneCardPreview() {
    switch (_selectedStage) {
      case 1:
        return _buildBronzeCard();
      case 2:
        return _buildSilverCard();
      case 3:
        return _buildGoldCard();
      default:
        return _buildBronzeCard();
    }
  }

  // ─── BRONZE CERTIFICATE ───────────────────────────────────────────────────
  // Phase 1: Survival & Preservation (Weeks 1-4)
  // Trader has survived the first 4 weeks. HardRiskKernel protected capital.
  // Zero blow-ups. Daily drawdown never exceeded. Kill-switch never fired.
  Widget _buildBronzeCard() {
    const accent = Color(0xFFCD7F32); // Bronze
    const bg1 = Color(0xFF0F0B08); // Deep obsidian espresso
    const bg2 = Color(0xFF1E140E); // Rich mahogany bronze
    return _buildCertCard(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [bg1, bg2, Color(0xFF191009)],
      ),
      borderColor: accent,
      glowColor: accent,
      stageLine: 'PHASE 1  •  SURVIVAL & PRESERVATION',
      titleLine1: 'CAPITAL',
      titleLine2: 'SURVIVED INTACT',
      accentColor: accent,
      badgeLabel: 'BRONZE ALPHA CERTIFIED',
      stats: [
        _StatData('WEEKS ACTIVE', 'WEEKS 1-4'),
        _StatData('KILL SWITCH', 'NEVER FIRED'),
        _StatData('DRAWDOWN HOLD', '< 3% MAX'),
      ],
      badges: const ['RISK KERNEL ACTIVE', '24/5 GUARD', 'CAPITAL PRESERVED'],
      painter: _CardGridPainter(accent.withOpacity(0.045)),
    );
  }

  // ─── SILVER CERTIFICATE ───────────────────────────────────────────────────
  // Phase 2: Pattern Recognition (Weeks 5-8)
  // The Den identified the trader's winning edge. 11 agents reached consistent
  // consensus. Broker slippage verified and trusted. Execution engine confirmed.
  Widget _buildSilverCard() {
    const accent = Color(0xFFB0B3B8); // Platinum Silver
    const bg1 = Color(0xFF0C0D0F); // Sleek charcoal obsidian
    const bg2 = Color(0xFF1A1C20); // Gunmetal steel
    return _buildCertCard(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [bg1, bg2, Color(0xFF15171B)],
      ),
      borderColor: accent,
      glowColor: accent,
      stageLine: 'PHASE 2  •  PATTERN RECOGNITION',
      titleLine1: 'EDGE',
      titleLine2: 'PATTERN CONFIRMED',
      accentColor: accent,
      badgeLabel: 'SILVER EDGE CERTIFIED',
      stats: [
        _StatData('AGENT CONSENSUS', '75%+ ALIGN'),
        _StatData('WEEKS ACTIVE', 'WEEKS 5-8'),
        _StatData('BROKER TRUST', 'ZERO-TRUST OK'),
      ],
      badges: const ['11-AGENT VERIFIED', 'EDGE CONFIRMED', 'ECN CLEARED'],
      painter: _CardGridPainter(accent.withOpacity(0.04)),
    );
  }

  // ─── GOLD CERTIFICATE ─────────────────────────────────────────────────────
  // Phase 3-4: Execution Edge → Unconscious Competence (Weeks 9-24)
  // The Den is now compounding autonomously. The trader has proven consistent
  // institutional discipline. 24/5 execution runs without manual intervention.
  Widget _buildGoldCard() {
    const accent = Color(0xFFE5A93C); // Polished Gold
    const bg1 = Color(0xFF0A0802); // Imperial black gold
    const bg2 = Color(0xFF1F1807); // Sovereign gold-leaf
    return _buildCertCard(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [bg1, bg2, Color(0xFF191305)],
      ),
      borderColor: accent,
      glowColor: accent,
      stageLine: 'PHASE 3-4  •  SOVEREIGN AUTONOMY',
      titleLine1: 'SOVEREIGN',
      titleLine2: 'QUANT ESTABLISHED',
      accentColor: accent,
      badgeLabel: 'GOLD ALPHA SOVEREIGN',
      stats: [
        _StatData('24/5 UPTIME', 'AUTONOMOUS'),
        _StatData('WEEKS ACTIVE', 'WEEK 9+'),
        _StatData('CONSTITUTION', 'UPHELD'),
      ],
      badges: const ['11-AGENT SOVEREIGN', 'CONSTITUTION OK', 'ZERO MANUAL TRADES'],
      painter: _MarbleVeinsPainter(),
    );
  }

  // ─── SHARED CERTIFICATE BUILDER ───────────────────────────────────────────
  Widget _buildCertCard({
    required LinearGradient gradient,
    required Color borderColor,
    required Color glowColor,
    required String stageLine,
    required String titleLine1,
    required String titleLine2,
    required Color accentColor,
    required String badgeLabel,
    required List<_StatData> stats,
    required List<String> badges,
    required CustomPainter painter,
  }) {
    return Container(
      width: double.infinity,
      height: 420, // Taller card for breathing room
      decoration: BoxDecoration(
        gradient: gradient,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor, width: 2.0), // Full opacity, bolder border
        boxShadow: [
          BoxShadow(
            color: glowColor.withOpacity(0.22), // Stronger outer glow
            blurRadius: 40,
            spreadRadius: 4,
          ),
          BoxShadow(
            color: glowColor.withOpacity(0.08),
            blurRadius: 80,
            spreadRadius: 12,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(21),
        child: Stack(
          children: [
            // Subtle background texture
            Positioned.fill(
              child: CustomPaint(painter: painter),
            ),

            // Large radial spotlight — lights up the center dramatically
            Positioned.fill(
              child: Center(
                child: Container(
                  width: 340,
                  height: 340,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        accentColor.withOpacity(0.14),
                        accentColor.withOpacity(0.04),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.5, 1.0],
                    ),
                  ),
                ),
              ),
            ),

            // TIGER — Bold, wide, dominant, clearly visible watermark
            Positioned.fill(
              child: Center(
                child: Opacity(
                  opacity: 0.26, // Bold presence without drowning the text
                  child: Image.asset(
                    'assets/images/mehd_logo.png',
                    width: 275, // Wide, fills the card center with authority
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),

            // Content
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // ── TOP: Stage badge + domain ─────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color: accentColor.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(5),
                            border: Border.all(color: accentColor.withOpacity(0.65), width: 1.2),
                          ),
                          child: Text(
                            badgeLabel,
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 8.5,
                              color: accentColor,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                        Text(
                          'mehd.ai',
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 10,
                            color: accentColor.withOpacity(0.7),
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),

                    // ── TITLE group ──────────────────────────────────────────
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          stageLine,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 9.5,
                            color: accentColor.withOpacity(0.75),
                            letterSpacing: 2.5,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          titleLine1,
                          style: GoogleFonts.orbitron(
                            fontSize: 32, // Big, punchy headline
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 3,
                            shadows: [
                              Shadow(
                                color: Colors.white.withOpacity(0.15),
                                blurRadius: 12,
                              )
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          titleLine2,
                          style: GoogleFonts.orbitron(
                            fontSize: 16,
                            color: accentColor,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 10),
                        Builder(builder: (ctx) {
                          final user = FirebaseAuth.instance.currentUser;
                          final name = user?.displayName ?? 'TRADER';
                          return Text(
                            'OPERATOR: ${name.toUpperCase()}',
                            style: GoogleFonts.jetBrainsMono(
                              fontSize: 10,
                              color: Colors.white70,
                              letterSpacing: 2.0,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          );
                        }),
                      ],
                    ),


                    // ── STATS ROW ────────────────────────────────────────────
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          height: 1,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [
                              Colors.transparent,
                              accentColor.withOpacity(0.4),
                              Colors.transparent,
                            ]),
                          ),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: stats
                              .map((s) => Expanded(
                                    child: _buildCertStat(s.label, s.value, accentColor),
                                  ))
                              .toList(),
                        ),
                        const SizedBox(height: 14),
                        Container(
                          height: 1,
                          decoration: BoxDecoration(
                            gradient: LinearGradient(colors: [
                              Colors.transparent,
                              accentColor.withOpacity(0.35),
                              Colors.transparent,
                            ]),
                          ),
                        ),
                      ],
                    ),

                    // ── BADGES ROW ───────────────────────────────────────────
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      alignment: WrapAlignment.center,
                      children: badges
                          .map((b) => Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                decoration: BoxDecoration(
                                  color: accentColor.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: accentColor.withOpacity(0.45), width: 1.0),
                                ),
                                child: Text(
                                  b,
                                  style: GoogleFonts.jetBrainsMono(
                                    fontSize: 8,
                                    color: accentColor,
                                    letterSpacing: 1.0,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildCertStat(String label, String value, Color accent) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: GoogleFonts.orbitron(
                fontSize: 15, // Bigger stat values
                color: Colors.white,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 7.5,
                color: accent.withOpacity(0.75),
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildStatCol(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: GoogleFonts.jetBrainsMono(
                fontSize: 7.5, color: Colors.white38, letterSpacing: 1)),
        const SizedBox(height: 4),
        Text(value,
            style: GoogleFonts.jetBrainsMono(
                fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
      ],
    );
  }
}

class _StatData {
  final String label;
  final String value;
  const _StatData(this.label, this.value);
}

// Custom Painter to render grid lines on the Bronze and Silver cards
class _CardGridPainter extends CustomPainter {
  final Color lineColor;
  _CardGridPainter(this.lineColor);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = lineColor
      ..strokeWidth = 0.5
      ..style = PaintingStyle.stroke;

    const spacing = 20.0;
    for (double i = 0; i < size.width; i += spacing) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double j = 0; j < size.height; j += spacing) {
      canvas.drawLine(Offset(0, j), Offset(size.width, j), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Custom Painter to draw gold marble vein lines on the Gold card
class _MarbleVeinsPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const ui.Color(0xFFFFD700).withOpacity(0.04)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final path1 = Path();
    path1.moveTo(0, size.height * 0.2);
    path1.quadraticBezierTo(size.width * 0.3, size.height * 0.15, size.width * 0.5, size.height * 0.45);
    path1.quadraticBezierTo(size.width * 0.7, size.height * 0.75, size.width, size.height * 0.6);
    canvas.drawPath(path1, paint);

    final path2 = Path();
    path2.moveTo(size.width * 0.2, size.height);
    path2.quadraticBezierTo(size.width * 0.4, size.height * 0.6, size.width * 0.7, size.height * 0.5);
    path2.quadraticBezierTo(size.width * 0.85, size.height * 0.4, size.width, size.height * 0.1);
    canvas.drawPath(path2, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
