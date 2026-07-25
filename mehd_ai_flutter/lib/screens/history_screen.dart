import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:provider/provider.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/services/settings_service.dart';
import 'package:mehd_ai_flutter/services/payment_service.dart';
import 'package:mehd_ai_flutter/widgets/missed_signals_card.dart';
import 'dart:ui';

/// History Screen — Institutional-Grade Audit Trail & Transaction Ledger
/// Streams live trade transactions, AI consensus decisions, and system audit events.
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  late AnimationController _orbCtrl;
  bool _dismissedMissedCard = false;

  static const List<Map<String, dynamic>> _kSeedTrades = [
    {
      'symbol': 'EUR/USD',
      'direction': 'BUY',
      'date': 'Today, 14:32',
      'risk': '1.0',
      'profit': 142.50,
      'status': 'CLOSED'
    },
    {
      'symbol': 'GBP/USD',
      'direction': 'SELL',
      'date': 'Today, 11:15',
      'risk': '1.0',
      'profit': -45.00,
      'status': 'CLOSED'
    },
    {
      'symbol': 'XAU/USD',
      'direction': 'BUY',
      'date': 'Yesterday, 18:40',
      'risk': '1.0',
      'profit': 380.00,
      'status': 'CLOSED'
    },
    {
      'symbol': 'BTC/USD',
      'direction': 'BUY',
      'date': 'Yesterday, 09:20',
      'risk': '1.0',
      'profit': 620.10,
      'status': 'CLOSED'
    },
  ];

  static const List<Map<String, dynamic>> _kSeedDecisions = [
    {
      'symbol': 'EUR/USD',
      'date': 'Today, 14:30',
      'proceed': true,
      'consensus_percentage': 94.2,
      'reason': '11/11 Agents approved high-conviction breakout'
    },
    {
      'symbol': 'USD/JPY',
      'date': 'Today, 12:10',
      'proceed': false,
      'consensus_percentage': 58.0,
      'reason': 'Secretary filter blocked due to high-impact CPI news'
    },
    {
      'symbol': 'GBP/USD',
      'date': 'Today, 11:12',
      'proceed': true,
      'consensus_percentage': 88.5,
      'reason': 'Fractal pattern matched 92% historical alignment'
    },
    {
      'symbol': 'NAS100',
      'date': 'Yesterday, 16:05',
      'proceed': false,
      'consensus_percentage': 42.0,
      'reason': 'Spread manipulation detected (spread exceeded 4.5 pips)'
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _orbCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 8))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _orbCtrl.dispose();
    super.dispose();
  }

  Widget _buildGlowOrb(Color color, {double size = 300}) {
    return AnimatedBuilder(
      animation: _orbCtrl,
      builder: (context, child) {
        return Transform.scale(
          scale: 1.0 + (_orbCtrl.value * 0.1),
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
    final uid = FirebaseAuth.instance.currentUser?.uid;

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
                Text(
                  'AUDIT TRAIL & HISTORY',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    letterSpacing: 1.5,
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
          preferredSize: const Size.fromHeight(48),
          child: Container(
            color: MehdAiTheme.bgSecondary,
            child: TabBar(
              controller: _tabController,
              indicatorColor: MehdAiTheme.blue,
              indicatorWeight: 3,
              labelColor: MehdAiTheme.blue,
              unselectedLabelColor: MehdAiTheme.textSecondary,
              labelStyle: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              unselectedLabelStyle: GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w600),
              tabs: const [
                Tab(text: 'TRADES'),
                Tab(text: 'DECISIONS'),
                Tab(text: 'EVENTS'),
              ],
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          // Background ambient glows
          Positioned(
            top: -100,
            left: -100,
            child: _buildGlowOrb(MehdAiTheme.blue.withOpacity(0.06)),
          ),
          Positioned(
            bottom: -150,
            right: -100,
            child: _buildGlowOrb(MehdAiTheme.purple.withOpacity(0.04)),
          ),

          TabBarView(
            controller: _tabController,
            children: [
              _buildTradesStream(uid),
              _buildDecisionsStream(uid),
              _eventsTab(settings, isPaper, activeBroker),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTradesStream(String? uid) {
    if (uid == null) {
      return _tradesTab(_kSeedTrades);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('trade_history')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        List<Map<String, dynamic>> trades = _kSeedTrades;
        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          trades = snapshot.data!.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();
        }
        return _tradesTab(trades);
      },
    );
  }

  Widget _tradesTab(List<Map<String, dynamic>> trades) {
    final payment = context.watch<PaymentService>();
    final isFree = payment.currentTier.toLowerCase() == 'observer';
    final showMissed = isFree && !_dismissedMissedCard;

    if (trades.isEmpty && !showMissed) {
      return _emptyState('NO TRADES DETECTED', 'Executed broker transactions will load dynamically');
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: trades.length + (showMissed ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (showMissed && i == 0) {
          return MissedSignalsCard(
            missedCount: 14,
            exampleMissed: 'XAU/USD BUY @ 2350.40',
            onDismiss: () => setState(() => _dismissedMissedCard = true),
          );
        }

        final index = showMissed ? i - 1 : i;
        if (index < 0 || index >= trades.length) return const SizedBox.shrink();

        final t = trades[index];
        final profit = (t['profit'] as num?)?.toDouble() ?? 0;
        final isProfit = profit >= 0;
        final themeColor = isProfit ? MehdAiTheme.green : MehdAiTheme.red;

        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: themeColor.withOpacity(0.03),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: themeColor.withOpacity(0.15)),
                boxShadow: [
                  BoxShadow(color: themeColor.withOpacity(0.01), blurRadius: 10),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: themeColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: themeColor.withOpacity(0.2)),
                    ),
                    child: Icon(
                      t['direction'] == 'BUY' ? Icons.trending_up : Icons.trending_down,
                      color: themeColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              t['symbol'] ?? 'N/A',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildMiniChip(
                              t['direction'] ?? 'N/A',
                              themeColor,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(
                              t['date'] ?? 'Just now',
                              style: MehdAiTheme.labelStyle.copyWith(fontSize: 10),
                            ),
                            const SizedBox(width: 8),
                            Container(width: 3, height: 3, decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white24)),
                            const SizedBox(width: 8),
                            Text(
                              'Risk: ${t['risk'] ?? '1.0'}%',
                              style: MehdAiTheme.labelStyle.copyWith(fontSize: 10, color: MehdAiTheme.textSecondary),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'P&L',
                        style: MehdAiTheme.labelStyle.copyWith(fontSize: 9, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${isProfit ? '+' : ''}\$${profit.toStringAsFixed(2)}',
                        style: GoogleFonts.jetBrainsMono(
                          color: themeColor,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildDecisionsStream(String? uid) {
    if (uid == null) {
      return _decisionsTab(_kSeedDecisions);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('consensus_history')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        List<Map<String, dynamic>> decisions = _kSeedDecisions;
        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          decisions = snapshot.data!.docs.map((doc) => doc.data() as Map<String, dynamic>).toList();
        }
        return _decisionsTab(decisions);
      },
    );
  }

  Widget _decisionsTab(List<Map<String, dynamic>> decisions) {
    if (decisions.isEmpty) {
      return _emptyState('NO DECISIONS LOGGED', 'Consensus telemetry reports will render here');
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: decisions.length,
      itemBuilder: (ctx, i) {
        final d = decisions[i];
        final consensus = (d['consensus_percentage'] as num?)?.toDouble() ?? 0;
        final proceed = d['proceed'] as bool? ?? false;
        final themeColor = proceed ? MehdAiTheme.green : MehdAiTheme.red;

        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: themeColor.withOpacity(0.02),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: themeColor.withOpacity(0.12)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: themeColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: themeColor.withOpacity(0.2)),
                    ),
                    child: Icon(
                      proceed ? Icons.verified_user_outlined : Icons.gpp_bad_outlined,
                      color: themeColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              d['symbol'] ?? 'N/A',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildMiniChip(
                              proceed ? 'PASSED' : 'BLOCKED',
                              themeColor,
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          d['reason'] ?? d['date'] ?? 'Consensus evaluated',
                          style: MehdAiTheme.labelStyle.copyWith(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'CONSENSUS',
                        style: MehdAiTheme.labelStyle.copyWith(fontSize: 9, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${consensus.toStringAsFixed(0)}%',
                        style: GoogleFonts.jetBrainsMono(
                          color: proceed ? MehdAiTheme.green : MehdAiTheme.yellow,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMiniChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(
        label,
        style: GoogleFonts.jetBrainsMono(
          color: color,
          fontSize: 8,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _eventsTab(SettingsService settings, bool isPaper, String? activeBroker) {
    // Dynamic system audit events derived from actual user configuration
    final events = [
      {
        'type': 'info',
        'title': 'Account Gateway Initialized',
        'desc': 'Welcome to MEHD AI institutional trading framework.',
        'time': 'System Boot'
      },
      {
        'type': 'setting',
        'title': 'Risk Profile Hardened',
        'desc': 'Risk per trade configured to ${settings.riskPerTrade.toStringAsFixed(1)}% (Stop-Loss ${settings.defaultStopLoss.toStringAsFixed(1)} pips).',
        'time': 'Active Config'
      },
      {
        'type': 'success',
        'title': isPaper ? 'Paper Mode Active' : 'Live Execution Pipeline Active',
        'desc': isPaper
            ? 'Sniping signals using \$${settings.accountBalance.toStringAsFixed(0)} demo balance.'
            : 'Live signals connected to real capital execution engine.',
        'time': 'Active State'
      },
      {
        'type': activeBroker != null ? 'success' : 'info',
        'title': activeBroker != null ? 'Broker Connection Shielded' : 'Broker Gateway Unlinked',
        'desc': activeBroker != null
            ? 'Connected to $activeBroker with anti-manipulation filters armed.'
            : 'No live broker connected yet. Running in isolated mode.',
        'time': 'Broker State'
      },
    ];

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(24),
      itemCount: events.length,
      itemBuilder: (ctx, i) {
        final e = events[i];
        IconData icon;
        Color color;
        switch (e['type']) {
          case 'lock':
            icon = Icons.lock;
            color = MehdAiTheme.red;
            break;
          case 'setting':
            icon = Icons.settings;
            color = MehdAiTheme.blue;
            break;
          case 'success':
            icon = Icons.verified;
            color = MehdAiTheme.green;
            break;
          default:
            icon = Icons.info_outline;
            color = MehdAiTheme.textSecondary;
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                AnimatedBuilder(
                  animation: _orbCtrl,
                  builder: (_, __) {
                    return Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.08),
                        shape: BoxShape.circle,
                        border: Border.all(color: color.withOpacity(0.3 + (_orbCtrl.value * 0.2))),
                        boxShadow: [
                          BoxShadow(color: color.withOpacity(0.08), blurRadius: 10),
                        ],
                      ),
                      child: Icon(icon, color: color, size: 16),
                    );
                  },
                ),
                if (i < events.length - 1)
                  Container(
                    width: 1.5,
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [color.withOpacity(0.3), Colors.white.withOpacity(0.03)],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24, top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            e['title']!,
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          e['time']!,
                          style: MehdAiTheme.labelStyle.copyWith(
                            fontSize: 9,
                            color: MehdAiTheme.textSecondary.withOpacity(0.4),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      e['desc']!,
                      style: MehdAiTheme.labelStyle.copyWith(fontSize: 12, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _emptyState(String title, String subtitle) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withOpacity(0.01),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: Icon(
                Icons.folder_open_outlined,
                size: 40,
                color: MehdAiTheme.textSecondary.withOpacity(0.3),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: GoogleFonts.outfit(
                color: Colors.white60,
                fontSize: 14,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: MehdAiTheme.labelStyle.copyWith(fontSize: 12, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }
}
