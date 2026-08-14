import 'package:flutter/material.dart';
import 'package:mehd_ai_flutter/services/settings_service.dart';

/// Risk percentage slider widget used in Settings screen.
/// Lets the user set risk per trade (0.1% – 10.0%) via a
/// colour-coded slider and a numeric text input.
class GlobalRiskSlider extends StatefulWidget {
  final SettingsService settings;
  const GlobalRiskSlider({super.key, required this.settings});

  @override
  State<GlobalRiskSlider> createState() => GlobalRiskSliderState();
}

class GlobalRiskSliderState extends State<GlobalRiskSlider> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.settings.riskPerTrade.toStringAsFixed(2));
  }

  @override
  void didUpdateWidget(GlobalRiskSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.riskPerTrade != widget.settings.riskPerTrade) {
      if (double.tryParse(_controller.text) != widget.settings.riskPerTrade) {
        _controller.text = widget.settings.riskPerTrade.toStringAsFixed(2);
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color _getRiskColor(double risk) {
    if (risk > 7.0) return const Color(0xFFFF3B3B); // Red
    if (risk > 3.0) return const Color(0xFFD29922); // Yellow
    return const Color(0xFF58A6FF); // Blue
  }

  @override
  Widget build(BuildContext context) {
    final risk = widget.settings.riskPerTrade;
    final color = _getRiskColor(risk);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Global Risk Protocol', style: TextStyle(color: Color(0xFFDDDDDD), fontSize: 13, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(
                    risk > 7.0 ? 'Aggressive exposure' : risk > 3.0 ? 'Moderate exposure' : 'Conservative exposure',
                    style: TextStyle(color: color, fontSize: 10),
                  ),
                ],
              ),
              SizedBox(
                width: 60,
                child: TextField(
                  controller: _controller,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.center,
                  style: TextStyle(color: color, fontSize: 14, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    filled: true,
                    fillColor: color.withOpacity(0.1),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onSubmitted: (val) {
                    final newRisk = double.tryParse(val);
                    if (newRisk != null && newRisk >= 0.1 && newRisk <= 10.0) {
                      widget.settings.setRiskPerTrade(newRisk);
                    } else {
                      _controller.text = widget.settings.riskPerTrade.toStringAsFixed(2);
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: color,
              inactiveTrackColor: color.withOpacity(0.1),
              thumbColor: color,
              overlayColor: color.withOpacity(0.2),
              trackHeight: 4.0,
            ),
            child: Slider(
              // Clamp prevents crash if stored value is outside slider bounds
              value: risk.clamp(0.1, 10.0),
              min: 0.1,
              max: 10.0,
              divisions: 99,
              onChanged: (val) {
                widget.settings.setRiskPerTrade(val, save: false);
              },
              onChangeEnd: (val) {
                widget.settings.setRiskPerTrade(val, save: true);
              },
            ),
          ),
        ],
      ),
    );
  }
}
