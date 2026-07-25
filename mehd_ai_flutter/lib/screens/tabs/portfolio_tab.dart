import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/services/settings_service.dart';
import 'dart:ui';

class PortfolioTab extends StatelessWidget {
  const PortfolioTab({super.key});

  @override
  Widget build(BuildContext context) {
    // Mocked data for now, would fetch from OANDA / Account Health
    final List<Map<String, dynamic>> positions = [];
    final settings = context.watch<SettingsService>();
    final balanceStr = '\$${settings.accountBalance.toStringAsFixed(0)}';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 100),
      children: [
        // Header
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: MehdAiTheme.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: MehdAiTheme.blue.withOpacity(0.2)),
              ),
              child: const Icon(Icons.pie_chart, color: MehdAiTheme.blue, size: 22),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("OPEN POSITIONS", style: MehdAiTheme.headingStyle.copyWith(fontSize: 16)),
                  const SizedBox(height: 4),
                  Text("Live portfolio state from broker", style: MehdAiTheme.labelStyle.copyWith(fontSize: 12)),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),

        // Account Summary Card
        _buildAccountSummary(balanceStr),
        const SizedBox(height: 24),

        if (positions.isEmpty)
          _buildEmptyState()
        else
          ...positions.map((p) => _buildPositionTile(context, p)),
      ],
    );
  }

  Widget _buildAccountSummary(String balanceStr) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 500;
        final cards = [
          _buildMiniMetric('EQUITY', balanceStr, MehdAiTheme.blue),
          _buildMiniMetric('MARGIN USED', '\$0.00', MehdAiTheme.textSecondary),
          _buildMiniMetric('FREE MARGIN', balanceStr, MehdAiTheme.green),
          _buildMiniMetric('UNREALIZED P&L', '\$0.00', MehdAiTheme.textSecondary),
        ];

        if (isMobile) {
          return Column(
            children: [
              Row(children: [Expanded(child: cards[0]), const SizedBox(width: 10), Expanded(child: cards[1])]),
              const SizedBox(height: 10),
              Row(children: [Expanded(child: cards[2]), const SizedBox(width: 10), Expanded(child: cards[3])]),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: cards[0]),
            const SizedBox(width: 10),
            Expanded(child: cards[1]),
            const SizedBox(width: 10),
            Expanded(child: cards[2]),
            const SizedBox(width: 10),
            Expanded(child: cards[3]),
          ],
        );
      },
    );
  }

  Widget _buildMiniMetric(String label, String value, Color color) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(MehdAiTheme.borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: color.withOpacity(0.05),
            borderRadius: BorderRadius.circular(MehdAiTheme.borderRadius),
            border: Border.all(color: color.withOpacity(0.14)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: MehdAiTheme.labelStyle.copyWith(fontSize: 11, letterSpacing: 0.6)),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(value, style: GoogleFonts.jetBrainsMono(color: color, fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.02),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: MehdAiTheme.blue.withOpacity(0.06),
                  border: Border.all(color: MehdAiTheme.blue.withOpacity(0.15)),
                ),
                child: const Icon(Icons.account_balance_wallet_outlined, color: MehdAiTheme.blue, size: 36),
              ),
              const SizedBox(height: 20),
              Text(
                'NO ACTIVE POSITIONS',
                style: GoogleFonts.outfit(color: Colors.white54, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 1),
              ),
              const SizedBox(height: 8),
              Text(
                'The Den is scanning for high-probability entries.\nPositions will appear here when snipers execute.',
                textAlign: TextAlign.center,
                style: MehdAiTheme.labelStyle.copyWith(height: 1.5),
              ),
              const SizedBox(height: 24),
              // Status indicators
              Wrap(
                spacing: 12,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _buildStatusChip('RISK KERNEL', 'ARMED', MehdAiTheme.green),
                  _buildStatusChip('SNIPERS', 'HUNTING', MehdAiTheme.blue),
                  _buildStatusChip('DRAWDOWN', '0.0%', MehdAiTheme.green),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7, height: 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [BoxShadow(color: color.withOpacity(0.6), blurRadius: 5)],
            ),
          ),
          const SizedBox(width: 7),
          Text('$label: ', style: MehdAiTheme.labelStyle.copyWith(fontSize: 11)),
          Text(value, style: MehdAiTheme.terminalStyle.copyWith(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildPositionTile(BuildContext context, Map<String, dynamic> pos) {
    final pnl = pos['pnl'] as double;
    final pnlColor = pnl >= 0 ? MehdAiTheme.green : MehdAiTheme.red;
    final sign = pnl >= 0 ? "+" : "";

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: pnlColor.withOpacity(0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: pnlColor.withOpacity(0.15)),
            boxShadow: [
              BoxShadow(color: pnlColor.withOpacity(0.03), blurRadius: 12),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text("${pos['symbol']} ${pos['direction']}",
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Text("Entry: ", style: MehdAiTheme.labelStyle.copyWith(fontSize: 11)),
                        Text("${pos['entry']}", style: MehdAiTheme.terminalStyle.copyWith(fontSize: 11)),
                        const SizedBox(width: 16),
                        Text("Live: ", style: MehdAiTheme.labelStyle.copyWith(fontSize: 11)),
                        Text("${pos['current']}", style: MehdAiTheme.terminalStyle.copyWith(fontSize: 11, color: pnlColor)),
                      ],
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text("P&L", style: MehdAiTheme.labelStyle.copyWith(fontSize: 10)),
                  const SizedBox(height: 4),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text("$sign\$${pnl.toStringAsFixed(2)}",
                      style: GoogleFonts.jetBrainsMono(color: pnlColor, fontWeight: FontWeight.bold, fontSize: 18)),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
