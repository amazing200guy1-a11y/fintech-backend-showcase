import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mehd_ai_flutter/controllers/trading_controller.dart';
import 'package:mehd_ai_flutter/services/settings_service.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'dart:ui';

/// Sovereign Community (Network Screen)
/// Displays top community nodes and a live stream of consensus trades.
class NetworkScreen extends StatefulWidget {
  const NetworkScreen({super.key});

  @override
  State<NetworkScreen> createState() => _NetworkScreenState();
}

class _NetworkScreenState extends State<NetworkScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  static const List<Map<String, dynamic>> _kGeneralsSeed = [
    {"rank": 1, "name": "Vanguard Capital", "winRate": 94.2, "pnl": 1250430.50},
    {"rank": 2, "name": "Apex Quant", "winRate": 91.8, "pnl": 984200.00},
    {"rank": 3, "name": "Sandbox Node 0x9", "winRate": 89.5, "pnl": 850100.25},
    {"rank": 4, "name": "Citadel Alpha", "winRate": 88.1, "pnl": 720050.00},
    {"rank": 5, "name": "Retail Killer", "winRate": 85.0, "pnl": 450000.00},
  ];

  static const List<Map<String, dynamic>> _kFeedSeed = [
    {
      "trader": "Apex Quant",
      "action": "SHORT",
      "symbol": "EUR/USD",
      "price": 1.0852,
      "time": "2m ago"
    },
    {
      "trader": "Retail Killer",
      "action": "LONG",
      "symbol": "EUR/USD",
      "price": 1.0848,
      "time": "5m ago"
    },
    {
      "trader": "Vanguard Capital",
      "action": "SHORT",
      "symbol": "GBP/USD",
      "price": 1.2980,
      "time": "12m ago"
    },
    {
      "trader": "Retail Killer",
      "action": "SHORT",
      "symbol": "GBP/USD",
      "price": 1.2975,
      "time": "18m ago"
    },
    {
      "trader": "Vanguard Capital",
      "action": "LONG",
      "symbol": "BTC/USD",
      "price": 64250.00,
      "time": "25m ago"
    },
    {
      "trader": "Citadel Alpha",
      "action": "SHORT",
      "symbol": "XAU/USD",
      "price": 2415.50,
      "time": "32m ago"
    },
  ];

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
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
          scale: 1.0 + (_animController.value * 0.15),
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

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final isPaper = settings.paperMode;
    final activeBroker =
        settings.hasBrokerConnected ? settings.connectedBrokerId.toUpperCase() : null;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('system_metrics')
          .doc('community_feed')
          .snapshots(),
      builder: (context, snapshot) {
        List<Map<String, dynamic>> feedItems = _kFeedSeed;
        List<Map<String, dynamic>> generals = _kGeneralsSeed;

        if (snapshot.hasData && snapshot.data!.exists) {
          final data = snapshot.data!.data() as Map<String, dynamic>?;
          if (data != null) {
            if (data['feed'] is List) {
              feedItems = (data['feed'] as List).cast<Map<String, dynamic>>();
            }
            if (data['generals'] is List) {
              generals = (data['generals'] as List).cast<Map<String, dynamic>>();
            }
          }
        }

        return Scaffold(
          backgroundColor: MehdAiTheme.background(context),
          body: Stack(
            children: [
              // Ambient Glow Orbs
              Positioned(
                top: -100,
                left: -50,
                child: _buildGlowOrb(MehdAiTheme.gold.withOpacity(0.1)),
              ),
              Positioned(
                bottom: -150,
                right: -100,
                child: _buildGlowOrb(MehdAiTheme.shieldColor.withOpacity(0.08)),
              ),

              SafeArea(
                child: Column(
                  children: [
                    _buildHeaderRow(context, isPaper, activeBroker),
                    const SizedBox(height: 16),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          if (constraints.maxWidth < 700) {
                            return Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 16.0),
                              child: SingleChildScrollView(
                                child: Column(
                                  children: [
                                    _buildLeaderboard(generals),
                                    const SizedBox(height: 16),
                                    SizedBox(
                                      height: 450,
                                      child: _buildAlphaFeed(feedItems, settings),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }
                          return Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16.0),
                            child: Row(
                              children: [
                                Expanded(
                                    flex: 4,
                                    child: _buildLeaderboard(generals)),
                                const SizedBox(width: 16),
                                Expanded(
                                    flex: 6,
                                    child: _buildAlphaFeed(feedItems, settings)),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeaderRow(
      BuildContext context, bool isPaper, String? activeBroker) {
    // This is a main navigation screen — back arrow is NEVER shown here.
    // It only appears when this screen is pushed on top of another route
    // (which currently never happens). Navigator.canPop() always returns true
    // inside the app so it cannot be used as a guard.

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          height: 54,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          decoration: BoxDecoration(
            color: MehdAiTheme.text(context).withOpacity(0.02),
            border:
                Border(bottom: BorderSide(color: MehdAiTheme.border(context))),
          ),
          child: Row(
            children: [
              const Icon(Icons.groups_rounded, color: MehdAiTheme.gold, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Row(
                  children: [
                    Text("SOVEREIGN COMMUNITY",
                        style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: MehdAiTheme.gold,
                            letterSpacing: 1.5),
                        overflow: TextOverflow.ellipsis),
                    if (isPaper) ...[
                      const SizedBox(width: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF58A6FF).withOpacity(0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: const Color(0xFF58A6FF).withOpacity(0.4)),
                        ),
                        child: const Text('PAPER',
                            style: TextStyle(
                                color: Color(0xFF58A6FF),
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 1.5)),
                      ),
                    ],
                    if (activeBroker != null) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFF00FF88).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: const Color(0xFF00FF88).withOpacity(0.3)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.shield,
                                color: Color(0xFF00FF88), size: 10),
                            const SizedBox(width: 4),
                            Text(activeBroker,
                                style: const TextStyle(
                                    color: Color(0xFF00FF88),
                                    fontSize: 9,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1)),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLeaderboard(List<Map<String, dynamic>> generals) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: MehdAiTheme.surface(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: MehdAiTheme.border(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.leaderboard_rounded,
                      color: MehdAiTheme.gold, size: 18),
                  const SizedBox(width: 8),
                  Text("GLOBAL GENERALS",
                      style: MehdAiTheme.terminalStyle.copyWith(
                          color: MehdAiTheme.gold,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1)),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                      flex: 1, child: Text("RANK", style: MehdAiTheme.labelStyle)),
                  Expanded(
                      flex: 4, child: Text("NODE", style: MehdAiTheme.labelStyle)),
                  Expanded(
                      flex: 2, child: Text("WIN %", style: MehdAiTheme.labelStyle)),
                  Expanded(
                      flex: 3,
                      child: Text("TOTAL PNL",
                          style: MehdAiTheme.labelStyle,
                          textAlign: TextAlign.right)),
                ],
              ),
              Divider(color: MehdAiTheme.border(context), height: 16),
              ...generals.asMap().entries.map((entry) {
                final index = entry.key;
                final gen = entry.value;
                final winRate = (gen['winRate'] as num?)?.toDouble() ?? 0.0;
                final pnl = (gen['pnl'] as num?)?.toDouble() ?? 0.0;

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10.0),
                  child: Row(
                    children: [
                      Expanded(
                          flex: 1,
                          child: Text("#${gen['rank'] ?? (index + 1)}",
                              style: MehdAiTheme.terminalStyle.copyWith(
                                  color: index == 0
                                      ? MehdAiTheme.gold
                                      : MehdAiTheme.textDim(context)))),
                      Expanded(
                          flex: 4,
                          child: Text(gen['name']?.toString() ?? 'Node',
                              style: MehdAiTheme.terminalStyle.copyWith(
                                  color: MehdAiTheme.text(context),
                                  fontWeight:
                                      index == 0 ? FontWeight.bold : null))),
                      Expanded(
                          flex: 2,
                          child: Text("${winRate.toStringAsFixed(1)}%",
                              style: MehdAiTheme.dataMono
                                  .copyWith(color: MehdAiTheme.green))),
                      Expanded(
                          flex: 3,
                          child: Text("\$${_formatPnl(pnl)}",
                              style: MehdAiTheme.dataMono
                                  .copyWith(color: MehdAiTheme.gold),
                              textAlign: TextAlign.right)),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  String _formatPnl(double val) {
    if (val >= 1000000) return '${(val / 1000000).toStringAsFixed(2)}M';
    if (val >= 1000) return '${(val / 1000).toStringAsFixed(0)}K';
    return val.toStringAsFixed(0);
  }

  Widget _buildAlphaFeed(
      List<Map<String, dynamic>> feedItems, SettingsService settings) {
    final isSandbox = settings.sandboxMode;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: MehdAiTheme.surface(context),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: MehdAiTheme.border(context)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.sensors_rounded,
                          color: MehdAiTheme.shieldColor, size: 18),
                      const SizedBox(width: 8),
                      Text("LIVE ALPHA STREAM",
                          style: MehdAiTheme.terminalStyle.copyWith(
                              color: MehdAiTheme.shieldColor,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1)),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isSandbox)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 4),
                          margin: const EdgeInsets.only(right: 8),
                          decoration: BoxDecoration(
                            color: MehdAiTheme.purple.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text("SANDBOX ACTIVE",
                              style: MehdAiTheme.terminalStyle.copyWith(
                                  color: MehdAiTheme.purple, fontSize: 10)),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: MehdAiTheme.shieldColor.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text("LIVE SYNC",
                            style: MehdAiTheme.terminalStyle.copyWith(
                                color: MehdAiTheme.shieldColor, fontSize: 10)),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ListView.builder(
                  itemCount: feedItems.length,
                  itemBuilder: (context, index) {
                    final item = feedItems[index];
                    final trader = item['trader']?.toString() ?? 'Node Trader';
                    final action = item['action']?.toString() ?? 'LONG';
                    final symbol = item['symbol']?.toString() ?? 'EUR/USD';
                    final price = (item['price'] as num?)?.toDouble() ?? 1.0850;
                    final isBuy = action == 'LONG';

                    return Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: MehdAiTheme.text(context).withOpacity(0.02),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: MehdAiTheme.border(context)),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 3,
                            height: 30,
                            color: isBuy ? MehdAiTheme.green : MehdAiTheme.red,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text("$trader executed a consensus trade",
                                    style: MehdAiTheme.labelStyle),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Text(action,
                                        style: MehdAiTheme.terminalStyle.copyWith(
                                            color: isBuy
                                                ? MehdAiTheme.green
                                                : MehdAiTheme.red,
                                            fontWeight: FontWeight.bold)),
                                    const SizedBox(width: 8),
                                    Text(symbol,
                                        style: MehdAiTheme.terminalStyle
                                            .copyWith(color: MehdAiTheme.text(context))),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          _buildSandboxButton(symbol, action, price),
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

  Widget _buildSandboxButton(
      String symbol, String direction, double entryPrice) {
    return GestureDetector(
      onTap: () {
        context
            .read<TradingController>()
            .executeSandboxTrade(symbol, direction, entryPrice);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text("⚡ Sandbox trade ($direction $symbol) queued for execution.",
              style: MehdAiTheme.terminalStyle
                  .copyWith(color: MehdAiTheme.text(context))),
          backgroundColor: MehdAiTheme.surface(context),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ));
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: MehdAiTheme.purple.withOpacity(0.1),
          border: Border.all(color: MehdAiTheme.purple.withOpacity(0.5)),
          borderRadius: BorderRadius.circular(8),
          boxShadow: [
            BoxShadow(
                color: MehdAiTheme.purple.withOpacity(0.2), blurRadius: 8),
          ],
        ),
        child: Text("SANDBOX",
            style: MehdAiTheme.terminalStyle.copyWith(
                color: MehdAiTheme.purple,
                fontWeight: FontWeight.bold,
                fontSize: 11)),
      ),
    );
  }
}
