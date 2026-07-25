import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/services/settings_service.dart';

class QuickPipCalculator extends StatefulWidget {
  const QuickPipCalculator({super.key});

  @override
  State<QuickPipCalculator> createState() => _QuickPipCalculatorState();
}

class _QuickPipCalculatorState extends State<QuickPipCalculator> {
  bool _isExpanded = false;

  // We will read the initial state from SettingsService and keep it in sync.
  double _localStopLossPips = 20.0;
  bool _initialized = false;

  @override
  Widget build(BuildContext context) {
    if (!_isExpanded) {
      return FloatingActionButton.small(
        backgroundColor: MehdAiTheme.bgSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: const BorderSide(color: MehdAiTheme.borderColor),
        ),
        onPressed: () => setState(() => _isExpanded = true),
        child: const Icon(Icons.calculate, color: MehdAiTheme.blue, size: 20),
      );
    }

    final settings = context.watch<SettingsService>();
    
    if (!_initialized) {
      _localStopLossPips = settings.defaultStopLoss;
      _initialized = true;
    }

    final double accountBalance = settings.accountBalance;
    final double riskPercent = settings.riskPerTrade; // e.g. 1.0 = 1%
    final double riskAmount = (accountBalance * riskPercent) / 100;
    
    // Allow sliding up to 20% risk
    final double maxRiskAmount = accountBalance * 0.20;

    final lotSize = riskAmount / (_localStopLossPips * 10); // Rough approximation for standard lots

    return Container(
      width: 200,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: MehdAiTheme.bgSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MehdAiTheme.borderColor),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.5), blurRadius: 10, offset: const Offset(0, 5))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: Text('PIP CALCULATOR', style: MehdAiTheme.labelStyle.copyWith(color: MehdAiTheme.white), overflow: TextOverflow.ellipsis)),
              InkWell(
                onTap: () => setState(() => _isExpanded = false),
                child: const Icon(Icons.close, size: 16, color: MehdAiTheme.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Risk Amount (\$)', style: MehdAiTheme.labelStyle, overflow: TextOverflow.ellipsis),
          Slider(
            value: riskAmount.clamp(10, maxRiskAmount > 10 ? maxRiskAmount : 100),
            min: 10,
            max: maxRiskAmount > 10 ? maxRiskAmount : 100,
            divisions: (maxRiskAmount / 10).round().clamp(1, 100),
            activeColor: MehdAiTheme.blue,
            inactiveColor: MehdAiTheme.borderColor,
            label: '\$${riskAmount.toInt()} (${riskPercent.toStringAsFixed(1)}%)',
            onChanged: (val) {
              final newPercent = (val / accountBalance) * 100;
              settings.setRiskPerTrade(newPercent);
            },
          ),
          Text('Max 20% cap: \$${maxRiskAmount.toInt()} of \$${accountBalance.toInt()} balance', style: MehdAiTheme.labelStyle.copyWith(color: MehdAiTheme.yellow, fontSize: 9), overflow: TextOverflow.ellipsis),
          Text('Stop Loss (Pips)', style: MehdAiTheme.labelStyle, overflow: TextOverflow.ellipsis),
          Slider(
            value: _localStopLossPips.clamp(5, 100),
            min: 5,
            max: 100,
            divisions: 95,
            activeColor: MehdAiTheme.red,
            inactiveColor: MehdAiTheme.borderColor,
            label: '${_localStopLossPips.toInt()} pips',
            onChanged: (val) {
               setState(() => _localStopLossPips = val);
               settings.setDefaultStopLoss(val);
            },
          ),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: MehdAiTheme.bgPrimary,
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: MehdAiTheme.borderColor),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Flexible(child: Text('Lot Size:', style: MehdAiTheme.labelStyle, overflow: TextOverflow.ellipsis)),
                Flexible(
                  child: Text(
                    lotSize.toStringAsFixed(2),
                    style: MehdAiTheme.terminalStyle.copyWith(color: MehdAiTheme.green, fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}
