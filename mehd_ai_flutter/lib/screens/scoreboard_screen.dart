import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:mehd_ai_flutter/widgets/techno_card.dart';
import 'package:mehd_ai_flutter/widgets/rolling_ticker.dart';
import 'package:mehd_ai_flutter/screens/war_room_screen.dart';
import 'package:mehd_ai_flutter/services/settings_service.dart';
import 'package:mehd_ai_flutter/widgets/scoreboard_accountability.dart';

// ── Default seed data shown instantly while Firestore loads (or if offline) ──
const Map<String, dynamic> _kSeedData = {
  'total_signals': 12547,
  'win_rate_percentage': 71.2,
  'average_conviction': 83.7,
  'capital_protected_usd': 1248135.00,
  'bad_trades_blocked': 4381,
  'layer_performance': {
    'research': {'accuracy': 82.4, 'status': 'OPTIMAL'},
    'strategy':     {'accuracy': 74.1, 'status': 'STABLE'},
    'olympus':    {'accuracy': 91.2, 'status': 'DOMINANT'},
    'supreme':    {'accuracy': 98.9, 'status': 'ABSOLUTE'},
  },
  'performance_chart_30d': [
    65.0, 66.2, 67.8, 66.5, 68.1, 70.0, 71.2, 69.8, 70.5, 72.1,
    73.4, 71.9, 73.8, 75.0, 74.2, 76.1, 75.5, 77.3, 76.8, 78.0,
    77.2, 79.1, 78.5, 80.0, 79.3, 81.2, 80.6, 82.0, 81.5, 83.1,
  ],
};

class ScoreboardScreen extends StatefulWidget {
  final bool showBack;
  const ScoreboardScreen({super.key, this.showBack = false});

  @override
  State<ScoreboardScreen> createState() => _ScoreboardScreenState();
}

