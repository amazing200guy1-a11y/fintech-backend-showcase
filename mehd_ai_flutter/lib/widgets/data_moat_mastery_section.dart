import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:mehd_ai_flutter/core/theme.dart';

class DataMoatMasterySection extends StatelessWidget {
  final int tradesStudied;

  const DataMoatMasterySection({super.key, required this.tradesStudied});

  int _starsFor(int tradesStudied, int threshold) {
    if (tradesStudied >= threshold * 5) return 5;
    if (tradesStudied >= threshold * 3) return 4;
    if (tradesStudied >= threshold * 2) return 3;
    if (tradesStudied >= threshold) return 2;
    if (tradesStudied >= threshold ~/ 2) return 1;
    return 0;
  }

  Widget _buildStars(int filled, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        5,
        (i) => Icon(
          i < filled ? Icons.star_rounded : Icons.star_outline_rounded,
          color: i < filled ? color : color.withOpacity(0.2),
          size: 16,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mastery = [
      {
        'label': 'Price patterns',
        'detail': 'Recognizes when charts set up for high-probability moves',
        'stars': _starsFor(tradesStudied, 10),
        'color': MehdAiTheme.green,
      },
      {
        'label': 'News & sentiment',
        'detail': 'Knows when market mood shifts before price reacts',
        'stars': _starsFor(tradesStudied, 30),
        'color': MehdAiTheme.blue,
      },
      {
        'label': 'Repeating cycles',
        'detail': 'Spots patterns that repeat across sessions and pairs',
        'stars': _starsFor(tradesStudied, 80),
        'color': MehdAiTheme.purple,
      },
      {
        'label': 'Global events',
        'detail': 'Links economic data (CPI, NFP) to price behaviour',
        'stars': _starsFor(tradesStudied, 150),
        'color': MehdAiTheme.gold,
      },
      {
        'label': 'Crash detection',
        'detail': 'Identifies unusual market behaviour before it becomes dangerous',
        'stars': _starsFor(tradesStudied, 300),
        'color': MehdAiTheme.red,
      },
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.white.withOpacity(0.03),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.stars_rounded, color: MehdAiTheme.textSecondary, size: 18),
                  const SizedBox(width: 8),
                  Text('WHAT YOUR AI HAS MASTERED',
                      style: MehdAiTheme.headingStyle.copyWith(fontSize: 13, letterSpacing: 1.5)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Stars fill as your AI studies more winning trades — automatically.',
                style: MehdAiTheme.labelStyle.copyWith(color: MehdAiTheme.textSecondary, fontSize: 11),
              ),
              const SizedBox(height: 20),
              ...mastery.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item['label'] as String,
                                  style: MehdAiTheme.terminalStyle.copyWith(
                                      fontSize: 12,
                                      color: item['color'] as Color,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 3),
                              Text(item['detail'] as String,
                                  style: MehdAiTheme.labelStyle.copyWith(fontSize: 11, height: 1.4)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        _buildStars(item['stars'] as int, item['color'] as Color),
                      ],
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }
}
