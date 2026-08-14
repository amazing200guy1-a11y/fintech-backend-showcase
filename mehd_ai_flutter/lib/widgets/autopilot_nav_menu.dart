import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/controllers/market_data_controller.dart';
import 'package:mehd_ai_flutter/screens/war_room_screen.dart';
import 'package:mehd_ai_flutter/screens/scoreboard_screen.dart';
import 'package:mehd_ai_flutter/screens/autopilot_command_center.dart';
import 'package:mehd_ai_flutter/screens/den/network_screen.dart';
import 'package:mehd_ai_flutter/screens/data_moat_screen.dart';
import 'package:mehd_ai_flutter/screens/pulse_trading_screen.dart';
import 'package:mehd_ai_flutter/screens/sandbox_mode_screen.dart';
import 'package:mehd_ai_flutter/screens/journey_screen.dart';
import 'package:mehd_ai_flutter/screens/calculators_screen.dart';
import 'package:mehd_ai_flutter/screens/den/sovereign_feed_screen.dart';
import 'package:mehd_ai_flutter/screens/war_room_community_screen.dart';
import 'package:mehd_ai_flutter/screens/settings_screen.dart';
import 'package:mehd_ai_flutter/screens/den/positions_screen.dart' as den_pos;
import 'package:mehd_ai_flutter/screens/broker_screen.dart';

import 'package:mehd_ai_flutter/screens/history_screen.dart';
import 'package:mehd_ai_flutter/screens/compliance_screen.dart';
import 'package:mehd_ai_flutter/screens/den/strategy_room.dart';
import 'package:mehd_ai_flutter/screens/den/research_room.dart';