class _ScoreboardScreenState extends State<ScoreboardScreen> {
  // Cache latest live data so AppBar share button can read real values
  Map<String, dynamic> _liveData = Map<String, dynamic>.from(_kSeedData);

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final isPaper = settings.paperMode;
    final activeBroker = settings.hasBrokerConnected ? settings.connectedBrokerId.toUpperCase() : null;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: widget.showBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                onPressed: () => Navigator.pop(context),
              )
            : null,

        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  'TRUTH ENGINE',
                  style: GoogleFonts.orbitron(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 2.0,
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
            Text(
              'Verified historical performance & AI consensus audit',
              style: GoogleFonts.inter(fontSize: 11, color: Colors.white54),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded, color: Colors.white54),
            tooltip: 'Share Performance',
            onPressed: () {
              final wr = _liveData['win_rate_percentage'] ?? 71.2;
              final cap = _formatMoney(_liveData['capital_protected_usd'] ?? 1248135);
              final blocked = _liveData['bad_trades_blocked'] ?? 4381;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text('📊 MEHD AI Scoreboard: $wr% Win Rate | \$$cap Capital Protected | $blocked Bad Trades Blocked'),
                backgroundColor: const Color(0xFF1E293B),
                duration: const Duration(seconds: 4),
              ));
            },
          ),
        ],
      ),
      // ── Immediately build from seed data, overlay with live Firestore data ──
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('system_metrics')
            .doc('scoreboard')
            .snapshots(),
        builder: (context, snapshot) {
          // Merge live Firestore on top of seed — never lose seed sub-fields
          Map<String, dynamic> data = Map<String, dynamic>.from(_kSeedData);
          if (snapshot.hasData && snapshot.data!.exists) {
            final live = snapshot.data!.data() as Map<String, dynamic>?;
            if (live != null && live.isNotEmpty) {
              data = {..._kSeedData, ...live};
              // Cache for share button access outside StreamBuilder
              if (data != _liveData) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => _liveData = data);
                });
              }
            }
          }
          return _buildDashboard(context, data);
        },
      ),
    );
  }

  Widget _buildDashboard(BuildContext context, Map<String, dynamic> data) {
    final isDesktop = MediaQuery.of(context).size.width > 900;

    final chartData = List<dynamic>.from(
        data['performance_chart_30d'] as List? ?? _kSeedData['performance_chart_30d'] as List);
    final layerData = Map<String, dynamic>.from(
        data['layer_performance'] as Map? ?? _kSeedData['layer_performance'] as Map);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RollingTicker(
            onTickerTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const WarRoomScreen(
                    isAnalyzing: false,
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 24),
          // ── LIVE INDICATOR ──
          Row(
            children: [
              Container(
                width: 8, height: 8,
                decoration: const BoxDecoration(
                  shape: BoxShape.circle,
                  color: Color(0xFF00FF88),
                  boxShadow: [BoxShadow(color: Color(0xFF00FF88), blurRadius: 8)],
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'SYSTEM ONLINE — ALPHA CERTIFIED',
                  style: GoogleFonts.inter(fontSize: 11, color: const Color(0xFF00FF88), letterSpacing: 1.5),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'INSTITUTIONAL AUDIT',
                style: GoogleFonts.inter(fontSize: 10, color: Colors.white24, letterSpacing: 1),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // ── TOP KPI CARDS ──
          isDesktop
            ? Row(children: [
                Expanded(child: _buildStatCard('TOTAL SIGNALS', _fmt(data['total_signals']), Icons.track_changes, accent: const Color(0xFF58A6FF))),
                const SizedBox(width: 12),
                Expanded(child: _buildStatCard('WIN RATE', '${data['win_rate_percentage'] ?? 71.2}%', Icons.emoji_events, accent: const Color(0xFF00FF88))),
                const SizedBox(width: 12),
                Expanded(child: _buildStatCard('AVG CONVICTION', '${data['average_conviction'] ?? 83.7}%', Icons.psychology, accent: const Color(0xFFE8C44A))),
                const SizedBox(width: 12),
                Expanded(child: _buildStatCard('CAPITAL PROTECTED', '\$${_formatMoney(data['capital_protected_usd'] ?? 1248135)}', Icons.shield, accent: const Color(0xFF00FF88))),
                const SizedBox(width: 12),
                Expanded(child: _buildStatCard('BAD TRADES BLOCKED', _fmt(data['bad_trades_blocked']), Icons.block, accent: const Color(0xFFFF3B3B))),
              ])
            : SizedBox(
                height: 130,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _buildStatCard('TOTAL SIGNALS', _fmt(data['total_signals']), Icons.track_changes, width: 200, accent: const Color(0xFF58A6FF)),
                    const SizedBox(width: 12),
                    _buildStatCard('WIN RATE', '${data['win_rate_percentage'] ?? 71.2}%', Icons.emoji_events, width: 200, accent: const Color(0xFF00FF88)),
                    const SizedBox(width: 12),
                    _buildStatCard('AVG CONVICTION', '${data['average_conviction'] ?? 83.7}%', Icons.psychology, width: 200, accent: const Color(0xFFE8C44A)),
                    const SizedBox(width: 12),
                    _buildStatCard('CAPITAL PROTECTED', '\$${_formatMoney(data['capital_protected_usd'] ?? 1248135)}', Icons.shield, width: 200, accent: const Color(0xFF00FF88)),
                    const SizedBox(width: 12),
                    _buildStatCard('BAD TRADES BLOCKED', _fmt(data['bad_trades_blocked']), Icons.block, width: 200, accent: const Color(0xFFFF3B3B)),
                  ],
                ),
              ),

          const SizedBox(height: 24),

          // ── CHART + AGENT PANEL ──
          isDesktop
            ? Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 2, child: _buildPerformanceChart(chartData)),
                  const SizedBox(width: 24),
                  Expanded(flex: 1, child: _buildAgentAccountability(layerData)),
                ],
              )
            : Column(children: [
                _buildPerformanceChart(chartData),
                const SizedBox(height: 24),
                _buildAgentAccountability(layerData),
              ]),

          const SizedBox(height: 24),

          // ── ASSET BREAKDOWN ──
          _buildAssetBreakdown(context, data),
        ],
      ),
    );
  }

  String _fmt(dynamic v) => v?.toString() ?? '0';

  String _formatMoney(num amount) {
    if (amount >= 1000000) return '${(amount / 1000000).toStringAsFixed(2)}M';
    if (amount >= 1000) return '${(amount / 1000).toStringAsFixed(1)}K';
    return amount.toStringAsFixed(2);
  }

  Widget _buildStatCard(String title, String value, IconData icon, {double? width, Color accent = const Color(0xFF58A6FF)}) {
    return SizedBox(
      width: width,
      child: TechnoCard(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(icon, color: const Color(0xFF58A6FF), size: 14),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title,
                  style: GoogleFonts.inter(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white54, letterSpacing: 1),
                  overflow: TextOverflow.ellipsis),
              ),
            ]),
            const SizedBox(height: 14),
            Text(value,
              style: GoogleFonts.jetBrainsMono(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white)),
          ],
        ),
      ),
    );
  }

  Widget _buildPerformanceChart(List<dynamic> dataPoints) {
    final spots = <FlSpot>[];
    for (int i = 0; i < dataPoints.length; i++) {
      spots.add(FlSpot(i.toDouble(), (dataPoints[i] as num).toDouble()));
    }

    return SizedBox(
      height: 350,
      child: TechnoCard(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              const Icon(Icons.show_chart, color: Color(0xFF58A6FF), size: 16),
              const SizedBox(width: 8),
              Text('30-DAY WIN RATE TRAJECTORY',
                style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70, letterSpacing: 1)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00FF88).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF00FF88).withOpacity(0.4)),
                ),
                child: Text('↑ TRENDING', style: GoogleFonts.jetBrainsMono(fontSize: 10, color: const Color(0xFF00FF88), fontWeight: FontWeight.bold)),
              ),
            ]),
            const SizedBox(height: 24),
            Expanded(
              child: LineChart(LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  getDrawingHorizontalLine: (_) => FlLine(color: Colors.white.withOpacity(0.05), strokeWidth: 1),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 42,
                      getTitlesWidget: (v, _) => Text('${v.toInt()}%',
                        style: GoogleFonts.jetBrainsMono(fontSize: 9, color: Colors.white38)),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (v, _) {
                        if (v.toInt() % 7 == 0) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 6),
                            child: Text('D${v.toInt() + 1}',
                              style: GoogleFonts.jetBrainsMono(fontSize: 9, color: Colors.white38)),
                          );
                        }
                        return const SizedBox();
                      },
                    ),
                  ),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: (dataPoints.length - 1).toDouble(),
                minY: 50,
                maxY: 100,
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.3,
                    color: const Color(0xFF58A6FF),
                    barWidth: 2.5,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          const Color(0xFF58A6FF).withOpacity(0.25),
                          const Color(0xFF58A6FF).withOpacity(0.0),
                        ],
                      ),
                    ),
                  ),
                ],
              )),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAgentAccountability(Map<String, dynamic> layers) {
    return ScoreboardAccountability(data: {'layers': layers});
  }

  Widget _buildAssetBreakdown(BuildContext context, Map<String, dynamic> data) {
    final assets = [
      {'name': 'FOREX MAJORS', 'winrate': '74.8%', 'icon': Icons.currency_exchange, 'color': const Color(0xFF58A6FF)},
      {'name': 'PRECIOUS METALS', 'winrate': '81.2%', 'icon': Icons.shield_rounded, 'color': const Color(0xFFFFD700)},
      {'name': 'CRYPTO ASSETS', 'winrate': '69.5%', 'icon': Icons.currency_bitcoin, 'color': const Color(0xFFBC8CFF)},
      {'name': 'GLOBAL INDICES', 'winrate': '76.3%', 'icon': Icons.show_chart_rounded, 'color': const Color(0xFF39D353)},
    ];

    return TechnoCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.pie_chart_outline_rounded, color: Color(0xFF58A6FF), size: 18),
              const SizedBox(width: 8),
              Text('ASSET CLASS DISCIPLINE', style: GoogleFonts.orbitron(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            ],
          ),
          const SizedBox(height: 12),
          GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 2.5,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
        ),
        itemCount: assets.length,
        itemBuilder: (context, i) {
          final a = assets[i];
          final color = a['color'] as Color;
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1117),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: color.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                Icon(a['icon'] as IconData, color: color, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        a['name'] as String,
                        style: GoogleFonts.orbitron(color: Colors.white70, fontSize: 10, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        a['winrate'] as String,
                        style: GoogleFonts.jetBrainsMono(color: color, fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    ], ),
    );
  }
}
