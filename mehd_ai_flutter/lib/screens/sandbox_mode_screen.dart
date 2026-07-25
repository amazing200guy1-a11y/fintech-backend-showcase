import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/widgets/mehd_mascot.dart';
import 'package:mehd_ai_flutter/widgets/techno_card.dart';
import 'package:mehd_ai_flutter/services/settings_service.dart';
import 'package:mehd_ai_flutter/controllers/trading_controller.dart';
import 'dart:ui';

/// Digital Twin Sandbox Mode Screen
/// Forward-testing laboratory for simulated paper trades and Certified Alpha badge qualification.
class SandboxModeScreen extends StatefulWidget {
  const SandboxModeScreen({super.key});

  @override
  State<SandboxModeScreen> createState() => _SandboxModeScreenState();
}

class _SandboxModeScreenState extends State<SandboxModeScreen> with TickerProviderStateMixin {
  late AnimationController _orbCtrl;

  static const Map<String, dynamic> _kSeedTelemetry = {
    'simulation_hours_elapsed': 31,
    'total_simulation_hours': 48,
    'simulated_win_rate': 78.4,
    'simulated_pnl_usd': 1280.50,
    'market_outperformance_pct': 12.4,
    'certified_alpha_qualified': true,
    'active_simulations': 3,
  };

