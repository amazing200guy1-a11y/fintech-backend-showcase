import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:mehd_ai_flutter/core/theme.dart';

/// Global Generals Leaderboard widget for Network / Community Screen.
class GlobalGeneralsLeaderboard extends StatelessWidget {
  final List<Map<String, dynamic>> generals;

  const GlobalGeneralsLeaderboard({
    super.key,
    required this.generals,
  });

  String _formatPnl(double val) {
    if (val >= 1000000) return '${(val / 1000000).toStringAsFixed(2)}M';
    if (val >= 1000) return '${(val / 1000).toStringAsFixed(0)}K';
    return val.toStringAsFixed(0);
  }

  @override
  Widget build(BuildContext context) {
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
}
