import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mehd_ai_flutter/widgets/milestone_card_painters.dart';

class MilestoneCertCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Color accent;
  final IconData icon;
  final String rank;
  final String date;
  final String verificationId;
  final Map<String, dynamic>? metrics;

  const MilestoneCertCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.icon,
    required this.rank,
    required this.date,
    required this.verificationId,
    this.metrics,
  });

  @override
  Widget build(BuildContext context) {
    final statList = <_StatData>[];
    if (metrics != null) {
      metrics!.forEach((k, v) => statList.add(_StatData(k, v.toString())));
    }

    return _buildCertCard(
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [const Color(0xFF0F0B08), const Color(0xFF1E140E), accent.withOpacity(0.2)],
      ),
      borderColor: accent,
      glowColor: accent,
      stageLine: date,
      titleLine1: title,
      titleLine2: subtitle,
      accentColor: accent,
      badgeLabel: rank,
      stats: statList,
      badges: [verificationId],
      painter: MilestoneCardGridPainter(color: accent),
    );
  }

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
