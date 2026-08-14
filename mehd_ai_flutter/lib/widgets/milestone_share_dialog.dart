import 'dart:ui' as ui;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:mehd_ai_flutter/utils/file_exporter.dart';
import 'package:mehd_ai_flutter/utils/native_share.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/widgets/milestone_cert_card.dart';
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
  Widget _buildBronzeCard() {
    return MilestoneCertCard(
      title: 'CAPITAL',
      subtitle: 'SURVIVED INTACT',
      accent: const Color(0xFFCD7F32),
      icon: Icons.shield_rounded,
      rank: 'BRONZE ALPHA CERTIFIED',
      date: 'PHASE 1  •  SURVIVAL & PRESERVATION',
      verificationId: 'WEEKS 1-4',
      metrics: const {
        'KILL SWITCH': 'NEVER FIRED',
        'DRAWDOWN HOLD': '< 3% MAX',
      },
    );
  }

  // ─── SILVER CERTIFICATE ───────────────────────────────────────────────────
  Widget _buildSilverCard() {
    return MilestoneCertCard(
      title: 'EDGE',
      subtitle: 'PATTERN CONFIRMED',
      accent: const Color(0xFFB0B3B8),
      icon: Icons.auto_graph_rounded,
      rank: 'SILVER EDGE CERTIFIED',
      date: 'PHASE 2  •  PATTERN RECOGNITION',
      verificationId: 'WEEKS 5-8',
      metrics: const {
        'AGENT CONSENSUS': '75%+ ALIGN',
        'BROKER TRUST': 'ZERO-TRUST OK',
      },
    );
  }

  // ─── GOLD CERTIFICATE ─────────────────────────────────────────────────────
  Widget _buildGoldCard() {
    return MilestoneCertCard(
      title: 'SOVEREIGN',
      subtitle: 'QUANT ESTABLISHED',
      accent: const Color(0xFFE5A93C),
      icon: Icons.workspace_premium_rounded,
      rank: 'GOLD ALPHA SOVEREIGN',
      date: 'PHASE 3-4  •  SOVEREIGN AUTONOMY',
      verificationId: 'WEEK 9+',
      metrics: const {
        '24/5 UPTIME': 'AUTONOMOUS',
        'CONSTITUTION': 'UPHELD',
      },
    );
  }
}

