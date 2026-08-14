import 'package:flutter/material.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/core/constitution_service.dart';

class ConstitutionHeaderSection extends StatelessWidget {
  final AppConstitution constitution;

  const ConstitutionHeaderSection({super.key, required this.constitution});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A3A5C), Color(0xFF0D1F33)],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: MehdAiTheme.blue.withOpacity(0.5)),
              boxShadow: [
                BoxShadow(
                  color: MehdAiTheme.blue.withOpacity(0.2),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_awesome, color: MehdAiTheme.blue, size: 14),
                const SizedBox(width: 8),
                Text(
                  'DEN LAW · CONSTITUTION v1.0',
                  style: MehdAiTheme.terminalStyle.copyWith(
                    color: MehdAiTheme.blue,
                    letterSpacing: 2.0,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          "The Trader's Constitution",
          style: MehdAiTheme.headingStyle.copyWith(fontSize: 26),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          'Three unbreakable laws. Follow them and protect your capital.\n'
          'Break them and The Den stops you — automatically, without mercy.',
          style: MehdAiTheme.labelStyle.copyWith(height: 1.6, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: MehdAiTheme.red.withOpacity(0.07),
            border: Border.all(color: MehdAiTheme.red.withOpacity(0.3)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(Icons.shield_outlined, color: MehdAiTheme.red, size: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Enforced by the Hard Risk Kernel. If a trade breaks these laws, '
                  'execution is blocked — no exceptions, no override.',
                  style: MehdAiTheme.labelStyle.copyWith(
                    color: MehdAiTheme.textSecondary,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),
        Row(
          children: [
            Expanded(
              child: _buildStatChip(
                icon: Icons.today_rounded,
                label: 'TRADES TODAY',
                value: '${constitution.dailyTradesCount}',
                color: MehdAiTheme.blue,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatChip(
                icon: Icons.gavel_rounded,
                label: 'ACTIVE LAWS',
                value: '${constitution.rules.where((r) => r.isActive).length}',
                color: MehdAiTheme.green,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildStatChip(
                icon: Icons.calendar_today_rounded,
                label: 'LAST RESET',
                value: constitution.lastResetDate.isEmpty
                    ? 'TODAY'
                    : constitution.lastResetDate.substring(5),
                color: MehdAiTheme.gold,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
      decoration: BoxDecoration(
        color: MehdAiTheme.bgSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: MehdAiTheme.labelStyle.copyWith(
              fontSize: 9,
              color: MehdAiTheme.textSecondary,
              letterSpacing: 0.5,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
