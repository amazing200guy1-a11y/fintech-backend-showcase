import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/models/broker_model.dart';
import 'package:mehd_ai_flutter/widgets/subscription_tier_modal.dart';

class MultiBrokerDiagnosticCard extends StatelessWidget {
  final List<Broker> connectedBrokers;
  final Map<String, dynamic> fraudIndex;
  final VoidCallback onConnectTap;
  final Function(Broker flagged, Broker recommended) onMigrateTap;

  const MultiBrokerDiagnosticCard({
    super.key,
    required this.connectedBrokers,
    required this.fraudIndex,
    required this.onConnectTap,
    required this.onMigrateTap,
  });

  @override
  Widget build(BuildContext context) {
    final highRiskBrokers = connectedBrokers.where((b) => b.isHighRisk).toList();
    final cleanBrokers = connectedBrokers.where((b) => !b.isHighRisk).toList();

    if (connectedBrokers.isEmpty) {
      return _buildNoBrokersCard(context);
    } else if (highRiskBrokers.isEmpty) {
      return _buildAllCleanCard(context, cleanBrokers);
    } else if (highRiskBrokers.length == 1) {
      return _buildSingleRiskCard(context, highRiskBrokers.first);
    } else {
      return _buildMultiRiskCard(context, highRiskBrokers);
    }
  }

  Widget _buildNoBrokersCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.link_off_rounded, color: Colors.white54, size: 20),
              const SizedBox(width: 10),
              Text(
                'NO BROKER CONNECTED',
                style: GoogleFonts.orbitron(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Connect your trading account(s) to run automated B-Book fraud detection & latency audits.',
            style: GoogleFonts.inter(color: Colors.white60, fontSize: 11),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF58A6FF).withOpacity(0.2),
                side: const BorderSide(color: Color(0xFF58A6FF)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: onConnectTap,
              icon: const Icon(Icons.add_link_rounded, color: Colors.white, size: 18),
              label: Text(
                'CONNECT YOUR FIRST BROKER',
                style: GoogleFonts.orbitron(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAllCleanCard(BuildContext context, List<Broker> clean) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF091611),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF00FF88).withOpacity(0.5)),
        boxShadow: [
          BoxShadow(color: const Color(0xFF00FF88).withOpacity(0.1), blurRadius: 20),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_user_rounded, color: Color(0xFF00FF88), size: 22),
              const SizedBox(width: 10),
              Text(
                '100% ECN VERIFIED ENVIRONMENT',
                style: GoogleFonts.orbitron(color: const Color(0xFF00FF88), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'All ${clean.length} connected account(s) passed ECN execution audits with sub-1pip slippage and 0 manipulation flags.',
            style: GoogleFonts.inter(color: Colors.white70, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildSingleRiskCard(BuildContext context, Broker flagged) {
    final recommended = Broker.defaultBrokers.firstWhere((b) => b.id == 'pepperstone');

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1E100A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFF6B00).withOpacity(0.7), width: 1.5),
        boxShadow: [
          BoxShadow(color: const Color(0xFFFF6B00).withOpacity(0.15), blurRadius: 20),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFFFF6B00), size: 22),
              const SizedBox(width: 10),
              Text(
                '1 MANIPULATIVE BROKER DETECTED',
                style: GoogleFonts.orbitron(color: const Color(0xFFFF6B00), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '⚠️ ${flagged.name} is flagged for B-Book spread manipulation (${flagged.avgSlippage} pips slippage, ${flagged.executionLatency}ms latency).',
            style: GoogleFonts.inter(color: Colors.white, fontSize: 11),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF6B00).withOpacity(0.25),
                side: const BorderSide(color: Color(0xFFFF6B00)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => onMigrateTap(flagged, recommended),
              icon: const Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 18),
              label: Text(
                'REVIEW RISK & MIGRATE TO ${recommended.name.toUpperCase()}',
                style: GoogleFonts.orbitron(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMultiRiskCard(BuildContext context, List<Broker> highRisk) {
    final recommended = Broker.defaultBrokers.firstWhere((b) => b.id == 'icmarkets');
    final totalLoss = highRisk.fold<double>(0.0, (sum, b) => sum + b.estimatedMonthlySlippageCost(10.0));

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFF1F080A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFF3B3B), width: 1.5),
        boxShadow: [
          BoxShadow(color: const Color(0xFFFF3B3B).withOpacity(0.2), blurRadius: 24),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.gavel_rounded, color: Color(0xFFFF3B3B), size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'CRITICAL RISK: ${highRisk.length} FLAGGED BROKERS',
                  style: GoogleFonts.orbitron(color: const Color(0xFFFF3B3B), fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
                ),
              ),
              InkWell(
                onTap: () => SubscriptionTierModal.show(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: MehdAiTheme.gold.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: MehdAiTheme.gold),
                  ),
                  child: Text('\$299 SHIELD', style: GoogleFonts.orbitron(color: MehdAiTheme.gold, fontSize: 9, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '⛔ ${highRisk.length} of your connected accounts (${highRisk.map((b) => b.name).join(', ')}) are B-Book Market Makers. Estimated monthly slippage drain: \$${totalLoss.toStringAsFixed(0)}/mo.',
            style: GoogleFonts.inter(color: Colors.white, fontSize: 11),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF3B3B).withOpacity(0.3),
                side: const BorderSide(color: Color(0xFFFF3B3B)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => onMigrateTap(highRisk.first, recommended),
              icon: const Icon(Icons.shield_moon_rounded, color: Colors.white, size: 18),
              label: Text(
                'MIGRATE BOTH BROKERS TO ECN (\$299 STEALTH)',
                style: GoogleFonts.orbitron(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
