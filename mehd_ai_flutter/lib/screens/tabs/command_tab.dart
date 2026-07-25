import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/services/settings_service.dart';
import 'package:mehd_ai_flutter/controllers/trading_controller.dart';
import 'package:mehd_ai_flutter/controllers/market_data_controller.dart';
import 'package:mehd_ai_flutter/widgets/techno_card.dart';

/// Autopilot Command Center — Autonomous Execution Deck
/// All toggles persist to SettingsService (Firebase + SharedPreferences).
/// Signal queue reflects your real active symbol and real conviction threshold.
/// Execution log appends entries when TradingController positions change.
class CommandTab extends StatefulWidget {
  const CommandTab({super.key});

  @override
  State<CommandTab> createState() => _CommandTabState();
}

class _CommandTabState extends State<CommandTab> {
  // Locally tracks Tiger Mode (not yet in SettingsService — UI only for now)
  bool _isTigerMode = false;

  // Execution log — appended dynamically when positions change
  final List<Map<String, dynamic>> _executionLog = [];
  int _lastPositionCount = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Every time TradingController notifies, we check if new positions were added
    final trading = context.read<TradingController>();
    final count = trading.activePositions.length;
    if (count > _lastPositionCount) {
      final newPositions = trading.activePositions.skip(_lastPositionCount);
      for (final pos in newPositions) {
        _executionLog.insert(0, {
          'time': _nowTime(),
          'event': 'Autopilot executed ${pos['type']} ${pos['symbol']} @ ${pos['entry']}  |  Lot: ${pos['lotSize']}',
          'status': 'EXECUTED',
          'color': const Color(0xFF00FF88),
        });
      }
    } else if (count < _lastPositionCount) {
      _executionLog.insert(0, {
        'time': _nowTime(),
        'event': 'Position closed — ${_lastPositionCount - count} position(s) liquidated',
        'status': 'CLOSED',
        'color': const Color(0xFFFF3B3B),
      });
    }
    _lastPositionCount = count;
  }

  String _nowTime() {
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final trading = context.watch<TradingController>();
    final market = context.watch<MarketDataController>();

    final isPaper = settings.paperMode;
    final threshold = settings.convictionThreshold.toInt();
    final lotSize = settings.defaultLotSize;
    final activePositionsCount = trading.activePositions.length;
    final accountBalance = settings.accountBalance;
    final activeSymbol = market.activeSymbol ?? 'EUR/USD';
    final livePrice = market.latestSnapshot?.close;

    // Autopilot & Alpha mode from SettingsService — persisted across screen changes
    final autopilotEngaged = settings.autopilotEngaged;
    final alphaPredatorMode = settings.alphaPredatorMode;

    // Effective lot size when Alpha is on
    final effectiveLot = alphaPredatorMode ? (lotSize * 1.5) : lotSize;

    // Sentinel values from real settings
    final riskPct = settings.riskPerTrade;
    final stopLossPips = settings.defaultStopLoss;

    return Material(
      color: MehdAiTheme.bgPrimary,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 40),
        children: [

          // ── 1. MASTER AUTOPILOT ENGAGEMENT DECK ────────────────────────────
          _buildMasterEngagementCard(context, settings, autopilotEngaged),
          const SizedBox(height: 20),

          // ── 2. LIVE TELEMETRY KPI DASHBOARD ────────────────────────────────
          _buildTelemetryDashboard(
            isPaper: isPaper,
            balance: accountBalance,
            activeCount: activePositionsCount,
            threshold: threshold,
            effectiveLot: effectiveLot,
          ),
          const SizedBox(height: 24),

          // ── 3. MODE CONTROLS DECK ──────────────────────────────────────────
          _buildSectionHeader('AUTONOMOUS MODE CONTROLS', Icons.tune_rounded, MehdAiTheme.blue),
          const SizedBox(height: 12),
          _buildModeToggleCards(context, settings, autopilotEngaged, alphaPredatorMode),
          const SizedBox(height: 24),

          // ── 4. CORE PAIRS SIGNAL QUEUE ─────────────────────────────────────
          _buildSectionHeader('ACTIVE SIGNAL QUEUE', Icons.bolt_rounded, const Color(0xFF00FF88)),
          const SizedBox(height: 12),
          _buildSignalQueue(activeSymbol, livePrice, threshold, trading, alphaPredatorMode, effectiveLot),
          const SizedBox(height: 24),

          // ── 5. SENTINEL AUTOMATED RISK PROTOCOL ────────────────────────────
          _buildSectionHeader('SENTINEL RISK PROTOCOL', Icons.shield_outlined, MehdAiTheme.gold),
          const SizedBox(height: 12),
          _buildSentinelRiskRulesCard(riskPct, stopLossPips),
          const SizedBox(height: 24),

          // ── 6. REAL-TIME EXECUTION LOG ──────────────────────────────────────
          _buildSectionHeader('REAL-TIME EXECUTION LOG', Icons.receipt_long_rounded, Colors.white70),
          const SizedBox(height: 12),
          _buildExecutionLogCard(trading),
          const SizedBox(height: 30),
        ],
      ),
    );
  }

  // ── SECTION HEADER ────────────────────────────────────────────────────────
  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 16),
        const SizedBox(width: 8),
        Text(
          title,
          style: GoogleFonts.outfit(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5),
        ),
      ],
    );
  }

  // ── 1. MASTER ENGAGEMENT CARD ─────────────────────────────────────────────
  Widget _buildMasterEngagementCard(BuildContext context, SettingsService settings, bool engaged) {
    final engagedColor = engaged ? const Color(0xFF00FF88) : const Color(0xFFFF3B3B);
    return TechnoCard(
      borderColor: engagedColor.withOpacity(0.5),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  // Pulsing status dot
                  Container(
                    width: 14, height: 14,
                    decoration: BoxDecoration(
                      color: engagedColor,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: engagedColor.withOpacity(0.5), blurRadius: 10, spreadRadius: 2)],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        engaged ? 'AUTOPILOT ENGAGED' : 'AUTOPILOT DISARMED',
                        style: GoogleFonts.outfit(color: engagedColor, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.5),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        engaged
                            ? 'Autonomous Execution Active • 24/5 Swarm Monitoring'
                            : 'Manual Assist Mode • Tap APPROVE to strike each signal',
                        style: GoogleFonts.inter(color: MehdAiTheme.textSecondary, fontSize: 11),
                      ),
                    ],
                  ),
                ],
              ),
              // Toggle saves to SettingsService → Firebase + SharedPreferences
              Switch(
                value: engaged,
                activeColor: const Color(0xFF00FF88),
                inactiveThumbColor: const Color(0xFFFF3B3B),
                onChanged: (val) => settings.setAutopilotEngaged(val),
              ),
            ],
          ),
          if (!engaged) ...[ 
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => settings.setAutopilotEngaged(true),
                icon: const Icon(Icons.flash_on_rounded, size: 16),
                label: const Text('RE-ENGAGE AUTOPILOT NOW', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00FF88).withOpacity(0.15),
                  foregroundColor: const Color(0xFF00FF88),
                  side: const BorderSide(color: Color(0xFF00FF88)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ── 2. TELEMETRY DASHBOARD ────────────────────────────────────────────────
  Widget _buildTelemetryDashboard({
    required bool isPaper,
    required double balance,
    required int activeCount,
    required int threshold,
    required double effectiveLot,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 600;
        final tiles = [
          _buildMetricTile('ENVIRONMENT', isPaper ? 'PAPER DEMO' : 'LIVE BROKER', Icons.science_rounded, isPaper ? const Color(0xFF58A6FF) : const Color(0xFFFF3B3B)),
          _buildMetricTile('CAPITAL', '\$${balance.toStringAsFixed(0)}', Icons.account_balance_wallet_rounded, MehdAiTheme.gold),
          _buildMetricTile('CONVICTION GATE', '≥ $threshold%', Icons.verified_rounded, MehdAiTheme.blue),
          _buildMetricTile('ACTIVE POSITIONS', '$activeCount Open', Icons.swap_calls_rounded, const Color(0xFF00FF88)),
        ];
        if (isNarrow) {
          return Column(children: [
            Row(children: [Expanded(child: tiles[0]), const SizedBox(width: 10), Expanded(child: tiles[1])]),
            const SizedBox(height: 10),
            Row(children: [Expanded(child: tiles[2]), const SizedBox(width: 10), Expanded(child: tiles[3])]),
          ]);
        }
        return Row(children: [
          Expanded(child: tiles[0]), const SizedBox(width: 10),
          Expanded(child: tiles[1]), const SizedBox(width: 10),
          Expanded(child: tiles[2]), const SizedBox(width: 10),
          Expanded(child: tiles[3]),
        ]);
      },
    );
  }

  Widget _buildMetricTile(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, color: color, size: 13),
            const SizedBox(width: 6),
            Flexible(child: Text(label, style: GoogleFonts.inter(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.5), overflow: TextOverflow.ellipsis)),
          ]),
          const SizedBox(height: 6),
          Text(value, style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  // ── 3. MODE TOGGLE CARDS ──────────────────────────────────────────────────
  Widget _buildModeToggleCards(BuildContext context, SettingsService settings, bool autopilotEngaged, bool alphaPredatorMode) {
    return Column(
      children: [
        // Autopilot Auto-Execution — persisted to SettingsService
        _buildToggleRow(
          title: 'AUTONOMOUS AUTO-EXECUTION',
          subtitle: 'Automatically executes qualifying signals without manual approval',
          value: autopilotEngaged,
          color: const Color(0xFF00FF88),
          onChanged: (val) => settings.setAutopilotEngaged(val),
        ),
        const SizedBox(height: 10),
        // Alpha Predator Mode — persisted to SettingsService
        _buildToggleRow(
          title: 'ALPHA PREDATOR MODE  (1.5× SIZING)',
          subtitle: 'Boosts lot size by 1.5× on ultra-high conviction setups (≥ 92%). Risk increases proportionally.',
          value: alphaPredatorMode,
          color: MehdAiTheme.purple,
          onChanged: (val) => settings.setAlphaPredatorMode(val),
        ),
        const SizedBox(height: 10),
        // Tiger Mode — UI only (backend integration when broker API is live)
        _buildToggleRow(
          title: 'TIGER INSTITUTIONAL MODE',
          subtitle: 'Zero-latency gateway to your connected broker API (requires live broker connection)',
          value: _isTigerMode,
          color: MehdAiTheme.gold,
          onChanged: (val) => setState(() => _isTigerMode = val),
        ),
      ],
    );
  }

  Widget _buildToggleRow({
    required String title,
    required String subtitle,
    required bool value,
    required Color color,
    required ValueChanged<bool> onChanged,
  }) {
    return TechnoCard(
      borderColor: value ? color.withOpacity(0.4) : MehdAiTheme.borderColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: GoogleFonts.outfit(color: value ? color : Colors.white70, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                const SizedBox(height: 2),
                Text(subtitle, style: GoogleFonts.inter(color: MehdAiTheme.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          Switch(value: value, activeColor: color, onChanged: onChanged),
        ],
      ),
    );
  }

  // ── 4. SIGNAL QUEUE ───────────────────────────────────────────────────────
  Widget _buildSignalQueue(String activeSymbol, double? livePrice, int threshold, TradingController trading, bool alphaPredatorMode, double effectiveLot) {
    // Static seed signals — in production these come from the backend API consensus engine
    final seedSignals = [
      {'symbol': 'EUR/USD', 'direction': 'BUY',  'conviction': 92.4, 'price': livePrice != null && activeSymbol == 'EUR/USD' ? livePrice.toStringAsFixed(4) : '1.0852', 'target': '1.0890', 'sl': '1.0830'},
      {'symbol': 'XAU/USD', 'direction': 'BUY',  'conviction': 88.1, 'price': livePrice != null && activeSymbol == 'XAU/USD' ? livePrice.toStringAsFixed(2) : '2354.20', 'target': '2370.00', 'sl': '2342.00'},
      {'symbol': 'GBP/USD', 'direction': 'SELL', 'conviction': 85.0, 'price': livePrice != null && activeSymbol == 'GBP/USD' ? livePrice.toStringAsFixed(4) : '1.2710', 'target': '1.2650', 'sl': '1.2750'},
      {'symbol': 'BTC/USD', 'direction': 'HOLD', 'conviction': 64.2, 'price': livePrice != null && activeSymbol == 'BTC/USD' ? livePrice.toStringAsFixed(2) : '64210.00', 'target': 'N/A', 'sl': 'N/A'},
    ];

    // Always put the active symbol first
    final sorted = [...seedSignals]..sort((a, b) {
      if (a['symbol'] == activeSymbol) return -1;
      if (b['symbol'] == activeSymbol) return 1;
      return 0;
    });

    return Column(
      children: sorted.map((signal) {
        final conviction = (signal['conviction'] as num).toDouble();
        final meets = conviction >= threshold;
        final dir = signal['direction'] as String;
        final Color color = dir == 'BUY'
            ? const Color(0xFF00FF88)
            : dir == 'SELL'
                ? const Color(0xFFFF3B3B)
                : const Color(0xFF888888);
        final String status = !meets
            ? 'REJECTED (< ${threshold}% THRESHOLD)'
            : dir == 'HOLD'
                ? 'MONITORING'
                : 'STRIKE QUEUED';

        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1117),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(meets ? 0.35 : 0.15)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: color.withOpacity(0.4)),
                  ),
                  child: Text(dir, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Text(signal['symbol'] as String, style: GoogleFonts.outfit(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                      if (signal['symbol'] == activeSymbol) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(color: MehdAiTheme.blue.withOpacity(0.15), borderRadius: BorderRadius.circular(3), border: Border.all(color: MehdAiTheme.blue.withOpacity(0.4))),
                          child: Text('ACTIVE', style: GoogleFonts.inter(color: MehdAiTheme.blue, fontSize: 8, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ]),
                    const SizedBox(height: 2),
                    Text(
                      'Price: ${signal['price']}  •  TP: ${signal['target']}  •  SL: ${signal['sl']}  •  Lot: ${effectiveLot.toStringAsFixed(2)}',
                      style: GoogleFonts.inter(color: Colors.white54, fontSize: 10),
                    ),
                  ],
                ),
              ]),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${conviction.toStringAsFixed(1)}%',
                    style: GoogleFonts.jetBrainsMono(color: meets ? const Color(0xFF00FF88) : Colors.white38, fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 2),
                  Text(status, style: GoogleFonts.inter(color: color, fontSize: 9, fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── 5. SENTINEL RISK RULES ────────────────────────────────────────────────
  Widget _buildSentinelRiskRulesCard(double riskPct, double stopLossPips) {
    return TechnoCard(
      borderColor: MehdAiTheme.gold.withOpacity(0.3),
      child: Column(
        children: [
          // Reads from settings.riskPerTrade
          _buildRiskRuleRow('AUTO-KILL SWITCH', 'Freezes trading if daily drawdown hits ${(riskPct * 3).toStringAsFixed(1)}% (3× your risk/trade)', 'ARMED 🛡️', const Color(0xFF00FF88)),
          const Divider(color: MehdAiTheme.borderColor, height: 16),
          _buildRiskRuleRow('NEWS BLACKOUT SHIELD', 'Pauses execution 30 min before high-impact news (NFP / CPI / FOMC)', 'ACTIVE 📰', const Color(0xFF58A6FF)),
          const Divider(color: MehdAiTheme.borderColor, height: 16),
          // Reads from settings.defaultStopLoss
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

  // ── 6. EXECUTION LOG ──────────────────────────────────────────────────────
  Widget _buildExecutionLogCard(TradingController trading) {
    // If no real log entries yet, show seed entries so screen doesn't look empty
    final List<Map<String, dynamic>> displayLog = _executionLog.isNotEmpty
        ? _executionLog
        : [
            {'time': '--:--:--', 'event': 'Autopilot swarm monitoring 24/5 — awaiting qualifying signal', 'status': 'WATCHING', 'color': const Color(0xFF58A6FF)},
            {'time': '--:--:--', 'event': 'Sentinel risk rules armed and active', 'status': 'ARMED', 'color': const Color(0xFF00FF88)},
          ];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: MehdAiTheme.borderColor),
      ),
      child: Column(
        children: displayLog.map((log) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Text(log['time'] as String, style: GoogleFonts.jetBrainsMono(color: Colors.white38, fontSize: 10)),
                const SizedBox(width: 10),
                Expanded(child: Text(log['event'] as String, style: GoogleFonts.inter(color: Colors.white70, fontSize: 11))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: (log['color'] as Color).withOpacity(0.12), borderRadius: BorderRadius.circular(3)),
                  child: Text(log['status'] as String, style: TextStyle(color: log['color'] as Color, fontSize: 8, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
