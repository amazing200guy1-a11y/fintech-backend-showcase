import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/models/broker_model.dart';
import 'package:mehd_ai_flutter/widgets/subscription_tier_modal.dart';

class BrokerMigrationDialog extends StatelessWidget {
  final Broker flaggedBroker;
  final Broker recommendedBroker;
  final VoidCallback onMigrateConfirm;

  const BrokerMigrationDialog({
    super.key,
    required this.flaggedBroker,
    required this.recommendedBroker,
    required this.onMigrateConfirm,
  });

  static void show({
    required BuildContext context,
    required Broker flaggedBroker,
    required Broker recommendedBroker,
    required VoidCallback onMigrateConfirm,
  }) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => BrokerMigrationDialog(
        flaggedBroker: flaggedBroker,
        recommendedBroker: recommendedBroker,
        onMigrateConfirm: onMigrateConfirm,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final flaggedLoss = flaggedBroker.estimatedMonthlySlippageCost(10.0);
    final recommendedLoss = recommendedBroker.estimatedMonthlySlippageCost(10.0);
    final monthlySavings = (flaggedLoss - recommendedLoss).clamp(0.0, 10000.0);

    return Container(
      padding: const EdgeInsets.all(24),
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.9),
      decoration: const BoxDecoration(
        color: Color(0xFF0D1117),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(top: BorderSide(color: Color(0xFFFF3B3B), width: 1.5)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header Bar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3B3B).withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.gavel_rounded, color: Color(0xFFFF3B3B), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'MANIPULATION WARNING',
                        style: GoogleFonts.orbitron(
                          color: const Color(0xFFFF3B3B),
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.5,
                        ),
                      ),
                      Text(
                        'Community Fraud Intelligence Flag',
                        style: GoogleFonts.inter(color: Colors.white54, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.white54),
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Savings Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFD700).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.savings_rounded, color: Color(0xFFFFD700), size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'ESTIMATED SLIPPAGE DRAIN',
                        style: GoogleFonts.orbitron(
                          color: const Color(0xFFFFD700),
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Staying on ${flaggedBroker.name} costs you ~\$${monthlySavings.toStringAsFixed(0)}/mo in artificial spread markup.',
                        style: GoogleFonts.inter(color: Colors.white, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),

          // Side-by-Side Comparison
          Row(
            children: [
              // Left: Current Flagged Broker
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFF3B3B).withOpacity(0.5)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF3B3B).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'CURRENT BROKER',
                          style: GoogleFonts.orbitron(color: const Color(0xFFFF3B3B), fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        flaggedBroker.name,
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const Divider(color: Colors.white10, height: 16),
                      _buildMetricRow('Health Score', '${flaggedBroker.healthScore}/100', const Color(0xFFFF3B3B)),
                      _buildMetricRow('Avg Slippage', '${flaggedBroker.avgSlippage} pips', const Color(0xFFFF3B3B)),
                      _buildMetricRow('Latency', '${flaggedBroker.executionLatency} ms', const Color(0xFFFF3B3B)),
                      _buildMetricRow('Trust Tier', 'B-Book Maker', const Color(0xFFFF3B3B)),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Right: Recommended ECN Broker
              Expanded(
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.4),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF00FF88).withOpacity(0.6), width: 1.5),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00FF88).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'RECOMMENDED ECN',
                          style: GoogleFonts.orbitron(color: const Color(0xFF00FF88), fontSize: 9, fontWeight: FontWeight.bold),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        recommendedBroker.name,
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold),
                      ),
                      const Divider(color: Colors.white10, height: 16),
                      _buildMetricRow('Health Score', '${recommendedBroker.healthScore}/100', const Color(0xFF00FF88)),
                      _buildMetricRow('Avg Slippage', '${recommendedBroker.avgSlippage} pips', const Color(0xFF00FF88)),
                      _buildMetricRow('Latency', '${recommendedBroker.executionLatency} ms', const Color(0xFF00FF88)),
                      _buildMetricRow('Trust Tier', 'True ECN', const Color(0xFF00FF88)),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Action Buttons
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00FF88),
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                Navigator.pop(context);
                onMigrateConfirm();
              },
              icon: const Icon(Icons.swap_horiz_rounded, size: 20),
              label: Text(
                'SWITCH TO ${recommendedBroker.name.toUpperCase()} (VERIFIED ECN)',
                style: GoogleFonts.orbitron(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              onPressed: () {
                Navigator.pop(context);
                SubscriptionTierModal.show(context);
              },
              child: Text(
                'Learn more about \$299 Institutional ECN Audit Protections →',
                style: GoogleFonts.inter(color: MehdAiTheme.gold, fontSize: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricRow(String label, String val, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: GoogleFonts.inter(color: Colors.white54, fontSize: 10)),
          Text(val, style: GoogleFonts.jetBrainsMono(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
