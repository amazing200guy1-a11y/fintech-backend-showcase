import 'package:flutter/material.dart';
import 'package:mehd_ai_flutter/core/theme.dart';

class AuthTermsCheckbox extends StatelessWidget {
  final bool termsAccepted;
  final ValueChanged<bool> onChanged;

  const AuthTermsCheckbox({
    super.key,
    required this.termsAccepted,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MehdAiTheme.bgSecondary.withOpacity(0.5),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: termsAccepted ? MehdAiTheme.green.withOpacity(0.3) : MehdAiTheme.red.withOpacity(0.6)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24, height: 24,
            child: Checkbox(
              value: termsAccepted,
              onChanged: (v) => onChanged(v ?? false),
              activeColor: MehdAiTheme.green,
              checkColor: Colors.black,
              side: BorderSide(color: termsAccepted ? MehdAiTheme.green : MehdAiTheme.red),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'I acknowledge that trading on margin involves significant risk of capital loss. Mehd AI is a decision-support tool, not financial advice. I trade entirely at my own risk.',
              style: MehdAiTheme.labelStyle.copyWith(fontSize: 12, color: MehdAiTheme.textSecondary, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}
