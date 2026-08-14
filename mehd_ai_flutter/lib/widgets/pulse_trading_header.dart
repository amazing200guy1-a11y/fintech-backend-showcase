import 'package:flutter/material.dart';
import 'package:mehd_ai_flutter/core/theme.dart';

class NeuroCockpitBar extends StatelessWidget {
  const NeuroCockpitBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF090D16),
        border: Border(bottom: BorderSide(color: MehdAiTheme.borderColor.withOpacity(0.5))),
      ),
      child: Row(
        children: [
          Container(
            width: 8, height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFF00FF88),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text('NEURO PULSE ONLINE', style: MehdAiTheme.terminalStyle.copyWith(color: const Color(0xFF00FF88), fontSize: 11, fontWeight: FontWeight.bold)),
          const Spacer(),
          Text('LATENCY: 12ms', style: MehdAiTheme.terminalStyle.copyWith(color: Colors.white38, fontSize: 10)),
        ],
      ),
    );
  }
}
