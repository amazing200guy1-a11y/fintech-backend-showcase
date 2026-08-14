import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/widgets/subscription_tier_modal.dart';

class ProfitRotatorCard extends StatefulWidget {
  final List<Map<String, dynamic>> brokers;
  final double weeklyTargetUsd;
  final VoidCallback? onRotateTap;

  const ProfitRotatorCard({
    super.key,
    required this.brokers,
    this.weeklyTargetUsd = 5000.0,
    this.onRotateTap,
  });

  @override
  State<ProfitRotatorCard> createState() => _ProfitRotatorCardState();
}

class _ProfitRotatorCardState extends State<ProfitRotatorCard> with SingleTickerProviderStateMixin {
  late AnimationController _flipCtrl;
  late Animation<double> _flipAnim;
  bool _showBack = false;
  double _selectedTarget = 5000.0;
  bool _autoStealthEnabled = true;

  @override
  void initState() {
    super.initState();
    _selectedTarget = widget.weeklyTargetUsd;
    _flipCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _flipAnim = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _flipCtrl, curve: Curves.easeInOutBack),
    );
  }

  @override
  void dispose() {
    _flipCtrl.dispose();
    super.dispose();
  }

  void _toggleFlip() {
    if (_showBack) {
      _flipCtrl.reverse();
    } else {
      _flipCtrl.forward();
    }
    setState(() {
      _showBack = !_showBack;
    });
  }

  void _handleRotateTap() {
    _toggleFlip();
    if (widget.onRotateTap != null) {
      widget.onRotateTap!();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool hasRotationAlert = widget.brokers.any((b) => b['status'] == 'TARGET_REACHED');

    return AnimatedBuilder(
      animation: _flipAnim,
      builder: (context, child) {
        final angle = _flipAnim.value * math.pi;
        final isFrontVisible = angle < (math.pi / 2);

        return Transform(
          transform: Matrix4.identity()
            ..setEntry(3, 2, 0.001) // 3D Perspective
            ..rotateY(angle),
          alignment: Alignment.center,
          child: isFrontVisible
              ? _buildFrontCard(context, hasRotationAlert)
              : Transform(
                  transform: Matrix4.identity()..rotateY(math.pi),
                  alignment: Alignment.center,
                  child: _buildBackCard(context),
                ),
        );
      },
    );
  }

  Widget _buildFrontCard(BuildContext context, bool hasRotationAlert) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF090D16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: hasRotationAlert
              ? const Color(0xFFBC8CFF).withOpacity(0.6)
              : MehdAiTheme.gold.withOpacity(0.3),
          width: hasRotationAlert ? 1.5 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: hasRotationAlert
                ? const Color(0xFFBC8CFF).withOpacity(0.2)
                : MehdAiTheme.gold.withOpacity(0.08),
            blurRadius: 24,
            spreadRadius: -2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Row with $299 Tier Badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: hasRotationAlert
                      ? const Color(0xFFBC8CFF).withOpacity(0.2)
                      : MehdAiTheme.gold.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.radar_rounded,
                  color: hasRotationAlert ? const Color(0xFFBC8CFF) : MehdAiTheme.gold,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          'B-BOOK RADAR SHIELD',
                          style: GoogleFonts.orbitron(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: () => SubscriptionTierModal.show(context),
                          borderRadius: BorderRadius.circular(4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: MehdAiTheme.gold.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: MehdAiTheme.gold.withOpacity(0.5)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.star_rounded, color: MehdAiTheme.gold, size: 10),
                                const SizedBox(width: 3),
                                Text(
                                  '\$299/MO',
                                  style: GoogleFonts.orbitron(
                                    color: MehdAiTheme.gold,
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Prevents broker toxic flow flagging & trade size caps',
                      style: GoogleFonts.inter(color: MehdAiTheme.textSecondary, fontSize: 10),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.flip_camera_android_rounded, color: Colors.white54, size: 20),
                tooltip: 'Configure Rotation Rules',
                onPressed: _toggleFlip,
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Broker Allocations List
          ...widget.brokers.map((b) {
            final String name = b['broker'] ?? 'Broker Account';
            final double pnl = (b['weekly_pnl'] as num?)?.toDouble() ?? 0.0;
            final double target = (b['weekly_target'] as num?)?.toDouble() ?? _selectedTarget;
            final double pct = ((pnl / target).clamp(0.0, 1.0));
            final String status = b['status'] ?? 'STEALTH_ACTIVE';

            Color statusColor = MehdAiTheme.green;
            if (status == 'TARGET_REACHED') {
              statusColor = const Color(0xFFBC8CFF);
            } else if (status == 'STEALTH_WARNING') {
              statusColor = MehdAiTheme.gold;
            }

            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            status == 'TARGET_REACHED' ? Icons.check_circle_rounded : Icons.shield_rounded,
                            color: statusColor,
                            size: 14,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            name,
                            style: GoogleFonts.outfit(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      Text(
                        '\$${pnl.toStringAsFixed(0)} / \$${target.toStringAsFixed(0)}',
                        style: GoogleFonts.jetBrainsMono(color: statusColor, fontSize: 11, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: pct,
                      minHeight: 6,
                      backgroundColor: Colors.white10,
                      valueColor: AlwaysStoppedAnimation<Color>(statusColor),
                    ),
                  ),
                ],
              ),
            );
          }),

          const SizedBox(height: 8),

          // Action Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: hasRotationAlert
                    ? const Color(0xFFBC8CFF).withOpacity(0.25)
                    : MehdAiTheme.gold.withOpacity(0.15),
                side: BorderSide(
                  color: hasRotationAlert ? const Color(0xFFBC8CFF) : MehdAiTheme.gold.withOpacity(0.6),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: _handleRotateTap,
              icon: const Icon(Icons.sync_alt_rounded, color: Colors.white, size: 18),
              label: Text(
                hasRotationAlert ? 'ROTATE BROKER CAPITAL (ALERT)' : 'ROTATE BROKER CAPITAL (3D FLIP)',
                style: GoogleFonts.orbitron(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackCard(BuildContext context) {
    final targets = [2500.0, 5000.0, 10000.0, 25000.0];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MehdAiTheme.gold, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: MehdAiTheme.gold.withOpacity(0.2),
            blurRadius: 24,
            spreadRadius: -2,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.settings_suggest_rounded, color: MehdAiTheme.gold, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'STEALTH ROTATION CONFIG',
                    style: GoogleFonts.orbitron(
                      color: MehdAiTheme.gold,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 18),
                onPressed: _toggleFlip,
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Target Selector
          Text(
            'WEEKLY PROFIT CAP PER BROKER:',
            style: GoogleFonts.inter(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Row(
            children: targets.map((t) {
              final isSel = _selectedTarget == t;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 2),
                  child: InkWell(
                    onTap: () => setState(() => _selectedTarget = t),
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isSel ? MehdAiTheme.gold : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isSel ? MehdAiTheme.gold : Colors.white24,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          '\$${(t / 1000).toStringAsFixed(1)}K',
                          style: GoogleFonts.orbitron(
                            color: isSel ? Colors.black : Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),

          // Auto-Stealth Switch
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'INSTITUTIONAL AUTO-ROTATE',
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                  Text(
                    'Auto-switches capital on 80% cap reach',
                    style: GoogleFonts.inter(color: Colors.white54, fontSize: 9),
                  ),
                ],
              ),
              Switch(
                value: _autoStealthEnabled,
                activeColor: MehdAiTheme.gold,
                onChanged: (v) => setState(() => _autoStealthEnabled = v),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Confirm Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: MehdAiTheme.gold,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () {
                _toggleFlip();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  backgroundColor: const Color(0xFF0F172A),
                  content: Text(
                    '🛡️ Institutional rotation target set to \$${_selectedTarget.toStringAsFixed(0)}. Stealth active!',
                    style: const TextStyle(color: MehdAiTheme.gold),
                  ),
                ));
              },
              icon: const Icon(Icons.check_circle_rounded, size: 18),
              label: Text(
                'APPLY ROTATION SETTINGS',
                style: GoogleFonts.orbitron(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
