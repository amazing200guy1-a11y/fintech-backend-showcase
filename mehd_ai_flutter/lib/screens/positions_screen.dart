import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/controllers/trading_controller.dart';
import 'package:mehd_ai_flutter/services/settings_service.dart';
import 'package:mehd_ai_flutter/widgets/trade_health_indicator.dart';
import 'package:mehd_ai_flutter/widgets/positions_empty_state.dart';
import 'package:mehd_ai_flutter/widgets/pending_orders_list.dart';

class PositionsScreen extends StatefulWidget {
  const PositionsScreen({super.key});

  @override
  State<PositionsScreen> createState() => _PositionsScreenState();
}

class _PositionsScreenState extends State<PositionsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  final List<Map<String, dynamic>> _pendingOrders = [];

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
    context.read<TradingController>().closePosition(id);
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
    final symbol = (p['symbol'] as String?) ?? '';
    final direction = (p['direction'] ?? p['type'] ?? 'BUY').toString().toUpperCase();
    final entry = (p['entry'] as num?)?.toDouble() ?? 0.0;
    final current = (p['current'] as num?)?.toDouble() ?? entry;
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
    final trading = context.watch<TradingController>();
    final settings = context.watch<SettingsService>();
    final openPositions = trading.activePositions;
    final totalFloatingPnl = openPositions.fold(
      0.0,
      (sum, item) => sum + ((item['pnl'] as num?)?.toDouble() ?? 0.0),
    );
    final balance = settings.accountBalance;
    final equity = balance + totalFloatingPnl;
    final marginUsed = openPositions.length * 50.0;
    final freeMargin = equity - marginUsed;
    final isProfit = totalFloatingPnl >= 0;

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
                    '${isProfit ? '+' : ''}\$${totalFloatingPnl.toStringAsFixed(2)}',
                    style: TextStyle(
                      fontFamily: 'JetBrains Mono',
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                      color: isProfit ? MehdAiTheme.green : MehdAiTheme.red,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  runSpacing: 16,
                  spacing: 16,
                  children: [
                    _buildMiniStat('Equity', '\$${equity.toStringAsFixed(2)}'),
                    _buildMiniStat(
                        'Margin Used', '\$${marginUsed.toStringAsFixed(2)}'),
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
                _buildOpenPositionsList(openPositions),
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

  Widget _buildOpenPositionsList(List<Map<String, dynamic>> openPositions) {
    if (openPositions.isEmpty) {
      return _buildEmptyState(
          Icons.monitor_heart, 'NO ACTIVE POSITIONS', 'The radar is clear.');
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: openPositions.length,
      itemBuilder: (context, index) {
        final p = openPositions[index];
        final directionStr = (p['direction'] ?? p['type'] ?? 'BUY').toString().toUpperCase();
        final isBuy = directionStr == 'BUY';
        final pnlVal = (p['pnl'] as num?)?.toDouble() ?? 0.0;
        final isProfit = pnlVal >= 0;

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
                    directionStr,
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
                        '${p['symbol']}  •  ${p['lots'] ?? p['lotSize'] ?? 1.0} Lots',
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
                        '${isProfit ? '+' : ''}\$${pnlVal.toStringAsFixed(2)}',
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
    return PendingOrdersList(
      pendingOrders: _pendingOrders,
      onCancelOrder: _cancelOrder,
    );
  }
  Widget _buildEmptyState(IconData icon, String title, String subtitle) {
    return PositionsEmptyState(icon: icon, title: title, subtitle: subtitle);
  }
}
