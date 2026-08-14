import 'package:flutter/material.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/core/constitution_service.dart';

/// Card widget rendering a single ConstitutionRule with its parameter controls.
class ConstitutionRuleCard extends StatelessWidget {
  final ConstitutionRule rule;
  final int index;
  final ValueChanged<bool> onToggleActive;
  final ValueChanged<double> onUpdateParameter;

  const ConstitutionRuleCard({
    super.key,
    required this.rule,
    required this.index,
    required this.onToggleActive,
    required this.onUpdateParameter,
  });

  @override
  Widget build(BuildContext context) {
    final colors = [MehdAiTheme.blue, MehdAiTheme.gold, MehdAiTheme.purple];
    final icons = [
      Icons.balance_rounded,
      Icons.bar_chart_rounded,
      Icons.groups_rounded,
    ];
    final accent = colors[index % colors.length];
    final cardIcon = icons[index % icons.length];

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: MehdAiTheme.bgSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.06),
            blurRadius: 20,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [accent.withOpacity(0.12), Colors.transparent],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: accent.withOpacity(0.4)),
                  ),
                  child: Icon(cardIcon, color: accent, size: 18),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    rule.name.toUpperCase(),
                    style: MehdAiTheme.headingStyle.copyWith(
                      fontSize: 13,
                      color: accent,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                Transform.scale(
                  scale: 0.85,
                  child: Switch(
                    value: rule.isActive,
                    activeColor: accent,
                    activeTrackColor: accent.withOpacity(0.25),
                    inactiveThumbColor: Colors.grey,
                    inactiveTrackColor: Colors.white10,
                    onChanged: onToggleActive,
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rule.description,
                  style: MehdAiTheme.labelStyle.copyWith(
                    height: 1.7,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 20),
                _buildParameterControl(rule, accent),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildParameterControl(ConstitutionRule rule, Color accent) {
    if (rule.ruleType == 'max_daily_trades') {
      return _buildCountControl(
        label: 'Max Trades Per Day',
        value: rule.parameter.toInt(),
        min: 1,
        max: 10,
        accent: accent,
        onDecrement: rule.parameter > 1
            ? () => onUpdateParameter(rule.parameter - 1)
            : null,
        onIncrement: rule.parameter < 10
            ? () => onUpdateParameter(rule.parameter + 1)
            : null,
      );
    }

    if (rule.ruleType == 'min_consensus') {
      return _buildSliderControl(
        label: 'Consensus Required',
        value: rule.parameter,
        displayText: '${rule.parameter.toInt()}%',
        min: 50,
        max: 100,
        minLabel: '50% (Lenient)',
        maxLabel: '100% (Unanimous)',
        accent: accent,
        onChanged: onUpdateParameter,
      );
    }

    if (rule.ruleType == 'max_risk_per_trade') {
      return _buildSliderControl(
        label: 'Risk Per Trade',
        value: rule.parameter.clamp(0.1, 10.0),
        displayText: '${rule.parameter.toStringAsFixed(1)}%',
        min: 0.1,
        max: 10.0,
        divisions: 99,
        minLabel: '0.1% (Conservative)',
        maxLabel: '10% (Aggressive)',
        accent: accent,
        onChanged: (val) => onUpdateParameter(
          double.parse(val.toStringAsFixed(1)),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MehdAiTheme.bgPrimary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          const Icon(Icons.psychology_rounded, color: MehdAiTheme.purple, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This rule is managed autonomously by The Den AI.',
              style: MehdAiTheme.labelStyle.copyWith(
                color: MehdAiTheme.textSecondary,
                fontStyle: FontStyle.italic,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountControl({
    required String label,
    required int value,
    required int min,
    required int max,
    required Color accent,
    required VoidCallback? onDecrement,
    required VoidCallback? onIncrement,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: MehdAiTheme.labelStyle
                .copyWith(color: MehdAiTheme.textSecondary, fontSize: 11)),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _counterButton(
              icon: Icons.remove_rounded,
              color: MehdAiTheme.red,
              onTap: onDecrement,
            ),
            const SizedBox(width: 24),
            Text(
              '$value',
              style: TextStyle(
                color: accent,
                fontSize: 36,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(width: 24),
            _counterButton(
              icon: Icons.add_rounded,
              color: MehdAiTheme.green,
              onTap: onIncrement,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            '$min–$max trades per day',
            style: MehdAiTheme.labelStyle
                .copyWith(fontSize: 10, color: MehdAiTheme.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _counterButton({
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: onTap == null ? Colors.white.withOpacity(0.05) : color.withOpacity(0.12),
          shape: BoxShape.circle,
          border:
              Border.all(color: onTap == null ? Colors.white10 : color.withOpacity(0.4)),
        ),
        child: Icon(
          icon,
          color: onTap == null ? Colors.white24 : color,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildSliderControl({
    required String label,
    required double value,
    required String displayText,
    required double min,
    required double max,
    required String minLabel,
    required String maxLabel,
    required Color accent,
    required ValueChanged<double> onChanged,
    int? divisions,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: MehdAiTheme.labelStyle
                    .copyWith(color: MehdAiTheme.textSecondary, fontSize: 11)),
            Text(
              displayText,
              style: TextStyle(
                color: accent,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: accent,
            inactiveTrackColor: accent.withOpacity(0.15),
            thumbColor: accent,
            overlayColor: accent.withOpacity(0.12),
            trackHeight: 3,
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions ?? ((max - min).round()),
            onChanged: onChanged,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(minLabel,
                style: MehdAiTheme.labelStyle
                    .copyWith(fontSize: 10, color: MehdAiTheme.textSecondary)),
            Text(maxLabel,
                style: MehdAiTheme.labelStyle
                    .copyWith(fontSize: 10, color: MehdAiTheme.textSecondary)),
          ],
        ),
      ],
    );
  }
}
