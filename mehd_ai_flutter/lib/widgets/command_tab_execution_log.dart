import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/controllers/trading_controller.dart';

class CommandTabExecutionLog extends StatelessWidget {
  final TradingController trading;

  const CommandTabExecutionLog({super.key, required this.trading});

  @override
  Widget build(BuildContext context) {
    final history = trading.recentTrades;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MehdAiTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.history_rounded, color: MehdAiTheme.blue, size: 18),
              const SizedBox(width: 8),
              Text('EXECUTION LOG', style: GoogleFonts.orbitron(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            ],
          ),
          const SizedBox(height: 12),
          if (history.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(child: Text('No trades executed yet', style: TextStyle(color: Colors.white38, fontSize: 12))),
            )
          else
            ...history.take(5).map((t) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${t.direction} ${t.symbol}', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                      Text('\$${t.pnl.toStringAsFixed(2)}', style: TextStyle(color: t.pnl >= 0 ? const Color(0xFF00FF88) : const Color(0xFFFF3B3B), fontSize: 12, fontWeight: FontWeight.bold)),
                    ],
                  ),
                )),
        ],
      ),
    );
  }
}
