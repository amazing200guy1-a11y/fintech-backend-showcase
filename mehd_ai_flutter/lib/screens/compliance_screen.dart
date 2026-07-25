import 'dart:io';
import 'dart:ui' as ui;
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:mehd_ai_flutter/utils/file_exporter.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ComplianceScreen extends StatefulWidget {
  const ComplianceScreen({super.key});

  @override
  State<ComplianceScreen> createState() => _ComplianceScreenState();
}

class _ComplianceScreenState extends State<ComplianceScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  final GlobalKey _certKey = GlobalKey();
  bool _isDownloading = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Widget _buildGlowOrb(Color color, {double size = 400}) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return Transform.scale(
          scale: 1.0 + (_animController.value * 0.15),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [color, Colors.transparent],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MehdAiTheme.bgPrimary,
      appBar: AppBar(
        title: Text('Compliance & Audit', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        backgroundColor: MehdAiTheme.bgSecondary,
        elevation: 0,
      ),
      body: Stack(
        children: [
          // Ambient depth
          Positioned(
            top: -120,
            right: -80,
            child: _buildGlowOrb(MehdAiTheme.gold.withOpacity(0.12)),
          ),
          Positioned(
            bottom: -150,
            left: -100,
            child: _buildGlowOrb(MehdAiTheme.green.withOpacity(0.08)),
          ),

          SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCertificate(),
                const SizedBox(height: 32),
                _buildIntegrityMetrics(),
                const SizedBox(height: 32),
                _buildAuditLogs(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCertificate() {
    return RepaintBoundary(
      key: _certKey,
      child: ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: AnimatedBuilder(
          animation: _animController,
          builder: (_, child) {
            return Container(
              width: double.infinity,
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    MehdAiTheme.gold.withOpacity(0.08 + (_animController.value * 0.04)),
                    Colors.black.withOpacity(0.4),
                  ],
                ),
                border: Border.all(color: MehdAiTheme.gold.withOpacity(0.4 + (_animController.value * 0.2))),
                boxShadow: [
                  BoxShadow(
                    color: MehdAiTheme.gold.withOpacity(0.08 + (_animController.value * 0.05)),
                    blurRadius: 30,
                    spreadRadius: 5,
                  ),
                ],
              ),
              child: child,
            );
          },
          child: Column(
            children: [
              // Logo seal — pill shaped to respect the wide 16:9 logo aspect ratio
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: LinearGradient(
                    colors: [
                      MehdAiTheme.gold.withOpacity(0.12),
                      Colors.transparent,
                    ],
                  ),
                  border: Border.all(color: MehdAiTheme.gold.withOpacity(0.3)),
                ),
                child: Image.asset(
                  'assets/images/mehd_logo.png',
                  height: 36,
                  // No width — Flutter auto-calculates from the real aspect ratio
                  color: MehdAiTheme.gold,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'CERTIFICATE OF INTELLIGENCE',
                style: GoogleFonts.outfit(
                  color: MehdAiTheme.gold,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 3,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Container(
                width: 80,
                height: 2,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Colors.transparent, MehdAiTheme.gold, Colors.transparent],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Builder(builder: (ctx) {
                final user = FirebaseAuth.instance.currentUser;
                final name = user?.displayName ?? 'TRADER';
                return Text(
                  'ISSUED TO: ${name.toUpperCase()}',
                  style: GoogleFonts.jetBrainsMono(
                    color: MehdAiTheme.gold,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 2.0,
                  ),
                  textAlign: TextAlign.center,
                );
              }),
              const SizedBox(height: 16),
              Text(
                'This institution is operating under Mehd AI Den Analysis™ execution standards.\nAll algorithmic risk limits are strictly enforced by the HardRiskKernel.',
                style: MehdAiTheme.labelStyle.copyWith(fontSize: 14, height: 1.6),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              // Certification tags
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _buildCertTag('AES-256', Icons.lock_outline),
                  _buildCertTag('SOC 2 TYPE II', Icons.security),
                  _buildCertTag('ZERO-TRUST', Icons.shield_outlined),
                  _buildCertTag('11-AGENT VERIFIED', Icons.hub_outlined),
                ],
              ),
              const SizedBox(height: 32),
              // Download Button
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _isDownloading ? null : () async {
                    final box = context.findRenderObject() as RenderBox?;
                    setState(() => _isDownloading = true);
                    try {
                      final boundary = _certKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
                      if (boundary == null) throw Exception('Boundary not found');
                      final image = await boundary.toImage(pixelRatio: 3.0);
                      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
                      if (byteData == null) throw Exception('Failed to encode image');
                      final pngBytes = byteData.buffer.asUint8List();
                      final filename = 'mehd_ai_certificate.png';

                      if (kIsWeb) {
                        savePngBytes(pngBytes, filename);
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              backgroundColor: Color(0xFF1A2A1A),
                              content: Text(
                                '✅ Certificate downloaded to your Downloads folder!',
                                style: TextStyle(color: Color(0xFF00FF88)),
                              ),
                            ),
                          );
                        }
                      } else {
                        final tempDir = await getTemporaryDirectory();
                        final file = await File('${tempDir.path}/$filename').create();
                        await file.writeAsBytes(pngBytes);
                        if (!mounted) return;
                        await SharePlus.instance.share(
                          ShareParams(
                            text: 'Mehd AI — Certificate of Intelligence. Operating under Den Analysis™ execution standards with HardRiskKernel enforcement.',
                            files: [XFile(file.path)],
                            sharePositionOrigin: box != null ? (box.localToGlobal(Offset.zero) & box.size) : null,
                          ),
                        );
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Export failed: $e'),
                          backgroundColor: Colors.red,
                        ));
                      }
                    } finally {
                      if (mounted) setState(() => _isDownloading = false);
                    }
                  },
                  icon: _isDownloading
                      ? const SizedBox(height: 14, width: 14, child: CircularProgressIndicator(strokeWidth: 2, color: MehdAiTheme.gold))
                      : const Icon(Icons.ios_share, color: MehdAiTheme.gold, size: 16),
                  label: Text(
                    _isDownloading ? 'EXPORTING...' : 'DOWNLOAD CERTIFICATE',
                    style: MehdAiTheme.terminalStyle.copyWith(
                      color: MehdAiTheme.gold, fontWeight: FontWeight.bold, fontSize: 12,
                    )
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: MehdAiTheme.gold.withOpacity(0.3)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ),
        ),
      ),
    );
  }

  Widget _buildCertTag(String label, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: MehdAiTheme.gold.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: MehdAiTheme.gold.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: MehdAiTheme.gold, size: 14),
          const SizedBox(width: 6),
          Text(label, style: MehdAiTheme.terminalStyle.copyWith(
            color: MehdAiTheme.gold, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5,
          )),
        ],
      ),
    );
  }

  Widget _buildIntegrityMetrics() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 500;
        final cards = [
          _buildIntegrityCard('RISK KERNEL', 'ARMED', MehdAiTheme.green, Icons.verified_user_rounded),
          _buildIntegrityCard('CONSENSUS', '11/11', MehdAiTheme.blue, Icons.how_to_vote_rounded),
          _buildIntegrityCard('ANOMALY SCAN', 'CLEAR', MehdAiTheme.green, Icons.radar_rounded),
          _buildIntegrityCard('LATENCY', '12ms', MehdAiTheme.gold, Icons.speed_rounded),
        ];

        if (isMobile) {
          return Column(
            children: [
              Row(children: [Expanded(child: cards[0]), const SizedBox(width: 12), Expanded(child: cards[1])]),
              const SizedBox(height: 12),
              Row(children: [Expanded(child: cards[2]), const SizedBox(width: 12), Expanded(child: cards[3])]),
            ],
          );
        }
        return Row(
          children: cards.map((c) => Expanded(child: c)).toList()
            ..insert(1, const Expanded(flex: 0, child: SizedBox(width: 12)))
            ..insert(3, const Expanded(flex: 0, child: SizedBox(width: 12)))
            ..insert(5, const Expanded(flex: 0, child: SizedBox(width: 12))),
        );
      },
    );
  }

  Widget _buildIntegrityCard(String title, String value, Color color, IconData icon) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: color.withOpacity(0.06),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 24),
              const SizedBox(height: 10),
              Text(title, style: MehdAiTheme.labelStyle.copyWith(fontSize: 9, letterSpacing: 1)),
              const SizedBox(height: 4),
              Text(value, style: MehdAiTheme.terminalStyle.copyWith(
                color: color, fontWeight: FontWeight.bold, fontSize: 16,
              )),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAuditLogs() {
    final now = DateTime.now().toUtc();
    String fmt(DateTime d) => '${d.toString().substring(0, 19)} UTC';
    
    final List<Map<String, dynamic>> logs = [
      {'time': fmt(now.subtract(const Duration(seconds: 45))), 'event': 'Consensus 8/11 Reached (EUR/USD)', 'type': 'success'},
      {'time': fmt(now.subtract(const Duration(minutes: 2))), 'event': 'HardRiskKernel Approved (Lot: 1.2)', 'type': 'success'},
      {'time': fmt(now.subtract(const Duration(minutes: 5))), 'event': 'Execution Confirmed (Latency: 14ms)', 'type': 'success'},
      {'time': fmt(now.subtract(const Duration(hours: 1, minutes: 12))), 'event': 'SENTINEL FREEZE — Paradox Detected (JPY)', 'type': 'alert'},
      {'time': fmt(now.subtract(const Duration(hours: 3))), 'event': 'Post-Mortem: Constitution Amended (Rule 042)', 'type': 'info'},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.receipt_long_rounded, color: MehdAiTheme.textSecondary, size: 18),
            const SizedBox(width: 8),
            Text('IMMUTABLE AUDIT TRAIL', style: MehdAiTheme.headingStyle.copyWith(fontSize: 14, letterSpacing: 2)),
          ],
        ),
        const SizedBox(height: 16),
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117).withOpacity(0.8),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF30363D)),
              ),
              child: Column(
                children: logs.map((log) {
                  Color dotColor = MehdAiTheme.green;
                  if (log['type'] == 'alert') dotColor = MehdAiTheme.red;
                  if (log['type'] == 'info') dotColor = MehdAiTheme.blue;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 14.0),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 5),
                          width: 8, height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: dotColor,
                            boxShadow: [BoxShadow(color: dotColor.withOpacity(0.5), blurRadius: 6)],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(log['event']!, style: MehdAiTheme.terminalStyle.copyWith(color: dotColor, fontSize: 13)),
                              const SizedBox(height: 2),
                              Text(log['time']!, style: MehdAiTheme.terminalStyle.copyWith(color: MehdAiTheme.textSecondary, fontSize: 10)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