/// Shows the bottom-sheet app navigation grid.
void showDenActionMenu(
  BuildContext context,
  ValueNotifier<int> desktopIndexNotifier,
) {
  final isDesktop = MediaQuery.of(context).size.width > 1200;

  void navTo(int desktopIndex, Widget Function() mobileBuilder) {
    Navigator.pop(context);
    if (isDesktop) {
      desktopIndexNotifier.value = desktopIndex;
    } else {
      Navigator.push(context, MaterialPageRoute(builder: (_) => mobileBuilder()));
    }
  }

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: Container(
        height: MediaQuery.of(context).size.height * 0.85,
        decoration: BoxDecoration(
          color: MehdAiTheme.surface(context).withOpacity(0.95),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          border: Border.all(color: MehdAiTheme.border(context).withOpacity(0.2)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: MehdAiTheme.textDim(context).withOpacity(0.3), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 24),
            const Text('Navigation', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
            const SizedBox(height: 6),
            const Text('Select a feature to open', style: TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 24),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GridView.count(
                  crossAxisCount: MediaQuery.of(context).size.width < 400 ? 2 : 3,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.95,
                  children: [
                    _buildMenuCard(context, 'WAR ROOM', Icons.radar_rounded, const [Color(0xFF3A0E0E), Color(0xFF1F0707)], const Color(0xFFFF4444), () {
                      final market = Provider.of<MarketDataController>(context, listen: false);
                      navTo(0, () => WarRoomScreen(isAnalyzing: market.isAnalyzing, consensus: market.consensus, showBack: true));
                    }),
                    _buildMenuCard(context, 'SCOREBOARD', Icons.emoji_events_rounded, const [Color(0xFF0E3A18), Color(0xFF061A0C)], const Color(0xFF00FF88), () => navTo(10, () => const ScoreboardScreen(showBack: true))),
                    _buildMenuCard(context, 'AUTOPILOT', Icons.precision_manufacturing_rounded, const [Color(0xFF0E2A3A), Color(0xFF061520)], const Color(0xFF58A6FF), () => navTo(5, () => const AutopilotCommandCenter())),
                    _buildMenuCard(context, 'NETWORK', Icons.group_work_rounded, const [Color(0xFF3A2B0E), Color(0xFF1A1306)], const Color(0xFFFFD700), () => navTo(9, () => const NetworkScreen())),
                    _buildMenuCard(context, 'DATA MOAT', Icons.hub_rounded, const [Color(0xFF0F3D4A), Color(0xFF061A21)], const Color(0xFF00E5FF), () => navTo(11, () => const DataMoatScreen(showBack: true))),
                    _buildMenuCard(context, 'POSITIONS', Icons.show_chart_rounded, const [Color(0xFF4A3A0E), Color(0xFF211A06)], const Color(0xFFFFD700), () => navTo(3, () => const den_pos.PositionsScreen())),
                    _buildMenuCard(context, 'STRATEGY', Icons.account_balance_rounded, const [Color(0xFF0E3A4A), Color(0xFF061A21)], const Color(0xFF00FFCC), () => navTo(4, () => Scaffold(appBar: AppBar(title: const Text('Strategy Room')), backgroundColor: MehdAiTheme.bgPrimary, body: const StrategyRoom()))),
                    _buildMenuCard(context, 'RESEARCH', Icons.travel_explore_rounded, const [Color(0xFF2D1B4E), Color(0xFF1A0F30)], const Color(0xFFBC8CFF), () => navTo(4, () => Scaffold(appBar: AppBar(title: const Text('RESEARCH INTELLIGENCE')), backgroundColor: MehdAiTheme.bgPrimary, body: const ResearchRoom()))),
                    _buildMenuCard(context, 'NEURO PULSE', Icons.psychology_rounded, const [Color(0xFF0A2A18), Color(0xFF06180E)], const Color(0xFF00FF88), () => navTo(6, () => const PulseTradingScreen(showBack: true))),
                    _buildMenuCard(context, 'SANDBOX', Icons.visibility_rounded, const [Color(0xFF1A1040), Color(0xFF0D0820)], const Color(0xFFBC8CFF), () => navTo(7, () => const SandboxModeScreen(showBack: true))),
                    _buildMenuCard(context, 'JOURNEY', Icons.rocket_launch, const [Color(0xFF4A0E4E), Color(0xFF220526)], const Color(0xFF9E00FF), () => navTo(14, () => const JourneyScreen())),
                    _buildMenuCard(context, 'CALCULATOR', Icons.calculate_rounded, const [Color(0xFF2A1C0E), Color(0xFF140D07)], MehdAiTheme.gold, () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const CalculatorsScreen())); }),
                    _buildMenuCard(context, 'SOVEREIGN', Icons.hub_outlined, const [Color(0xFF0E2A3A), Color(0xFF061520)], const Color(0xFF58A6FF), () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const SovereignFeedScreen(showBack: true))); }),
                    _buildMenuCard(context, 'COMMUNITY', Icons.groups_rounded, const [Color(0xFF3A1B5E), Color(0xFF1F0F35)], MehdAiTheme.purple, () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const WarRoomCommunityScreen(showBack: true))); }),
                    _buildMenuCard(context, 'HISTORY', Icons.history_rounded, const [Color(0xFF2A2A0E), Color(0xFF141407)], const Color(0xFFFFD700), () => navTo(8, () => const HistoryScreen(showBack: true))),
                    _buildMenuCard(context, 'REJECTION FEED', Icons.gavel_rounded, const [Color(0xFF3A1010), Color(0xFF1A0505)], const Color(0xFFFF3B3B), () => navTo(10, () => const ScoreboardScreen(showBack: true))),
                    _buildMenuCard(context, 'COMPLIANCE', Icons.verified_user_rounded, const [Color(0xFF0E3A2A), Color(0xFF061A13)], const Color(0xFF00FF88), () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const ComplianceScreen(showBack: true))); }),
                    _buildMenuCard(context, 'BROKER SHIELD', Icons.shield_rounded, const [Color(0xFF0F3D4A), Color(0xFF061A21)], const Color(0xFF00E5FF), () => navTo(12, () => const BrokerScreen(showBack: true))),
                    _buildMenuCard(context, 'SETTINGS', Icons.settings_rounded, const [Color(0xFF1A2030), Color(0xFF0F1520)], Colors.white70, () => navTo(13, () => const SettingsScreen(showBack: true))),


                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    ),
  );
}

Widget _buildMenuCard(BuildContext context, String title, IconData icon, List<Color> gradient, Color accentColor, VoidCallback onTap) {
  return GestureDetector(
    onTap: onTap,
    child: Container(
      height: 110,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: gradient),
        border: Border.all(color: Colors.white.withOpacity(0.06), width: 0.5),
        boxShadow: [BoxShadow(color: gradient[0].withOpacity(0.25), blurRadius: 16, offset: const Offset(0, 6))],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [Colors.white.withOpacity(0.12), Colors.white.withOpacity(0.03)]),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 3))],
            ),
            child: Icon(icon, color: accentColor, size: 22),
          ),
          const SizedBox(height: 10),
          Text(title, style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.2), textAlign: TextAlign.center),
        ],
      ),
    ),
  );
}
