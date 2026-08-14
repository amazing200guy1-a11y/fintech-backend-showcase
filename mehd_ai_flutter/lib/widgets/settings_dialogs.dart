import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:mehd_ai_flutter/services/settings_service.dart';
import 'package:mehd_ai_flutter/controllers/trading_controller.dart';
import 'package:mehd_ai_flutter/core/constants.dart';

/// Shows an edit dialog for the user's display name.
void showEditProfileDialog(BuildContext context, String currentName, SettingsService settings) {
  final controller = TextEditingController(text: currentName);
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF020810),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: Color(0xFF222222)),
      ),
      title: Text('EDIT PROFILE NAME',
          style: GoogleFonts.orbitron(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 1.5)),
      content: TextField(
        controller: controller,
        style: const TextStyle(color: Colors.white),
        decoration: const InputDecoration(
          labelText: 'Display Name',
          labelStyle: TextStyle(color: Colors.white54),
          enabledBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: Colors.white24),
          ),
          focusedBorder: UnderlineInputBorder(
            borderSide: BorderSide(color: Color(0xFF58A6FF)),
          ),
        ),
      ),
      actions: [
        TextButton(
          child: const Text('CANCEL', style: TextStyle(color: Colors.white54)),
          onPressed: () => Navigator.pop(ctx),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF58A6FF),
          ),
          child: const Text('SAVE', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          onPressed: () async {
            final newName = controller.text.trim();
            if (newName.isNotEmpty) {
              try {
                await settings.setProfileName(newName);
                await FirebaseAuth.instance.currentUser?.updateDisplayName(newName);
                await FirebaseAuth.instance.currentUser?.reload();
                if (context.mounted) {
                  Navigator.pop(ctx);
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Display name updated to $newName'),
                    backgroundColor: const Color(0xFF1E293B),
                  ));
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                    content: Text('Error: $e'),
                    backgroundColor: Colors.red,
                  ));
                }
              }
            }
          },
        ),
      ],
    ),
  );
}

/// Shows the live trading confirmation warning dialog.
void showLiveTradingWarning(BuildContext context, SettingsService settings) {
  showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF080808),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: Color(0xFFFF3B3B), width: 1),
      ),
      title: Row(children: const [
        Icon(Icons.warning_amber, color: Color(0xFFFF3B3B)),
        SizedBox(width: 8),
        Text('LIVE TRADING',
          style: TextStyle(color: Color(0xFFFF3B3B), fontSize: 14, letterSpacing: 2, fontWeight: FontWeight.bold)),
      ]),
      content: Text(
        'You are enabling LIVE trading.\n\n'
        'Real money. Real consequences.\n'
        'Your current risk is locked at ${settings.riskPerTrade.toStringAsFixed(1)}% per trade.\n'
        'Kill-switch at ${AppConstants.killSwitchPercent.toStringAsFixed(0)}% drawdown.',
        style: const TextStyle(color: Color(0xFF666666), fontSize: 12, height: 1.7),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('CANCEL', style: TextStyle(color: Color(0xFF444444))),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF120000),
            side: const BorderSide(color: Color(0xFFFF3B3B)),
          ),
          onPressed: () {
            Navigator.pop(context);
            switchToLive(context, settings);
          },
          child: const Text('I UNDERSTAND — GO LIVE', style: TextStyle(color: Color(0xFFFF3B3B), fontSize: 10, fontWeight: FontWeight.bold)),
        ),
      ],
    ),
  );
}

void switchToLive(BuildContext context, SettingsService settings) {
  settings.setPaperMode(false);
  if (context.mounted) {
    context.read<TradingController>().setPaperMode(false);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF1A0000),
        content: Text(
          '⚡ Live trading enabled.',
          style: TextStyle(color: Color(0xFFFF3B3B)),
        ),
      ),
    );
  }
}

void switchToPaper(BuildContext context, SettingsService settings) {
  settings.setPaperMode(true);
  if (context.mounted) {
    context.read<TradingController>().setPaperMode(true);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        backgroundColor: Color(0xFF020810),
        content: Text(
          '📊 Paper trading enabled. Zero risk.',
          style: TextStyle(color: Color(0xFF58A6FF)),
        ),
      ),
    );
  }
}