  @override
  void initState() {
    super.initState();
    _orbCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 5))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _orbCtrl.dispose();
    super.dispose();
  }

  Widget _buildGlowOrb(Color color, {double size = 350}) {
    return AnimatedBuilder(
      animation: _orbCtrl,
      builder: (context, child) {
        return Transform.scale(
          scale: 1.0 + (_orbCtrl.value * 0.15),
          child: Container(
            width: size,
            height: size,
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

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final isPaper = settings.paperMode;
    final activeBroker = settings.hasBrokerConnected ? settings.connectedBrokerId.toUpperCase() : null;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('system_metrics')
          .doc('sandbox_telemetry')
          .snapshots(),
      builder: (context, snapshot) {
        Map<String, dynamic> telemetry = Map<String, dynamic>.from(_kSeedTelemetry);
        if (snapshot.hasData && snapshot.data!.exists) {
          final live = snapshot.data!.data() as Map<String, dynamic>?;
          if (live != null && live.isNotEmpty) {
            telemetry = {..._kSeedTelemetry, ...live};
          }
        }

        return Scaffold(
          backgroundColor: MehdAiTheme.bgPrimary,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            backgroundColor: MehdAiTheme.bgSecondary,
            elevation: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        'DIGITAL TWIN SANDBOX',
                        style: GoogleFonts.outfit(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 1.5,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isPaper) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF58A6FF).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFF58A6FF).withOpacity(0.4)),
                        ),
                        child: const Text('PAPER', style: TextStyle(color: Color(0xFF58A6FF), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                      ),
                    ],
                    if (activeBroker != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00FF88).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFF00FF88).withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.shield, color: Color(0xFF00FF88), size: 10),
                            const SizedBox(width: 4),
                            Text(activeBroker, style: const TextStyle(color: Color(0xFF00FF88), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(1),
              child: Container(color: MehdAiTheme.borderColor, height: 1),
            ),
          ),
          body: Stack(
            children: [
              // Ambient depth
              Positioned(
                top: -80,
                right: -100,
                child: _buildGlowOrb(MehdAiTheme.blue.withOpacity(0.10)),
              ),
              Positioned(
                bottom: -120,
                left: -80,
                child: _buildGlowOrb(MehdAiTheme.purple.withOpacity(0.08)),
              ),

              SingleChildScrollView(
                padding: const EdgeInsets.all(24.0),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 750),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        MehdMascot(isWorking: settings.sandboxMode, size: 120),
                        const SizedBox(height: 20),
                        Text(
                          'DIGITAL TWIN SANDBOX',
                          style: GoogleFonts.outfit(
                            fontSize: 24,
                            color: MehdAiTheme.blue,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 2,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '48-Hour Live Market Forward-Testing Laboratory',
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            color: MehdAiTheme.textSecondary,
                            letterSpacing: 0.5,
                          ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: MehdAiTheme.blue.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: MehdAiTheme.blue.withOpacity(0.15)),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.science_rounded, color: MehdAiTheme.blue, size: 16),
                                  const SizedBox(width: 8),
                                  Text('WHAT THIS SCREEN DOES', style: GoogleFonts.outfit(color: MehdAiTheme.blue, fontWeight: FontWeight.bold, fontSize: 12, letterSpacing: 1)),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Text(
                                'The Den analyzes live market data and executes AI consensus forward-testing paper trades using your exact strategy configuration — without risking any real money.\n\nIf your model beats the market benchmark by >10% alpha outperformance, you earn the CERTIFIED ALPHA 🏆 badge permanently.',
                                style: GoogleFonts.inter(fontSize: 12, color: MehdAiTheme.textSecondary, height: 1.6),
                                textAlign: TextAlign.left,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // ── PRIVACY SWITCH CARD ──────────────────────────────
                        _buildToggleCard(context, settings),
                        const SizedBox(height: 24),

                        // ── TELEMETRY KPI DASHBOARD ──────────────────────────
                        _buildTelemetryDashboard(telemetry),
                        const SizedBox(height: 24),

                        // ── ACTIVE POSITIONS MONITOR ─────────────────────────
                        _buildPositionsMonitor(context),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildToggleCard(BuildContext context, SettingsService settings) {
    final isActive = settings.sandboxMode;
    final accentColor = isActive ? MehdAiTheme.blue : const Color(0xFF888888);
    final glow = isActive ? MehdAiTheme.blueGlow : <BoxShadow>[];

    return TechnoCard(
      borderColor: accentColor,
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(
                      color: accentColor,
                      shape: BoxShape.circle,
                      boxShadow: glow,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    isActive ? 'SANDBOX ISOLATION ACTIVE' : 'SANDBOX MODE DISABLED',
                    style: MehdAiTheme.terminalStyle.copyWith(
                      color: accentColor,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                ],
              ),
              Switch(
                value: isActive,
                activeColor: MehdAiTheme.blue,
                onChanged: (val) {
                  settings.setSandboxMode(val);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            isActive
                ? '🔒 SIMULATION ISOLATED: Your paper orders, order statistics, and journey milestones are fully private to this device. Nothing is posted to public leaderboards.'
                : '🌐 PUBLIC LEADERBOARD ACTIVE: Your forward-testing simulations and badges are visible on the public community leaderboard for global verification.',
            style: MehdAiTheme.labelStyle.copyWith(height: 1.5, color: MehdAiTheme.textSecondary, fontSize: 12),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          if (isActive)
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: const LinearProgressIndicator(
                backgroundColor: Colors.transparent,
                valueColor: AlwaysStoppedAnimation<Color>(MehdAiTheme.blue),
                minHeight: 2,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildTelemetryDashboard(Map<String, dynamic> data) {
    final hoursElapsed = (data['simulation_hours_elapsed'] as num?)?.toInt() ?? 31;
    final totalHours = (data['total_simulation_hours'] as num?)?.toInt() ?? 48;
    final progress = (hoursElapsed / totalHours).clamp(0.0, 1.0);
    final winRate = (data['simulated_win_rate'] as num?)?.toDouble() ?? 78.4;
    final pnl = (data['simulated_pnl_usd'] as num?)?.toDouble() ?? 1280.50;
    final alpha = (data['market_outperformance_pct'] as num?)?.toDouble() ?? 12.4;
    final isQualified = alpha >= 10.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 48-Hour Timeline Progress
        Container(
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
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('48-HOUR SIMULATION TIMELINE',
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1)),
                  Text('$hoursElapsed / $totalHours HOURS',
                      style: GoogleFonts.jetBrainsMono(color: MehdAiTheme.blue, fontSize: 12, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 10),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 6,
                  backgroundColor: Colors.white10,
                  valueColor: const AlwaysStoppedAnimation<Color>(MehdAiTheme.blue),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // KPI Metric Cards Grid
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 550;
            return isNarrow
                ? Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: _buildMetricTile('SIMULATED WIN RATE', '$winRate%', Icons.emoji_events, MehdAiTheme.green)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildMetricTile('SIMULATED P&L', '+\$${pnl.toStringAsFixed(2)}', Icons.attach_money, MehdAiTheme.gold)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(child: _buildMetricTile('ALPHA OUTPERFORMANCE', '+$alpha%', Icons.auto_graph, isQualified ? MehdAiTheme.green : MehdAiTheme.yellow)),
                          const SizedBox(width: 12),
                          Expanded(child: _buildMetricTile('ALPHA BADGE', isQualified ? 'QUALIFIED 🏆' : 'IN PROGRESS', Icons.verified, isQualified ? MehdAiTheme.gold : Colors.white38)),
                        ],
                      ),
                    ],
                  )
                : Row(
                    children: [
                      Expanded(child: _buildMetricTile('SIMULATED WIN RATE', '$winRate%', Icons.emoji_events, MehdAiTheme.green)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildMetricTile('SIMULATED P&L', '+\$${pnl.toStringAsFixed(2)}', Icons.attach_money, MehdAiTheme.gold)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildMetricTile('ALPHA OUTPERFORMANCE', '+$alpha%', Icons.auto_graph, isQualified ? MehdAiTheme.green : MehdAiTheme.yellow)),
                      const SizedBox(width: 12),
                      Expanded(child: _buildMetricTile('ALPHA BADGE', isQualified ? 'QUALIFIED 🏆' : 'IN PROGRESS', Icons.verified, isQualified ? MehdAiTheme.gold : Colors.white38)),
                    ],
                  );
          },
        ),
      ],
    );
  }

  Widget _buildMetricTile(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 14),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: GoogleFonts.inter(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.w600, letterSpacing: 0.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }

  Widget _buildPositionsMonitor(BuildContext context) {
    final trading = context.watch<TradingController>();
    final activeCount = trading.activePositions.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MehdAiTheme.borderColor),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.swap_calls_rounded, color: MehdAiTheme.blue, size: 18),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('ACTIVE SANDBOX POSITIONS',
                        style: GoogleFonts.outfit(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1),
                        overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text('$activeCount paper orders running in simulation',
                        style: GoogleFonts.inter(color: Colors.white54, fontSize: 11),
                        overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
            ],
          ),
          ElevatedButton(
            onPressed: () {
              trading.executeSandboxTrade('EUR/USD', 'BUY', 1.0850);
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('⚡ Forward-test paper trade (BUY EUR/USD) queued in Sandbox.'),
                backgroundColor: Color(0xFF1E293B),
                duration: Duration(seconds: 2),
              ));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: MehdAiTheme.blue.withOpacity(0.15),
              foregroundColor: MehdAiTheme.blue,
              side: BorderSide(color: MehdAiTheme.blue.withOpacity(0.4)),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('+ SIMULATE TRADE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
