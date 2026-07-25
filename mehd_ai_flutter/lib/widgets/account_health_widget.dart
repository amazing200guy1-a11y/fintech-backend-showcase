import 'package:flutter/material.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/models/account_health.dart';
import 'package:mehd_ai_flutter/models/trade.dart';
import 'package:mehd_ai_flutter/widgets/trade_history_item.dart';

/// FILE 9 — account_health_widget.dart
///
/// Build Debrief:
/// This panel visualizes the HardRiskKernel and the resulting Trade Ledger. 
/// The 3% daily drawdown kill-switch is central to the UI. The bottom half 
/// is a scrolling list of trades, rendering complete transparent audit trails 
/// natively in the UI.

class AccountHealthWidget extends StatelessWidget {
  final AccountHealth? health;
  final List<Trade> recentTrades;

  const AccountHealthWidget({
    super.key, 
    this.health,
    this.recentTrades = const [],
  });

  @override
  Widget build(BuildContext context) {
    if (health == null) {
      return Container(color: MehdAiTheme.bgPrimary);
    }

    return Container(
      color: MehdAiTheme.bgPrimary,
      child: ListView(
        padding: const EdgeInsets.all(24.0),
        children: [
          Text('ACCOUNT STATUS', style: MehdAiTheme.headingStyle, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 24),
          
          _buildStatRow('Balance', '\$${health!.balance.toStringAsFixed(2)}'),
          const SizedBox(height: 12),
          _buildStatRow('Equity', '\$${health!.equity.toStringAsFixed(2)}'),
          
          const SizedBox(height: 32),
          Text('DAILY DRAWDOWN', style: MehdAiTheme.labelStyle, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 8),
          
          _buildDrawdownBar(),
          
          if (health!.isLocked) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: MehdAiTheme.red.withOpacity(0.1),
                border: Border.all(color: MehdAiTheme.red),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: MehdAiTheme.red),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('KILL-SWITCH ACTIVATED', style: MehdAiTheme.headingStyle.copyWith(color: MehdAiTheme.red, fontSize: 14), overflow: TextOverflow.ellipsis),
                        Text(health!.lockReason ?? '3% daily drawdown exceeded. Trading locked.', style: MehdAiTheme.labelStyle.copyWith(color: MehdAiTheme.red), overflow: TextOverflow.ellipsis),
                      ],
                    ),
                  ),
                ],
              ),
            )
          ],
          
          // Trade Ledger Section
          const SizedBox(height: 32),
          Text('TRADE LEDGER', style: MehdAiTheme.headingStyle, overflow: TextOverflow.ellipsis),
          const SizedBox(height: 16),
          
          // UPGRADE 2: AI Stop Guardian Badge
          if (recentTrades.isNotEmpty) ...[
            Container(
              margin: const EdgeInsets.only(bottom: 16),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: MehdAiTheme.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: MehdAiTheme.blue.withOpacity(0.3)),
                boxShadow: MehdAiTheme.blueGlow,
              ),
              child: Row(
                children: [
                  const Icon(Icons.security, color: MehdAiTheme.blue, size: 18),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      '🛡️ Stop Guardian Active — 4 Agents watching EUR/USD',
                      style: MehdAiTheme.labelStyle.copyWith(color: MehdAiTheme.blue, fontWeight: FontWeight.bold),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 12, height: 12,
                    child: CircularProgressIndicator(strokeWidth: 2, valueColor: AlwaysStoppedAnimation<Color>(MehdAiTheme.blue)),
                  )
                ],
              ),
            ),
          ],
          
          if (recentTrades.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(
                child: Text(
                  '24/5 AUTONOMOUS RISK KERNEL ACTIVE\nNO RECENT TRADES EXECUTED',
                  textAlign: TextAlign.center,
                  style: MehdAiTheme.labelStyle.copyWith(color: MehdAiTheme.textSecondary),
                ),
              ),
            )
          else
            ...recentTrades.reversed.map((trade) => TradeHistoryItem(trade: trade)),
        ],
      ),
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Text(
            label, 
            style: MehdAiTheme.labelStyle.copyWith(fontSize: 14),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 16),
        Flexible(child: Text(value, style: MehdAiTheme.priceStyle.copyWith(fontSize: 16), overflow: TextOverflow.ellipsis)),
      ],
    );
  }

  Widget _buildDrawdownBar() {
    double pct = health!.dailyDrawdownPct;
    Color barColor = MehdAiTheme.green;
    if (pct >= 2.0) barColor = MehdAiTheme.yellow;
    if (pct >= 2.8) barColor = MehdAiTheme.red;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        LinearProgressIndicator(
          value: (pct / 3.0).clamp(0.0, 1.0),
          backgroundColor: MehdAiTheme.bgSecondary,
          valueColor: AlwaysStoppedAnimation<Color>(barColor),
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 4),
        Text('${pct.toStringAsFixed(1)}% / 3.0% Max', style: MehdAiTheme.labelStyle, overflow: TextOverflow.ellipsis),
      ],
    );
  }

}
