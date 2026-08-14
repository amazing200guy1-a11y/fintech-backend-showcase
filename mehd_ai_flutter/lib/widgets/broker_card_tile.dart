import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mehd_ai_flutter/models/broker_model.dart';
import 'package:mehd_ai_flutter/widgets/techno_card.dart';

/// Glassmorphism card widget displaying individual broker health, latency, slippage & fraud stats.
class BrokerCardTile extends StatelessWidget {
  final Broker broker;
  final int healthScore;
  final String trustTierLabel;
  final int latency;
  final double slippage;
  final bool isFlagged;
  final Map<String, dynamic>? fraudData;
  final bool isConnected;
  final String connectedBrokerId;
  final VoidCallback onTap;

  const BrokerCardTile({
    super.key,
    required this.broker,
    required this.healthScore,
    required this.trustTierLabel,
    required this.latency,
    required this.slippage,
    required this.isFlagged,
    this.fraudData,
    required this.isConnected,
    required this.connectedBrokerId,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color scoreColor;
    if (healthScore >= 90) {
      scoreColor = const Color(0xFF00FF88);
    } else if (healthScore >= 70) {
      scoreColor = const Color(0xFFD29922);
    } else if (healthScore > 0) {
      scoreColor = const Color(0xFFFF3B3B);
    } else {
      scoreColor = const Color(0xFF555555);
    }

    return TechnoCard(
      padding: const EdgeInsets.all(22.0),
      borderColor: isFlagged
          ? const Color(0xFFFF3B3B)
          : (isConnected && connectedBrokerId == broker.id ? const Color(0xFF00FF88) : null),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Avatar Block
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            broker.color.withOpacity(0.3),
                            broker.color.withOpacity(0.1),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: broker.color.withOpacity(0.5), width: 1.2),
                      ),
                      child: Center(
                        child: Text(
                          broker.initials,
                          style: TextStyle(color: broker.color, fontWeight: FontWeight.bold, fontSize: 18),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          broker.name,
                          style: GoogleFonts.outfit(color: Colors.white, fontSize: 17, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: (healthScore >= 90
                                    ? const Color(0xFF00FF88)
                                    : (healthScore < 75 ? const Color(0xFFFF3B3B) : const Color(0xFF888888)))
                                .withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: (healthScore >= 90
                                        ? const Color(0xFF00FF88)
                                        : (healthScore < 75 ? const Color(0xFFFF3B3B) : const Color(0xFF888888)))
                                    .withOpacity(0.4)),
                          ),
                          child: Text(
                            trustTierLabel.toUpperCase(),
                            style: TextStyle(
                              color: healthScore >= 90
                                  ? const Color(0xFF00FF88)
                                  : (healthScore < 75 ? const Color(0xFFFF3B3B) : const Color(0xFFA1A1AA)),
                              fontSize: 9,
                              letterSpacing: 1,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                // Health Score Indicator
                if (healthScore > 0)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: scoreColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: scoreColor.withOpacity(0.4)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.shield, color: scoreColor, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          '$healthScore',
                          style: TextStyle(color: scoreColor, fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                      ],
                    ),
                  )
                else if (isConnected && connectedBrokerId == broker.id)
                  const Icon(Icons.check_circle, color: Color(0xFF00FF88), size: 28)
              ],
            ),
            const SizedBox(height: 20),

            if (healthScore > 0)
              Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildMicroStat('SPEED', '$latency ms', latency < 100 ? const Color(0xFF00FF88) : const Color(0xFFFF3B3B)),
                      _buildMicroStat('SLIPPAGE', '$slippage pips', slippage < 1.0 ? const Color(0xFF00FF88) : const Color(0xFFFF3B3B)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildMicroStat('HONESTY', '${broker.withdrawalHonesty}/100', broker.withdrawalHonesty >= 90 ? const Color(0xFF00FF88) : const Color(0xFFFF3B3B)),
                      _buildMicroStat('STABILITY', broker.spreadStability, (() {
                        final val = double.tryParse(broker.spreadStability.replaceAll('%', ''));
                        if (val == null) return const Color(0xFF888888);
                        return val >= 90 ? const Color(0xFF00FF88) : const Color(0xFFFF3B3B);
                      })()),
                    ],
                  ),
                  if (isFlagged && fraudData != null) ...[
                    const SizedBox(height: 14),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF3B3B).withOpacity(0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: const Color(0xFFFF3B3B).withOpacity(0.4)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.flag_rounded, color: Color(0xFFFF3B3B), size: 12),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${((fraudData!['withdrawal_reports'] as num? ?? 0).toInt() + (fraudData!['spread_reports'] as num? ?? 0).toInt())} REPORTS  •  ${((fraudData!['auto_latency_flags'] as num? ?? 0).toInt() + (fraudData!['auto_spread_flags'] as num? ?? 0).toInt())} AI FLAGS',
                              style: const TextStyle(color: Color(0xFFFF3B3B), fontSize: 9, letterSpacing: 0.5, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              )
            else
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFF58A6FF).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFF58A6FF).withOpacity(0.4)),
                ),
                child: const Center(
                  child: Text(
                    'CONNECT VIA API →',
                    style: TextStyle(color: Color(0xFF58A6FF), fontSize: 11, letterSpacing: 1.2, fontWeight: FontWeight.bold),
                  ),
                ),
              )
          ],
        ),
      ),
    );
  }

  Widget _buildMicroStat(String label, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: GoogleFonts.inter(color: const Color(0xFFA1A1AA), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
        const SizedBox(height: 3),
        Text(value, style: GoogleFonts.outfit(color: valueColor, fontSize: 15, fontWeight: FontWeight.w900)),
      ],
    );
  }
}
