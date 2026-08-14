import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/widgets/techno_card.dart';

class CommandTabRiskRulesCard extends StatelessWidget {
  final double riskPct;
  final double stopLossPips;

  const CommandTabRiskRulesCard({
    super.key,
    required this.riskPct,
    required this.stopLossPips,
  });

  @override
  Widget build(BuildContext context) {
    return TechnoCard(
      borderColor: MehdAiTheme.gold.withOpacity(0.3),
      child: Column(
        children: [
          _buildRiskRuleRow('AUTO-KILL SWITCH', 'Freezes trading if daily drawdown hits ${(riskPct * 3).toStringAsFixed(1)}% (3× your risk/trade)', 'ARMED 🛡️', const Color(0xFF00FF88)),
          const Divider(color: MehdAiTheme.borderColor, height: 16),
          _buildRiskRuleRow('NEWS BLACKOUT SHIELD', 'Pauses execution 30 min before high-impact news (NFP / CPI / FOMC)', 'ACTIVE 📰', const Color(0xFF58A6FF)),
          const Divider(color: MehdAiTheme.borderColor, height: 16),
          _buildRiskRuleRow('SPREAD SPIKE GUARD', 'Rejects trade if broker spread exceeds ${(stopLossPips * 1.25).toStringAsFixed(1)} pips (125% of your SL)', 'ARMED 📏', MehdAiTheme.gold),
        ],
      ),
    );
  }

  Widget _buildRiskRuleRow(String name, String desc, String status, Color color) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: GoogleFonts.outfit(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(desc, style: GoogleFonts.inter(color: MehdAiTheme.textSecondary, fontSize: 10)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: color.withOpacity(0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Text(status, style: TextStyle(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
