import 'package:flutter/material.dart';
import 'package:mehd_ai_flutter/core/theme.dart';

/// Institutional clear radar / empty state visual for Positions & Orders.
class PositionsEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const PositionsEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
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
