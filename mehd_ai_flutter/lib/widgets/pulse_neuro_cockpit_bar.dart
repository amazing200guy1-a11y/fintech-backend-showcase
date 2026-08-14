import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:mehd_ai_flutter/controllers/trading_controller.dart';
import 'package:mehd_ai_flutter/controllers/market_data_controller.dart';
import 'package:mehd_ai_flutter/services/settings_service.dart';

/// The horizontal cockpit action bar at the top of Pulse Trading Screen.
/// Provides one-tap BUY, SELL, CLOSE ALL, and SWARM SCAN execution buttons.
class PulseNeuroCockpitBar extends StatelessWidget {
  /// Called when the user taps BUY/SELL/CLOSE/SCAN with the command text to submit
  final ValueChanged<String> onCommandSubmit;

  const PulseNeuroCockpitBar({
    super.key,
    required this.onCommandSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final trading = context.watch<TradingController>();
    final market = context.read<MarketDataController>();
    final settings = context.read<SettingsService>();
    final activeSymbol = market.activeSymbol ?? 'EUR/USD';
    final livePrice = market.latestSnapshot?.close ?? 1.0850;
    final lotSize = settings.defaultLotSize;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: const BoxDecoration(
        color: Color(0xFF18181B),
        border: Border(
            bottom: BorderSide(color: Color(0xFF27272A), width: 1)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _CockpitButton(
                    label: 'BUY MARKET',
                    subtitle: activeSymbol,
                    icon: Icons.trending_up_rounded,
                    color: const Color(0xFF10B981),
                    onTap: () {
                      trading.executeSandboxTrade(
                          activeSymbol, 'BUY', livePrice,
                          lotSize: lotSize);
                      onCommandSubmit('/long $activeSymbol 1x');
                    },
                  ),
                  const SizedBox(width: 8),
                  _CockpitButton(
                    label: 'SELL MARKET',
                    subtitle: activeSymbol,
                    icon: Icons.trending_down_rounded,
                    color: const Color(0xFFF43F5E),
                    onTap: () {
                      trading.executeSandboxTrade(
                          activeSymbol, 'SELL', livePrice,
                          lotSize: lotSize);
                      onCommandSubmit('/short $activeSymbol 1x');
                    },
                  ),
                  const SizedBox(width: 8),
                  _CockpitButton(
                    label: 'CLOSE ALL',
                    subtitle: 'LIQUIDATE',
                    icon: Icons.power_settings_new_rounded,
                    color: const Color(0xFFF59E0B),
                    onTap: () {
                      trading.closeAllPositions();
                      onCommandSubmit('CLOSE ALL — All active positions liquidated.');
                    },
                  ),
                  const SizedBox(width: 8),
                  _CockpitButton(
                    label: 'SWARM SCAN',
                    subtitle: 'ALL PAIRS',
                    icon: Icons.radar_rounded,
                    color: const Color(0xFF3B82F6),
                    onTap: () {
                      onCommandSubmit(
                          'Scan EUR/USD, GBP/USD, XAU/USD, BTC/USD');
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CockpitButton extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _CockpitButton({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        height: 36,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF27272A).withOpacity(0.5),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.3), width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 8),
            Text(
              label,
              style: GoogleFonts.outfit(
                  color: const Color(0xFFFAFAFA),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3),
            ),
            const SizedBox(width: 6),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                subtitle,
                style: GoogleFonts.jetBrainsMono(
                    color: color,
                    fontSize: 9,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
