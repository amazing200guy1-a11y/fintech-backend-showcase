import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:mehd_ai_flutter/services/settings_service.dart';
import 'package:mehd_ai_flutter/widgets/settings_card_builders.dart';

class SettingsDangerZone extends StatelessWidget {
  final SettingsService settings;

  const SettingsDangerZone({super.key, required this.settings});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        buildSettingsSectionTitle('DANGER ZONE', color: const Color(0xFFFF3B3B)),
        ListTile(
          leading: const Icon(Icons.delete_outline, color: Color(0xFFFF3B3B), size: 20),
          title: const Text('Clear Local Data', style: TextStyle(color: Color(0xFFFF3B3B))),
          subtitle: const Text('Resets cached settings only', style: TextStyle(color: Color(0xFF444444), fontSize: 10)),
          onTap: () => showDialog(
            context: context,
            builder: (_) => AlertDialog(
              backgroundColor: const Color(0xFF080808),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: const BorderSide(color: Color(0xFF1A0000))),
              title: const Text('Clear Local Data?', style: TextStyle(color: Color(0xFFFF3B3B), fontSize: 14)),
              content: const Text(
                'This clears cached settings.\n\n'
                'Your account and trades\n'
                'on Firebase stay safe.',
                style: TextStyle(color: Color(0xFF666666), height: 1.7)),
              actions: [
                TextButton(
                  onPressed: () async {
                    await settings.clearLocal();
                    if (context.mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                          backgroundColor: Color(0xFF001208),
                          content: Text('✓ Local data cleared',
                            style: TextStyle(color: Color(0xFF00FF88)))));
                    }
                  },
                  child: const Text('CLEAR', style: TextStyle(color: Color(0xFFFF3B3B)))),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CANCEL', style: TextStyle(color: Color(0xFF444444)))),
              ],
            ),
          ),
        ),
        ListTile(
          leading: const Icon(Icons.logout, color: Color(0xFFFF3B3B), size: 20),
          title: const Text('Sign Out', style: TextStyle(color: Color(0xFFFF3B3B))),
          onTap: () => showDialog(
            context: context,
            builder: (_) => AlertDialog(
              backgroundColor: const Color(0xFF080808),
              title: const Text('Sign Out?', style: TextStyle(color: Color(0xFFCCCCCC))),
              content: const Text(
                'The Den goes dark until\n'
                'you return.',
                style: TextStyle(color: Color(0xFF666666))),
              actions: [
                TextButton(
                  onPressed: () async {
                    await FirebaseAuth.instance.signOut();
                    if (context.mounted) {
                      Navigator.pushNamedAndRemoveUntil(context, '/login', (route) => false);
                    }
                  },
                  child: const Text('SIGN OUT', style: TextStyle(color: Color(0xFFFF3B3B)))),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CANCEL', style: TextStyle(color: Color(0xFF444444)))),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
