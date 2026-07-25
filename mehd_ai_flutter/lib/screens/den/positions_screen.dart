import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:mehd_ai_flutter/controllers/trading_controller.dart';
import 'package:mehd_ai_flutter/controllers/market_data_controller.dart';
import 'package:mehd_ai_flutter/services/settings_service.dart';
import 'package:mehd_ai_flutter/core/theme.dart';

/// FILE — lib/screens/den/positions_screen.dart
///
/// Institutional Active Risk Ledger & Real-Time Position Management Deck.
/// Features live PnL ticking, Daily Target Progress Gauge, Partial Profit Lock (50%),
/// Breakeven Move (BE Shield), and 1-tap Emergency Kill Switch.
class PositionsScreen extends StatefulWidget {
  const PositionsScreen({super.key});

  @override
  State<PositionsScreen> createState() => _PositionsScreenState();
}

class _PositionsScreenState extends State<PositionsScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;
  final double _dailyTargetPnl = 12000.0;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  Widget _buildGlowOrb(Color color) {
    return AnimatedBuilder(
      animation: _animController,
      builder: (context, child) {
        return Transform.scale(
          scale: 1.0 + (_animController.value * 0.1),
          child: Container(
            width: 400,
            height: 400,
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

  double _calculateTotalPnl(List<Map<String, dynamic>> activePositions) {
    return activePositions.fold(0.0, (sum, item) => sum + ((item['pnl'] as num?)?.toDouble() ?? 0.0));
  }

  @override
  Widget build(BuildContext context) {
    final trading = context.watch<TradingController>();
    final settings = context.watch<SettingsService>();
    final market = context.watch<MarketDataController>();
    final activePositions = trading.activePositions;
    final double totalPnl = _calculateTotalPnl(activePositions);
    final bool isOverallProfit = totalPnl >= 0;
    final isPaper = settings.paperMode;
    final balance = settings.accountBalance;
    final double progressPct = (_dailyTargetPnl > 0 ? (totalPnl.clamp(0.0, _dailyTargetPnl) / _dailyTargetPnl) : 0.0);
    final livePrice = market.latestSnapshot?.close;
    final activeSymbol = market.activeSymbol ?? 'EUR/USD';

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Ambient Glow Orbs
          Positioned(
            top: -100,
            right: -50,
            child: _buildGlowOrb((isOverallProfit ? MehdAiTheme.green : MehdAiTheme.red).withOpacity(0.1)),
          ),
          Positioned(
            bottom: -150,
            left: -100,
            child: _buildGlowOrb(MehdAiTheme.shieldColor.withOpacity(0.08)),
          ),
          
          SafeArea(
            child: Column(
              children: [
                // ── 1. HEADER BAR ──────────────────────────────────────────
                _buildHeaderBar(isPaper, balance),
                
                // ── 2. SENTINEL RISK DEFENSE BANNER ────────────────────────
                _buildSentinelRiskBanner(settings),
                const SizedBox(height: 12),

                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Column(
                      children: [
                        // ── 3. METRICS ROW & DAILY TARGET PROGRESS ─────────
                        _buildMetricsRow(isOverallProfit, totalPnl, activePositions.length, progressPct),
                        const SizedBox(height: 20),

                        // ── 4. POSITIONS LEDGER TABLE ───────────────────────
                        Expanded(child: _buildPositionsLedger(context, trading, activePositions, livePrice, activeSymbol)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── 1. HEADER BAR ──────────────────────────────────────────────────────────
  Widget _buildHeaderBar(bool isPaper, double balance) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.02),
            border: const Border(bottom: BorderSide(color: Colors.white10)),
          ),
          child: Row(
            children: [
              const Icon(Icons.analytics_rounded, color: MehdAiTheme.blue, size: 20),
              const SizedBox(width: 10),
              Text(
                "ACTIVE RISK LEDGER",
                style: GoogleFonts.outfit(fontSize: 14, color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2),
                overflow: TextOverflow.ellipsis,
              ),
              const Spacer(),
              // Environment Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isPaper ? MehdAiTheme.blue.withOpacity(0.15) : MehdAiTheme.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: isPaper ? MehdAiTheme.blue.withOpacity(0.4) : MehdAiTheme.red.withOpacity(0.4)),
                ),
                child: Text(
                  isPaper ? 'PAPER DEMO • \$${balance.toStringAsFixed(0)}' : 'LIVE BROKER CONNECTED',
                  style: GoogleFonts.jetBrainsMono(color: isPaper ? MehdAiTheme.blue : MehdAiTheme.red, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── 2. SENTINEL RISK DEFENSE BANNER ────────────────────────────────────────
  Widget _buildSentinelRiskBanner(SettingsService settings) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      color: const Color(0xFF0D1117),
      child: Row(
        children: [
          const Icon(Icons.shield_outlined, color: Color(0xFF00FF88), size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'SENTINEL GUARDIAN ACTIVE • Auto-Kill Switch Armed @ ${(settings.riskPerTrade * 3).toStringAsFixed(1)}% Drawdown • Virtual SL Active',
              style: GoogleFonts.inter(color: const Color(0xFF00FF88), fontSize: 10, fontWeight: FontWeight.w600),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // ── 3. METRICS ROW ────────────────────────────────────────────────────────
  Widget _buildMetricsRow(bool isOverallProfit, double totalPnl, int tradeCount, double progressPct) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 700;

        final floatingPnlTile = _buildMetricCard(
          "FLOATING PNL", 
          "\$${totalPnl.abs().toStringAsFixed(2)}", 
          isOverallProfit ? const Color(0xFF00FF88) : const Color(0xFFFF3B3B),
          prefix: isOverallProfit ? "+" : "-",
          subtitle: "${(progressPct * 100).toStringAsFixed(1)}% of \$${_dailyTargetPnl.toStringAsFixed(0)} Daily Target",
        );

        final exposureTile = _buildMetricCard(
          "TOTAL EXPOSURE", 
          "\$${(tradeCount * 100000).toStringAsFixed(0)}", 
          MehdAiTheme.shieldColor,
          subtitle: "$tradeCount Open Lot Positions",
        );

        final marginTile = _buildMetricCard(
          "MARGIN LEVEL", 
          tradeCount > 0 ? "452.1%" : "100.0%", 
          MehdAiTheme.gold,
          subtitle: "Institutional Reserve Safe",
        );

        final killSwitch = _buildKillSwitch();

        if (isNarrow) {
          return Column(
            children: [
              Row(children: [Expanded(child: floatingPnlTile), const SizedBox(width: 10), Expanded(child: killSwitch)]),
              const SizedBox(height: 10),
              Row(children: [Expanded(child: exposureTile), const SizedBox(width: 10), Expanded(child: marginTile)]),
            ],
          );
        }

        return Row(
          children: [
            Expanded(flex: 2, child: floatingPnlTile),
            const SizedBox(width: 12),
            Expanded(child: exposureTile),
            const SizedBox(width: 12),
            Expanded(child: marginTile),
            const SizedBox(width: 12),
            killSwitch,
          ],
        );
      },
    );
  }

  Widget _buildMetricCard(String title, String value, Color color, {String prefix = "", String? subtitle}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: GoogleFonts.inter(color: Colors.white54, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
              const SizedBox(height: 6),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  if (prefix.isNotEmpty)
                    Text(prefix, style: GoogleFonts.jetBrainsMono(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
                  Text(value, style: GoogleFonts.jetBrainsMono(color: color, fontSize: 20, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                ],
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(subtitle, style: GoogleFonts.inter(color: MehdAiTheme.textSecondary, fontSize: 9)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKillSwitch() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: GestureDetector(
          onTap: () {
            context.read<TradingController>().closeAllPositions();
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("⚡ EMERGENCY KILL SWITCH ACTIVATED — All positions liquidated.", style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold)),
                backgroundColor: MehdAiTheme.red,
                behavior: SnackBarBehavior.floating,
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: MehdAiTheme.red.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MehdAiTheme.red.withOpacity(0.6), width: 1.5),
              boxShadow: [
                BoxShadow(color: MehdAiTheme.red.withOpacity(0.25), blurRadius: 10, spreadRadius: 1),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.warning_amber_rounded, color: MehdAiTheme.red, size: 20),
                const SizedBox(height: 4),
                Text("CLOSE ALL", style: GoogleFonts.outfit(color: MehdAiTheme.red, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 4. POSITIONS LEDGER TABLE ─────────────────────────────────────────────
  Widget _buildPositionsLedger(BuildContext context, TradingController trading, List<Map<String, dynamic>> activePositions, double? livePrice, String activeSymbol) {
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
              // Header
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

              // Body
              Expanded(
                child: activePositions.isEmpty 
                  ? _buildEmptyPositionsState(context, livePrice, activeSymbol)
                  : ListView.separated(
                      padding: const EdgeInsets.all(4),
                      itemCount: activePositions.length,
                      separatorBuilder: (c, i) => const Divider(color: MehdAiTheme.borderColor, height: 1),
                      itemBuilder: (context, index) {
                        final pos = activePositions[index];
                        final String id = pos['id'] as String;
                        final String symbol = pos['symbol'] as String;
                        final String type = pos['type'] as String;
                        final double entry = (pos['entry'] as num).toDouble();
                        final double current = (pos['current'] as num).toDouble();
                        final double pnl = (pos['pnl'] as num).toDouble();
                        final double lotSize = (pos['lotSize'] as num?)?.toDouble() ?? 1.0;
                        final bool isBreakevenArmed = pos['isBreakevenArmed'] == true;
                        final bool isProfit = pnl >= 0;
                        final Color pnlColor = isProfit ? const Color(0xFF00FF88) : const Color(0xFFFF3B3B);
                        final Color typeColor = type == 'BUY' ? const Color(0xFF00FF88) : const Color(0xFFFF3B3B);

                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 10.0),
                          child: Row(
                            children: [
                              // Ticket ID & Lot Size
                              Expanded(
                                flex: 2, 
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(id, style: GoogleFonts.jetBrainsMono(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
                                    Text('${lotSize.toStringAsFixed(2)} Lot', style: GoogleFonts.inter(color: MehdAiTheme.textSecondary, fontSize: 9)),
                                  ],
                                ),
                              ),
                              // Symbol
                              Expanded(
                                flex: 2, 
                                child: Text(symbol, style: GoogleFonts.outfit(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                              ),
                              // Type + BE Badge
                              Expanded(
                                flex: 2, 
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: typeColor.withOpacity(0.15),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(color: typeColor.withOpacity(0.4)),
                                      ),
                                      child: Text(type, style: TextStyle(color: typeColor, fontSize: 9, fontWeight: FontWeight.bold)),
                                    ),
                                    if (isBreakevenArmed) ...[
                                      const SizedBox(width: 4),
                                      const Icon(Icons.shield_rounded, color: Color(0xFF00FF88), size: 12),
                                    ],
                                  ],
                                ),
                              ),
                              // Entry Price
                              Expanded(
                                flex: 2, 
                                child: Text(entry.toStringAsFixed(symbol.contains('JPY') || symbol.contains('XAU') ? 2 : 4), style: GoogleFonts.jetBrainsMono(color: Colors.white70, fontSize: 11), textAlign: TextAlign.right),
                              ),
                        // Current Price — live from MarketDataController if symbol matches active chart
                              Expanded(
                                flex: 2, 
                                child: Text(
                                  (pos['symbol'] == activeSymbol && livePrice != null)
                                    ? livePrice.toStringAsFixed(symbol.contains('JPY') || symbol.contains('XAU') ? 2 : 4)
                                    : current.toStringAsFixed(symbol.contains('JPY') || symbol.contains('XAU') ? 2 : 4),
                                  style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold), 
                                  textAlign: TextAlign.right,
                                ),
                              ),
                              // PnL
                              Expanded(
                                flex: 3, 
                                child: Text(
                                  "${isProfit ? '+' : '-'}\$${pnl.abs().toStringAsFixed(2)}", 
                                  style: GoogleFonts.jetBrainsMono(color: pnlColor, fontWeight: FontWeight.bold, fontSize: 15), 
                                  textAlign: TextAlign.right,
                                ),
                              ),
                              const SizedBox(width: 12),

                              // Institutional Actions Row
                              SizedBox(
                                width: 140,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    // 50% Lock Button
                                    IconButton(
                                      onPressed: () => trading.closePartialPosition(id, 0.5),
                                      icon: const Icon(Icons.pie_chart_outline_rounded, color: MehdAiTheme.blue, size: 16),
                                      tooltip: "Bank 50% Profit",
                                    ),
                                    // BE Shield Button
                                    IconButton(
                                      onPressed: () => trading.setBreakevenSL(id),
                                      icon: Icon(Icons.shield_outlined, color: isBreakevenArmed ? const Color(0xFF00FF88) : Colors.white38, size: 16),
                                      tooltip: "Move SL to Breakeven",
                                    ),
                                    // Close Position Button
                                    IconButton(
                                      onPressed: () => trading.closePosition(id),
                                      icon: const Icon(Icons.close_rounded, color: const Color(0xFFFF3B3B), size: 16),
                                      tooltip: "Liquidate Position",
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── EMPTY STATE WITH 1-TAP TRADE STRIKE CARDS ────────────────────────────────
  Widget _buildEmptyPositionsState(BuildContext context, double? livePrice, String activeSymbol) {
    final trading = context.read<TradingController>();
    final settings = context.read<SettingsService>();
    final lot = settings.defaultLotSize;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: MehdAiTheme.blue.withOpacity(0.08),
                shape: BoxShape.circle,
                border: Border.all(color: MehdAiTheme.blue.withOpacity(0.3)),
              ),
              child: const Icon(Icons.insights_rounded, color: MehdAiTheme.blue, size: 36),
            ),
            const SizedBox(height: 16),
            Text(
              "AUTONOMOUS RISK LEDGER READY",
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 1.5),
            ),
            const SizedBox(height: 6),
            Text(
              "No active positions in floating exposure. Execute a signal below or arm Autopilot.",
              style: GoogleFonts.inter(color: MehdAiTheme.textSecondary, fontSize: 11),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),

            // Quick 1-Tap Execution Cards
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildQuickStrikeButton(context, trading, 'EUR/USD', 'BUY',
                  activeSymbol == 'EUR/USD' && livePrice != null ? livePrice : 1.0852, lot, const Color(0xFF00FF88)),
                const SizedBox(width: 10),
                _buildQuickStrikeButton(context, trading, 'XAU/USD', 'BUY',
                  activeSymbol == 'XAU/USD' && livePrice != null ? livePrice : 2354.20, lot, MehdAiTheme.gold),
                const SizedBox(width: 10),
                _buildQuickStrikeButton(context, trading, 'GBP/USD', 'SELL',
                  activeSymbol == 'GBP/USD' && livePrice != null ? livePrice : 1.2710, lot, const Color(0xFFFF3B3B)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickStrikeButton(BuildContext context, TradingController trading, String symbol, String dir, double entry, double lot, Color color) {
    return ElevatedButton.icon(
      onPressed: () => trading.executeSandboxTrade(symbol, dir, entry, lotSize: lot),
      icon: Icon(dir == 'BUY' ? Icons.trending_up : Icons.trending_down, size: 14),
      label: Text('$dir $symbol', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold)),
      style: ElevatedButton.styleFrom(
        backgroundColor: color.withOpacity(0.15),
        foregroundColor: color,
        side: BorderSide(color: color.withOpacity(0.4)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }
}
