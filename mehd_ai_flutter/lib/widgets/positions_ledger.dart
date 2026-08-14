import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/controllers/trading_controller.dart';

/// Full positions ledger table — responsive (mobile cards + desktop table).
class PositionsLedger extends StatelessWidget {
  final TradingController trading;
  final List<Map<String, dynamic>> activePositions;
  final double? livePrice;
  final String activeSymbol;

  const PositionsLedger({
    super.key,
    required this.trading,
    required this.activePositions,
    required this.livePrice,
    required this.activeSymbol,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0D1117),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: MehdAiTheme.borderColor),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (MediaQuery.of(context).size.width >= 768)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: MehdAiTheme.borderColor)),
                    color: Color(0xFF161B22),
                  ),
                  child: Row(
                    children: [
                      Expanded(flex: 2, child: Text("TICKET", style: GoogleFonts.outfit(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold))),
                      Expanded(flex: 2, child: Text("SYMBOL", style: GoogleFonts.outfit(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold))),
                      Expanded(flex: 2, child: Text("TYPE", style: GoogleFonts.outfit(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold))),
                      Expanded(flex: 2, child: Text("ENTRY", style: GoogleFonts.outfit(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
                      Expanded(flex: 2, child: Text("CURRENT", style: GoogleFonts.outfit(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
                      Expanded(flex: 3, child: Text("PROFIT / LOSS", style: GoogleFonts.outfit(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
                      const SizedBox(width: 140, child: Text("ACTIONS", style: TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
                    ],
                  ),
                ),
              Expanded(
                child: activePositions.isEmpty
                    ? _buildEmptyState()
                    : ListView.separated(
                        padding: const EdgeInsets.all(8),
                        itemCount: activePositions.length,
                        separatorBuilder: (c, i) => const SizedBox(height: 8),
                        itemBuilder: (context, index) => _buildPositionRow(context, activePositions[index]),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.inbox_outlined, color: Colors.white24, size: 40),
          SizedBox(height: 12),
          Text('No active positions', style: TextStyle(color: Colors.white38, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildPositionRow(BuildContext context, Map<String, dynamic> pos) {
    final String id = pos['id'] as String;
    final String symbol = pos['symbol'] as String;
    final String type = pos['type'] as String;
    final double entry = (pos['entry'] as num).toDouble();
    final double current = (pos['current'] as num).toDouble();
    final double pnl = (pos['pnl'] as num).toDouble();
    final double lotSize = (pos['lotSize'] as num?)?.toDouble() ?? 1.0;
    final bool isProfit = pnl >= 0;
    final Color pnlColor = isProfit ? const Color(0xFF00FF88) : const Color(0xFFFF3B3B);
    final Color typeColor = type == 'BUY' ? const Color(0xFF00FF88) : const Color(0xFFFF3B3B);
    final bool isMobile = MediaQuery.of(context).size.width < 768;
    final displayCurrent = (pos['symbol'] == activeSymbol && livePrice != null)
        ? livePrice!
        : current;
    final int decimals = symbol.contains('JPY') || symbol.contains('XAU') ? 2 : 4;

    if (isMobile) {
      return Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFF161B22),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: MehdAiTheme.borderColor),
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: typeColor.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: typeColor.withOpacity(0.5)),
                    ),
                    child: Text(type, style: TextStyle(color: typeColor, fontSize: 10, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 8),
                  Text(symbol, style: GoogleFonts.outfit(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 6),
                  Text('${lotSize.toStringAsFixed(2)} Lot', style: GoogleFonts.inter(color: Colors.white54, fontSize: 11)),
                ]),
                Text("${isProfit ? '+' : '-'}\$${pnl.abs().toStringAsFixed(2)}", style: GoogleFonts.jetBrainsMono(color: pnlColor, fontWeight: FontWeight.bold, fontSize: 16)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Entry: ${entry.toStringAsFixed(2)}", style: GoogleFonts.jetBrainsMono(color: Colors.white54, fontSize: 11)),
                Text("Now: ${displayCurrent.toStringAsFixed(2)}", style: GoogleFonts.jetBrainsMono(color: Colors.white70, fontSize: 11)),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(icon: const Icon(Icons.pie_chart_rounded, color: Color(0xFF58A6FF), size: 18), onPressed: () => trading.closePartialPosition(id, 0.5)),
                IconButton(icon: const Icon(Icons.cancel_rounded, color: Color(0xFFFF3B3B), size: 18), onPressed: () => trading.closePosition(id)),
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
      child: Row(
        children: [
          Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(id, style: GoogleFonts.jetBrainsMono(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
            Text('${lotSize.toStringAsFixed(2)} Lot', style: GoogleFonts.inter(color: MehdAiTheme.textSecondary, fontSize: 9)),
          ])),
          Expanded(flex: 2, child: Text(symbol, style: GoogleFonts.outfit(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold))),
          Expanded(flex: 2, child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: typeColor.withOpacity(0.15), borderRadius: BorderRadius.circular(4), border: Border.all(color: typeColor.withOpacity(0.4))),
              child: Text(type, style: TextStyle(color: typeColor, fontSize: 9, fontWeight: FontWeight.bold)),
            ),
            if (pos['isBreakevenArmed'] == true) ...[const SizedBox(width: 4), const Icon(Icons.shield_rounded, color: Color(0xFF00FF88), size: 12)],
          ])),
          Expanded(flex: 2, child: Text(entry.toStringAsFixed(decimals), style: GoogleFonts.jetBrainsMono(color: Colors.white70, fontSize: 11), textAlign: TextAlign.right)),
          Expanded(flex: 2, child: Text(displayCurrent.toStringAsFixed(decimals), style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
          Expanded(flex: 3, child: Text("${isProfit ? '+' : '-'}\$${pnl.abs().toStringAsFixed(2)}", style: GoogleFonts.jetBrainsMono(color: pnlColor, fontWeight: FontWeight.bold, fontSize: 15), textAlign: TextAlign.right)),
          const SizedBox(width: 12),
          SizedBox(
            width: 140,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(onPressed: () => trading.closePartialPosition(id, 0.5), icon: const Icon(Icons.pie_chart_outline_rounded, color: MehdAiTheme.blue, size: 16), tooltip: "Bank 50% Profit"),
                IconButton(onPressed: () => trading.setBreakevenSL(id), icon: Icon(Icons.shield_outlined, color: pos['isBreakevenArmed'] == true ? const Color(0xFF00FF88) : Colors.white38, size: 16), tooltip: "Move SL to Breakeven"),
                IconButton(onPressed: () => trading.closePosition(id), icon: const Icon(Icons.close_rounded, color: Color(0xFFFF3B3B), size: 16), tooltip: "Liquidate Position"),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
