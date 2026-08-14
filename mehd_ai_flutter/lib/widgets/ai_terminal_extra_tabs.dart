import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mehd_ai_flutter/core/api_service.dart';
import 'package:mehd_ai_flutter/models/account_health.dart';

class AiTerminalDenTab extends StatelessWidget {
  const AiTerminalDenTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildLayerBox('THE RESEARCH', 'Sift, Sentiment, Order Flow', 'Protects against retail crowding and sudden traps.', const Color(0xFFBC8CFF)),
          const SizedBox(height: 12),
          _buildLayerBox('THE STRATEGY', 'Pattern, Structure, Trend', 'Protects against trading against the primary institutional momentum.', const Color(0xFFFFD700)),
          const SizedBox(height: 12),
          _buildLayerBox('OLYMPUS', 'Math, Fractal, Volatility', 'Protects against low-probability mathematical environments.', const Color(0xFFFF9F43)),
        ],
      ),
    );
  }

  Widget _buildLayerBox(String title, String subtitle, String tooltip, Color accent) {
    return Tooltip(
      message: tooltip,
      textStyle: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 11),
      decoration: BoxDecoration(color: const Color(0xFF1A1A1A), border: Border.all(color: const Color(0xFF333333))),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF080808),
          border: Border.all(color: const Color(0xFF1A1A1A)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(width: 8, height: 8, color: accent),
                const SizedBox(width: 8),
                Text(title, style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: GoogleFonts.jetBrainsMono(color: const Color(0xFF8B949E), fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

class AiTerminalAccountTab extends StatelessWidget {
  const AiTerminalAccountTab({super.key});

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AccountHealth>(
      future: ApiService().getAccountHealth(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Color(0xFF58A6FF)));
        }
        
        final health = snapshot.data;
        final balance = health?.balance ?? 0.0;
        final equity = health?.equity ?? 0.0;
        final drawdown = health?.dailyDrawdownPct ?? 0.0;
        
        return Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildMetric('Balance', '\$${balance.toStringAsFixed(2)}', Colors.white),
              const SizedBox(height: 16),
              _buildMetric('Equity', '\$${equity.toStringAsFixed(2)}', Colors.white),
              const SizedBox(height: 32),
              _buildMetric('Daily Drawdown', '${drawdown.toStringAsFixed(2)}%', drawdown > 2.0 ? const Color(0xFFFF3B3B) : const Color(0xFF2EA043)),
              const SizedBox(height: 16),
              _buildMetric('Status', health?.isLocked == true ? 'LOCKED' : 'ACTIVE', health?.isLocked == true ? const Color(0xFFFF3B3B) : const Color(0xFF58A6FF)),
            ],
          ),
        );
      },
    );
  }

  Widget _buildMetric(String label, String value, Color valueColor) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: GoogleFonts.jetBrainsMono(color: const Color(0xFF8B949E), fontSize: 11)),
        Text(value, style: GoogleFonts.jetBrainsMono(color: valueColor, fontSize: 12, fontWeight: FontWeight.bold)),
      ],
    );
  }
}
