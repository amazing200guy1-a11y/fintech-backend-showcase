import 'package:flutter/material.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/models/consensus_result.dart';

/// FILE — live_calculator.dart
///
/// Build Debrief:
/// The Math Room needs strict, unarguable statistics. 
/// LiveCalculator scans the individual votes from the Math Layer models
/// (DeepSeek, o3, Codestral) and aggregates their raw confidence scores
/// into a mathematical certainty rating.

class LiveCalculator extends StatelessWidget {
  final List<AIVote> mathVotes;

  const LiveCalculator({super.key, required this.mathVotes});

  @override
  Widget build(BuildContext context) {
    if (mathVotes.isEmpty) return const SizedBox.shrink();

    // Calculate aggregated stats
    double totalConfidence = 0;
    for (var v in mathVotes) {
      totalConfidence += v.confidence;
    }
    final avgConfidence = totalConfidence / mathVotes.length;

    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: MehdAiTheme.bgSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MehdAiTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.calculate, color: MehdAiTheme.green),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'LIVE CALCULUS',
                  style: MehdAiTheme.headingStyle.copyWith(letterSpacing: 1),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: _buildStatWidget('Avg Confidence', '${(avgConfidence * 100).toStringAsFixed(1)}%', MehdAiTheme.textPrimary)),
              Flexible(child: _buildStatWidget('Math Discrepancy', _calculateDiscrepancy(), MehdAiTheme.textSecondary)),
              Flexible(child: _buildStatWidget('Models Active', '${mathVotes.length}/3', MehdAiTheme.blue)),
            ],
          ),
        ],
      ),
    );
  }

  String _calculateDiscrepancy() {
    if (mathVotes.length < 2) return '0.0%';
    double maxConf = mathVotes.map((v) => v.confidence).reduce((a, b) => a > b ? a : b);
    double minConf = mathVotes.map((v) => v.confidence).reduce((a, b) => a < b ? a : b);
    return '${((maxConf - minConf) * 100).toStringAsFixed(1)}%';
  }

  Widget _buildStatWidget(String label, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: MehdAiTheme.labelStyle.copyWith(fontSize: 10),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: MehdAiTheme.terminalStyle.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: valueColor,
          ),
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
