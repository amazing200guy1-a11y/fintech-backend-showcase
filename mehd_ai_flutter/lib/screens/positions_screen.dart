import 'package:flutter/material.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/widgets/trade_health_indicator.dart';

class PositionsScreen extends StatefulWidget {
  const PositionsScreen({super.key});

  @override
  State<PositionsScreen> createState() => _PositionsScreenState();
}

class _PositionsScreenState extends State<PositionsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Mock Data
  final double _balance = 10450.00;
  final double _marginUsed = 250.00;
  double _totalFloatingPnl = 124.50; // Dynamic

  final List<Map<String, dynamic>> _openPositions = [
    {
      'id': '1',
      'symbol': 'EUR/USD',
      'direction': 'BUY',
      'lots': 0.5,
      'entry': 1.0850,
      'current': 1.0875,
      'pnl': 125.00,
      'timestamp': DateTime.now().subtract(const Duration(hours: 2)).toIso8601String(),
    },
    {
      'id': '2',
      'symbol': 'GBP/JPY',
      'direction': 'SELL',
      'lots': 0.2,
      'entry': 190.50,
      'current': 190.51,
      'pnl': -0.50,
      'timestamp': DateTime.now().subtract(const Duration(hours: 5)).toIso8601String(),
    },
  ];

  final List<Map<String, dynamic>> _pendingOrders = [
    {
      'id': '3',
      'symbol': 'XAU/USD',
      'type': 'Buy Limit',
      'lots': 0.1,
      'target': 2300.00
    },
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _closePosition(String id) {
    setState(() {
      _openPositions.removeWhere((p) => p['id'] == id);
      // Recalculate PnL
      _totalFloatingPnl = _openPositions.fold(
          0.0, (sum, item) => sum + (item['pnl'] as double));
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Position Closed Successfully',
            style: TextStyle(fontFamily: 'JetBrains Mono')),
        backgroundColor: MehdAiTheme.green.withOpacity(0.8),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _cancelOrder(String id) {
    setState(() {
      _pendingOrders.removeWhere((o) => o['id'] == id);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Pending Order Cancelled',
            style: TextStyle(fontFamily: 'JetBrains Mono')),
        backgroundColor: MehdAiTheme.textSecondary,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  double _getPipSize(String symbol) {
    final sym = symbol.toUpperCase().replaceAll('/', '');
    if (sym.contains('XAU')) {
      return 0.01;
    }
    if (sym.contains('JPY')) {
      return 0.01;
    }
    return 0.0001;
  }

  int _calculateHealthScore(Map<String, dynamic> p) {
    final symbol = p['symbol'] as String;
    final direction = p['direction'] as String;
    final entry = p['entry'] as double;
    final current = p['current'] as double;
    final timestampStr = p['timestamp'] as String?;

    final pipSize = _getPipSize(symbol);
    if (pipSize <= 0) return 100;

    double pipDiff = (current - entry) / pipSize;
    if (direction.toUpperCase() == 'SELL') {
      pipDiff = -pipDiff;
    }

    double health = 100.0;

    // Penalty for drawdown (30 pips = -45% health)
    if (pipDiff < 0) {
      health -= (pipDiff.abs() * 1.5).clamp(0.0, 60.0);
    } else {
      // Bonus for profit (capped)
      health += (pipDiff * 0.5).clamp(0.0, 10.0);
    }

    // Time decay
    if (timestampStr != null) {
      try {
        final entryTime = DateTime.parse(timestampStr);
        final hoursIn = DateTime.now().difference(entryTime).inSeconds / 3600.0;
        health -= (hoursIn * 1.5); // -1.5% per hour
      } catch (_) {}
    }

    return health.clamp(0.0, 100.0).round();
  }

  @override
  Widget build(BuildContext context) {
    final equity = _balance + _totalFloatingPnl;
    final freeMargin = equity - _marginUsed;
    final isProfit = _totalFloatingPnl >= 0;

    return Scaffold(
      backgroundColor: MehdAiTheme.background(context),
      appBar: AppBar(
        backgroundColor: MehdAiTheme.surface(context),
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.radar, color: MehdAiTheme.blue, size: 20),
            const SizedBox(width: 8),
            Text('ACTIVE RADAR', style: MehdAiTheme.labelStyle),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: MehdAiTheme.blue,
          labelColor: MehdAiTheme.blue,
          unselectedLabelColor: MehdAiTheme.textSecondary,
          labelStyle: MehdAiTheme.labelStyle.copyWith(fontSize: 11),
          isScrollable: true,
          tabAlignment: TabAlignment.center,
          tabs: const [
            Tab(text: 'OPEN POSITIONS'),
            Tab(text: 'PENDING ORDERS'),
          ],
        ),
      ),
      body: Column(
        children: [
          // ── RULE 9: MOCK DATA BANNER ──
          // All positions data below is hardcoded mock data.
          // This banner MUST remain until real broker data is wired.
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: MehdAiTheme.amber.withOpacity(0.08),
            child: Row(
              children: [
                Icon(Icons.science_outlined, color: MehdAiTheme.amber, size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "EXPERIMENTAL — Simulated positions. Not connected to broker.",
                    style: TextStyle(
                      color: MehdAiTheme.amber,
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Hero Summary Dashboard
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: MehdAiTheme.surface(context),
              border: Border(
                  bottom: BorderSide(color: MehdAiTheme.border(context))),
            ),
            child: Column(
              children: [
                Text('FLOATING P&L',
                    style: MehdAiTheme.labelStyle
                        .copyWith(color: MehdAiTheme.textSecondary)),
                const SizedBox(height: 8),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '${isProfit ? '+' : ''}\$${_totalFloatingPnl.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                      color: isProfit ? MehdAiTheme.green : MehdAiTheme.red,
                      shadows: [
                        BoxShadow(
                          color: (isProfit ? MehdAiTheme.green : MehdAiTheme.red)
                              .withOpacity(0.3),
                          blurRadius: 20,
                        )
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  runSpacing: 16,
                  spacing: 16,
                  children: [
                    _buildMiniStat('Equity', '\$${equity.toStringAsFixed(2)}'),
                    _buildMiniStat(
                        'Margin Used', '\$${_marginUsed.toStringAsFixed(2)}'),
                    _buildMiniStat(
                        'Free Margin', '\$${freeMargin.toStringAsFixed(2)}'),
                  ],
                ),
              ],
            ),
          ),

          // Tab Content
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildOpenPositionsList(),
                _buildPendingOrdersList(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: MehdAiTheme.labelStyle
                .copyWith(fontSize: 10, color: MehdAiTheme.textSecondary)),
        const SizedBox(height: 4),
        Text(value,
            style: const TextStyle(
                fontFamily: 'JetBrains Mono',
                fontSize: 13,
                color: Colors.white,
                fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildOpenPositionsList() {
    if (_openPositions.isEmpty) {
      return _buildEmptyState(
          Icons.monitor_heart, 'NO ACTIVE POSITIONS', 'The radar is clear.');
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _openPositions.length,
      itemBuilder: (context, index) {
        final p = _openPositions[index];
        final isBuy = p['direction'] == 'BUY';
        final isProfit = (p['pnl'] as double) >= 0;

        return Dismissible(
          key: Key(p['id']),
          direction: DismissDirection.endToStart,
          confirmDismiss: (direction) async {
            return await showDialog<bool>(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  backgroundColor: MehdAiTheme.surface(context),
                  title: Text('CLOSE POSITION?', style: MehdAiTheme.headingStyle.copyWith(fontSize: 16)),
                  content: Text('Are you sure you want to close this position?', style: MehdAiTheme.labelStyle),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('CANCEL', style: TextStyle(color: Colors.grey, fontFamily: 'JetBrains Mono')),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: MehdAiTheme.red),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('CLOSE', style: TextStyle(color: Colors.white, fontFamily: 'JetBrains Mono')),
                    ),
                  ],
                );
              },
            );
          },
          onDismissed: (direction) => _closePosition(p['id']),
          background: Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: MehdAiTheme.red.withOpacity(0.8),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            child: const Icon(Icons.close, color: Colors.white),
          ),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.02),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isBuy ? MehdAiTheme.green : MehdAiTheme.red)
                        .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    p['direction'],
                    style: TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isBuy ? MehdAiTheme.green : MehdAiTheme.red,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${p['symbol']}  •  ${p['lots']} Lots',
                        style: const TextStyle(
                            fontFamily: 'JetBrains Mono',
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${p['entry']} ➔ ${p['current']}',
                        style: TextStyle(
                            fontFamily: 'JetBrains Mono',
                            fontSize: 11,
                            color: MehdAiTheme.textSecondary),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        '${isProfit ? '+' : ''}\$${(p['pnl'] as double).toStringAsFixed(2)}',
                        style: TextStyle(
                          fontFamily: 'JetBrains Mono',
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isProfit ? MehdAiTheme.green : MehdAiTheme.red,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    TradeHealthIndicator(healthScore: _calculateHealthScore(p)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPendingOrdersList() {
    if (_pendingOrders.isEmpty) {
      return _buildEmptyState(Icons.pending_actions, 'NO PENDING ORDERS',
          'No orders waiting in the queue.');
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _pendingOrders.length,
      itemBuilder: (context, index) {
        final o = _pendingOrders[index];
        final type = o['type'] as String;
        final isBuy = type.contains('Buy');

        return Dismissible(
          key: Key(o['id']),
          direction: DismissDirection.endToStart,
          confirmDismiss: (direction) async {
            return await showDialog<bool>(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  backgroundColor: MehdAiTheme.surface(context),
                  title: Text('CANCEL ORDER?', style: MehdAiTheme.headingStyle.copyWith(fontSize: 16)),
                  content: Text('Are you sure you want to cancel this pending order?', style: MehdAiTheme.labelStyle),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('KEEP', style: TextStyle(color: Colors.grey, fontFamily: 'JetBrains Mono')),
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(backgroundColor: MehdAiTheme.textSecondary),
                      onPressed: () => Navigator.of(context).pop(true),
                      child: const Text('CANCEL ORDER', style: TextStyle(color: Colors.white, fontFamily: 'JetBrains Mono')),
                    ),
                  ],
                );
              },
            );
          },
          onDismissed: (direction) => _cancelOrder(o['id']),
          background: Container(
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: MehdAiTheme.textSecondary.withOpacity(0.8),
              borderRadius: BorderRadius.circular(12),
            ),
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: 24),
            child: const Icon(Icons.delete_outline, color: Colors.white),
          ),
          child: Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.02),
              border: Border.all(color: Colors.white.withOpacity(0.05)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: (isBuy ? MehdAiTheme.green : MehdAiTheme.red)
                        .withOpacity(0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    type.toUpperCase(),
                    style: TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                      color: isBuy ? MehdAiTheme.green : MehdAiTheme.red,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${o['symbol']}  •  ${o['lots']} Lots',
                        style: const TextStyle(
                            fontFamily: 'JetBrains Mono',
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Target: ${o['target']}',
                        style: const TextStyle(
                            fontFamily: 'JetBrains Mono',
                            fontSize: 11,
                            color: MehdAiTheme.blue),
                      ),
                    ],
                  ),
                ),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('WAITING',
                        style: TextStyle(
                            fontFamily: 'JetBrains Mono',
                            fontSize: 12,
                            color: Colors.grey,
                            fontWeight: FontWeight.bold)),
                    SizedBox(height: 4),
                    Text('Swipe to Cancel ⟵',
                        style: TextStyle(fontSize: 9, color: Colors.grey)),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(IconData icon, String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Institutional radar/lock visual
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: MehdAiTheme.blue.withOpacity(0.1),
                    width: 2,
                  ),
                ),
              ),
              Container(
                width: 60,
                height: 60,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: MehdAiTheme.blue.withOpacity(0.3),
                    width: 1,
                  ),
                ),
              ),
              Icon(
                icon,
                size: 32,
                color: MehdAiTheme.blue.withOpacity(0.5),
              ),
            ],
          ),
          const SizedBox(height: 32),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            decoration: BoxDecoration(
              color: MehdAiTheme.blue.withOpacity(0.05),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: MehdAiTheme.blue.withOpacity(0.2)),
            ),
            child: Text(
              'RADAR CLEAR',
              style: MehdAiTheme.terminalStyle.copyWith(
                color: MehdAiTheme.blue.withOpacity(0.8),
                fontSize: 10,
                letterSpacing: 2,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title.toUpperCase(),
            style: MehdAiTheme.headingStyle.copyWith(
              fontSize: 16,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle.toUpperCase(),
            style: MehdAiTheme.terminalStyle.copyWith(
              fontSize: 11,
              color: MehdAiTheme.textSecondary.withOpacity(0.7),
              letterSpacing: 1,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
