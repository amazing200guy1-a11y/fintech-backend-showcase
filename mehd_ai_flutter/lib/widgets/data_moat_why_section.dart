import 'package:flutter/material.dart';
import 'package:mehd_ai_flutter/core/theme.dart';

class DataMoatWhySection extends StatelessWidget {
  const DataMoatWhySection({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MehdAiTheme.bgSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MehdAiTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('WHY YOUR EDGE KEEPS GROWING',
              style: MehdAiTheme.headingStyle
                  .copyWith(fontSize: 12, letterSpacing: 1.5)),
          const SizedBox(height: 14),
          _whyRow(Icons.person_rounded, MehdAiTheme.purple,
              'This AI knows YOUR market.',
              'Most traders use generic signals that work for everyone and no one. Your AI studies your specific pairs, your sessions, your winning conditions.'),
          const SizedBox(height: 12),
          _whyRow(Icons.trending_up_rounded, MehdAiTheme.green,
              'The more you trade, the sharper it gets.',
              'Every winning trade adds a new lesson. A trader with 500 studied wins has a completely different AI than one with 50.'),
          const SizedBox(height: 12),
          _whyRow(Icons.timer_rounded, MehdAiTheme.blue,
              'Discipline compounds over time.',
              'Retail traders who stick with one system for 6 months statistically outperform those who chase strategies. Your AI locks in what works for you specifically.'),
        ],
      ),
    );
  }

  Widget _whyRow(IconData icon, Color color, String bold, String detail) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 12),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: MehdAiTheme.labelStyle.copyWith(fontSize: 13, height: 1.6),
              children: [
                TextSpan(
                    text: '$bold ',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                TextSpan(text: detail),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
