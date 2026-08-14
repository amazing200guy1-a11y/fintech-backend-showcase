import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/services/settings_service.dart';

class HistoryEventsTab extends StatelessWidget {
  final SettingsService settings;
  final bool isPaper;
  final String? activeBroker;
  final Animation<double> orbAnim;

  const HistoryEventsTab({
    super.key,
    required this.settings,
    required this.isPaper,
    this.activeBroker,
    required this.orbAnim,
  });

  @override
  Widget build(BuildContext context) {
    final events = [
      {
        'type': 'info',
        'title': 'Account Gateway Initialized',
        'desc': 'Welcome to MEHD AI institutional trading framework.',
        'time': 'System Boot'
      },
      {
        'type': 'setting',
        'title': 'Risk Profile Hardened',
        'desc': 'Risk per trade configured to ${settings.riskPerTrade.toStringAsFixed(1)}% (Stop-Loss ${settings.defaultStopLoss.toStringAsFixed(1)} pips).',
        'time': 'Active Config'
      },
      {
        'type': 'success',
        'title': isPaper ? 'Paper Mode Active' : 'Live Execution Pipeline Active',
        'desc': isPaper
            ? 'Sniping signals using \$${settings.accountBalance.toStringAsFixed(0)} demo balance.'
            : 'Live signals connected to real capital execution engine.',
        'time': 'Active State'
      },
      {
        'type': activeBroker != null ? 'success' : 'info',
        'title': activeBroker != null ? 'Broker Connection Shielded' : 'Broker Gateway Unlinked',
        'desc': activeBroker != null
            ? 'Connected to $activeBroker with anti-manipulation filters armed.'
            : 'No live broker connected yet. Running in isolated mode.',
        'time': 'Broker State'
      },
    ];

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(24),
      itemCount: events.length,
      itemBuilder: (ctx, i) {
        final e = events[i];
        IconData icon;
        Color color;
        switch (e['type']) {
          case 'lock':
            icon = Icons.lock;
            color = MehdAiTheme.red;
            break;
          case 'setting':
            icon = Icons.settings;
            color = MehdAiTheme.blue;
            break;
          case 'success':
            icon = Icons.verified;
            color = MehdAiTheme.green;
            break;
          default:
            icon = Icons.info_outline;
            color = MehdAiTheme.textSecondary;
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                AnimatedBuilder(
                  animation: orbAnim,
                  builder: (_, __) {
                    return Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: color.withOpacity(0.08),
                        shape: BoxShape.circle,
                        border: Border.all(color: color.withOpacity(0.3 + (orbAnim.value * 0.2))),
                        boxShadow: [
                          BoxShadow(color: color.withOpacity(0.08), blurRadius: 10),
                        ],
                      ),
                      child: Icon(icon, color: color, size: 16),
                    );
                  },
                ),
                if (i < events.length - 1)
                  Container(
                    width: 1.5,
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [color.withOpacity(0.3), Colors.white.withOpacity(0.03)],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 24, top: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Flexible(
                          child: Text(
                            e['title']!,
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          e['time']!,
                          style: MehdAiTheme.labelStyle.copyWith(
                            fontSize: 9,
                            color: MehdAiTheme.textSecondary.withOpacity(0.4),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      e['desc']!,
                      style: MehdAiTheme.labelStyle.copyWith(fontSize: 12, height: 1.4),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}
