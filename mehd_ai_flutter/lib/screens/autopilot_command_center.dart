import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/layouts/home_mobile_layout.dart';
import 'package:mehd_ai_flutter/layouts/home_tablet_layout.dart';
import 'package:mehd_ai_flutter/layouts/home_desktop_layout.dart';
import 'package:mehd_ai_flutter/controllers/trading_controller.dart';
import 'package:mehd_ai_flutter/controllers/market_data_controller.dart';
import 'dart:ui';
import 'package:mehd_ai_flutter/services/payment_service.dart';
import 'package:mehd_ai_flutter/widgets/tutorial_overlay.dart';
import 'package:mehd_ai_flutter/widgets/onboarding_tips.dart';
import 'package:shared_preferences/shared_preferences.dart';

// New Tabs
import 'package:mehd_ai_flutter/screens/tabs/command_tab.dart';
import 'package:mehd_ai_flutter/screens/tabs/portfolio_tab.dart';
import 'package:mehd_ai_flutter/screens/den/the_den_screen.dart';

import 'package:mehd_ai_flutter/screens/war_room_community_screen.dart';
import 'package:mehd_ai_flutter/screens/war_room_screen.dart';
import 'package:mehd_ai_flutter/screens/scoreboard_screen.dart';
import 'package:mehd_ai_flutter/screens/den/network_screen.dart';
import 'package:mehd_ai_flutter/screens/den/sovereign_feed_screen.dart';
import 'package:mehd_ai_flutter/screens/data_moat_screen.dart';
import 'package:mehd_ai_flutter/screens/calculators_screen.dart';
import 'package:mehd_ai_flutter/screens/journey_screen.dart';
import 'package:mehd_ai_flutter/screens/settings_screen.dart';
import 'package:mehd_ai_flutter/screens/den/strategy_room.dart';
import 'package:mehd_ai_flutter/screens/den/research_room.dart';
import 'package:mehd_ai_flutter/screens/den/positions_screen.dart' as den_pos;
import 'package:mehd_ai_flutter/screens/pulse_trading_screen.dart';
import 'package:mehd_ai_flutter/screens/sandbox_mode_screen.dart';

class AutopilotCommandCenter extends StatefulWidget {
  const AutopilotCommandCenter({super.key});

  @override
  State<AutopilotCommandCenter> createState() => _AutopilotCommandCenterState();
}

class _AutopilotCommandCenterState extends State<AutopilotCommandCenter> with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  Timer? _pollingTimer;
  bool _showOnboarding = false;
  // Controls the desktop sidebar index from the Tiger menu
  final ValueNotifier<int> _desktopIndexNotifier = ValueNotifier(0);

  @override
  void initState() {
    super.initState();
    _fetchStatus();
    _pollingTimer = Timer.periodic(const Duration(seconds: 3), (_) => _fetchStatus());
    _checkOnboarding();

    Future.microtask(() {
      if (!mounted) return;
      TutorialOverlay.checkAndShow(
        context: context,
        screenKey: 'autopilot',
        title: 'Institutional Terminal',
        subtitle: 'Autonomous Execution Protocol',
        items: [
          const TutorialItem(
            title: 'Autonomous Execution',
            description: 'The Den processes raw intelligence into precise execution. All trades are mathematically verified against institutional risk boundaries.',
            leading: Icon(Icons.hub_rounded, color: MehdAiTheme.blue),
          ),
          const TutorialItem(
            title: 'Operational States',
            description: 'A "HUNTING" status indicates the terminal is calculating the optimal entry. Do not override the automated sniper protocol.',
            leading: Icon(Icons.radar_rounded, color: MehdAiTheme.green),
          ),
          const TutorialItem(
            title: 'Operational Protocol',
            description: 'Initialize the execution switch, then monitor the terminal. The system enforces discipline while you focus on high-level strategy.',
            leading: Icon(Icons.security_rounded, color: MehdAiTheme.gold),
          ),
        ],
      );
    });
  }

  Future<void> _checkOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    final hasSeen = prefs.getBool('has_seen_onboarding') ?? false;
    if (!hasSeen && mounted) {
      setState(() {
        _showOnboarding = true;
      });
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _desktopIndexNotifier.dispose();
    super.dispose();
  }

  Future<void> _fetchStatus() async {
    try {
      // Mock status fetch
    } catch (e) {
      debugPrint("Status fetch failed: $e");
    }
  }

  void _showDenActionMenu(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width > 1200;

    // Helper: on desktop navigate sidebar, on mobile push a screen
    void navTo(int desktopIndex, Widget Function() mobileBuilder) {
      Navigator.pop(context);
      if (isDesktop) {
        _desktopIndexNotifier.value = desktopIndex;
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
              const Text('Navigation',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
              const SizedBox(height: 6),
              const Text('Select a feature to open',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
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
                      _buildMenuCard(context, 'WAR ROOM', Icons.radar_rounded, const [Color(0xFF3A0E0E), Color(0xFF1F0707)], const Color(0xFFFF4444),
                        () {
                          final market = Provider.of<MarketDataController>(context, listen: false);
                          navTo(0, () => WarRoomScreen(
                            isAnalyzing: market.isAnalyzing,
                            consensus: market.consensus,
                          ));
                        }),
                        
                      _buildMenuCard(context, 'SCOREBOARD', Icons.emoji_events_rounded, const [Color(0xFF0E3A18), Color(0xFF061A0C)], const Color(0xFF00FF88),
                        () => navTo(10, () => const ScoreboardScreen())),
                        
                      _buildMenuCard(context, 'AUTOPILOT', Icons.precision_manufacturing_rounded, const [Color(0xFF0E2A3A), Color(0xFF061520)], const Color(0xFF58A6FF),
                        () => navTo(5, () => const AutopilotCommandCenter())),
                        
                      _buildMenuCard(context, 'NETWORK', Icons.group_work_rounded, const [Color(0xFF3A2B0E), Color(0xFF1A1306)], const Color(0xFFFFD700),
                        () => navTo(9, () => const NetworkScreen())),
                        
                      _buildMenuCard(context, 'DATA MOAT', Icons.hub_rounded, const [Color(0xFF0F3D4A), Color(0xFF061A21)], const Color(0xFF00E5FF),
                        () => navTo(11, () => const DataMoatScreen())),
                        
                      _buildMenuCard(context, 'POSITIONS', Icons.show_chart_rounded, const [Color(0xFF4A3A0E), Color(0xFF211A06)], const Color(0xFFFFD700),
                        () => navTo(3, () => const den_pos.PositionsScreen())),
                        
                      _buildMenuCard(context, 'STRATEGY', Icons.account_balance_rounded, const [Color(0xFF0E3A4A), Color(0xFF061A21)], const Color(0xFF00FFCC),
                        () => navTo(4, () => Scaffold(appBar: AppBar(title: const Text('STRATEGY STRATEGY')), backgroundColor: MehdAiTheme.bgPrimary, body: const StrategyRoom()))),
                        
                      _buildMenuCard(context, 'RESEARCH', Icons.travel_explore_rounded, const [Color(0xFF2D1B4E), Color(0xFF1A0F30)], const Color(0xFFBC8CFF),
                        () => navTo(4, () => Scaffold(appBar: AppBar(title: const Text('RESEARCH INTELLIGENCE')), backgroundColor: MehdAiTheme.bgPrimary, body: const ResearchRoom()))),
                        
                      _buildMenuCard(context, 'NEURO PULSE', Icons.psychology_rounded, const [Color(0xFF0A2A18), Color(0xFF06180E)], const Color(0xFF00FF88),
                        () => navTo(6, () => const PulseTradingScreen())),
                        
                      _buildMenuCard(context, 'SANDBOX', Icons.visibility_rounded, const [Color(0xFF1A1040), Color(0xFF0D0820)], const Color(0xFFBC8CFF),
                        () => navTo(7, () => const SandboxModeScreen())),
                        
                      _buildMenuCard(context, 'JOURNEY', Icons.rocket_launch, const [Color(0xFF4A0E4E), Color(0xFF220526)], const Color(0xFF9E00FF),
                        () => navTo(14, () => const JourneyScreen())),
                        
                      _buildMenuCard(context, 'CALCULATOR', Icons.calculate_rounded, const [Color(0xFF2A1C0E), Color(0xFF140D07)], MehdAiTheme.gold,
                        () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const CalculatorsScreen())); }),
                        
                      _buildMenuCard(context, 'SOVEREIGN', Icons.hub_outlined, const [Color(0xFF0E2A3A), Color(0xFF061520)], const Color(0xFF58A6FF),
                        () => navTo(1, () => const SovereignFeedScreen())),
                        
                      _buildMenuCard(context, 'COMMUNITY', Icons.groups_rounded, const [Color(0xFF3A1B5E), Color(0xFF1F0F35)], MehdAiTheme.purple,
                        () { Navigator.pop(context); Navigator.push(context, MaterialPageRoute(builder: (_) => const WarRoomCommunityScreen())); }),
                        
                      _buildMenuCard(context, 'SETTINGS', Icons.settings_rounded, const [Color(0xFF1A2030), Color(0xFF0F1520)], Colors.white70,
                        () => navTo(12, () => const SettingsScreen())),
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

  Widget _buildMenuCard(BuildContext context, String title, IconData icon,
      List<Color> gradient, Color accentColor, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 110,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradient,
          ),
          border: Border.all(color: Colors.white.withOpacity(0.06), width: 0.5),
          boxShadow: [
            BoxShadow(
                color: gradient[0].withOpacity(0.25),
                blurRadius: 16,
                offset: const Offset(0, 6)),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Colors.white.withOpacity(0.12),
                    Colors.white.withOpacity(0.03),
                  ],
                ),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 3)),
                ],
              ),
              child: Icon(icon, color: accentColor, size: 22),
            ),
            const SizedBox(height: 10),
            Text(
              title,
              style: TextStyle(
                color: Colors.white.withOpacity(0.85),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isDesktop = width > 1200;

    // Desktop uses its own internal shell (Sidebar + Layouts)
    if (isDesktop) {
      return Stack(
        children: [
          Consumer2<TradingController, MarketDataController>(
            builder: (ctx, trading, market, _) {
              return HomeDesktopLayout(
                trading: trading, 
                market: market,
                onLogoTap: () => _showDenActionMenu(context),
                indexNotifier: _desktopIndexNotifier,
              );
            },
          ),
          if (_showOnboarding)
            OnboardingTips(onComplete: () {
              setState(() => _showOnboarding = false);
            }),
        ],
      );
    }

    // Mobile/Tablet uses the Autopilot Scaffold shell
    final mobileLayout = Scaffold(
      backgroundColor: MehdAiTheme.background(context),
      appBar: AppBar(
        backgroundColor: MehdAiTheme.surface(context),
        elevation: 0,
        toolbarHeight: 48,
        centerTitle: false,
        title: Consumer<PaymentService>(
          builder: (context, payment, _) {
            final isTiger = payment.isTigerModeEnabled;
            return Row(
              children: [
                ClipOval(
                  child: Image.asset('assets/images/mehd_logo.png', width: 22, height: 22),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Mehd AI',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    Text(
                      isTiger ? 'Tiger Mode active' : 'Signal monitor running',
                      style: const TextStyle(
                        color: Colors.white38,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ],
            );
          },
        ),
        actions: [
          // Live status dot — green = backend up, red = down
          Consumer<MarketDataController>(
            builder: (context, market, _) {
              final isLive = market.activeSymbol != null;
              return Padding(
                padding: const EdgeInsets.only(right: 16.0),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isLive
                            ? const Color(0xFF00FF88)
                            : const Color(0xFF444444),
                        boxShadow: isLive
                            ? [BoxShadow(color: const Color(0xFF00FF88).withOpacity(0.5), blurRadius: 6, spreadRadius: 1)]
                            : null,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isLive ? 'LIVE' : 'IDLE',
                      style: TextStyle(
                        color: isLive ? const Color(0xFF00FF88) : const Color(0xFF555555),
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: _buildBody(),
      extendBody: true,
      bottomNavigationBar: ClipRRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            color: MehdAiTheme.bgSecondary.withOpacity(0.85),
            child: BottomNavigationBar(
              type: BottomNavigationBarType.fixed,
              backgroundColor: Colors.transparent,
              selectedItemColor: MehdAiTheme.blue,
              unselectedItemColor: const Color(0xFF444444),
              selectedFontSize: 10,
              unselectedFontSize: 10,
              iconSize: 24,
              currentIndex: _currentIndex > 3 ? 0 : _currentIndex,
              onTap: (index) {
                if (index == 4) {
                  // HUB tab opens the grid menu — no screen change
                  _showDenActionMenu(context);
                  return;
                }
                setState(() {
                  _currentIndex = index;
                });
              },
              items: const [
                BottomNavigationBarItem(
                  icon: Icon(Icons.terminal_outlined),
                  activeIcon: Icon(Icons.terminal),
                  label: 'Terminal',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.hub_outlined),
                  activeIcon: Icon(Icons.hub),
                  label: 'The Den',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.precision_manufacturing_outlined),
                  activeIcon: Icon(Icons.precision_manufacturing),
                  label: 'Command',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.pie_chart_outline),
                  activeIcon: Icon(Icons.pie_chart),
                  label: 'Portfolio',
                ),
                BottomNavigationBarItem(
                  icon: Icon(Icons.apps_outlined),
                  activeIcon: Icon(Icons.apps),
                  label: 'Hub',
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (_showOnboarding) {
      return Stack(
        children: [
          mobileLayout,
          OnboardingTips(onComplete: () {
            setState(() => _showOnboarding = false);
          }),
        ],
      );
    }

    return mobileLayout;
  }

  Widget _buildBody() {
    final paymentService = Provider.of<PaymentService>(context);
    final tier = paymentService.currentTier.toLowerCase();

    // ── TIER GATING: OBSERVER MODE ──
    // Observer tier gets market intelligence only — not the execution terminal.
    if (tier == 'observer') {
      return _buildAccessOverlay(
        title: 'Upgrade Required',
        subtitle: 'The execution terminal is available on Core Trader plans and above. Your current plan includes market intelligence features.',
        icon: Icons.lock_outline_rounded,
        accent: MehdAiTheme.blue,
      );
    }

    Widget activeTab;
    switch (_currentIndex) {
      case 0:
        // TERMINAL — chart + AI terminal (the cleaned-up HomeMobileLayout)
        activeTab = Consumer2<TradingController, MarketDataController>(
          builder: (ctx, trading, market, _) {
            final width = MediaQuery.of(context).size.width;
            if (width > 768) {
              return HomeTabletLayout(trading: trading, market: market);
            }
            return HomeMobileLayout(trading: trading, market: market);
          },
        );
        break;
      case 1:
        // THE DEN — multi-agent analysis system
        activeTab = Consumer<MarketDataController>(
          builder: (ctx, market, _) {
            return TheDenScreen(
              consensusResult: market.consensus,
              isAnalyzing: market.isAnalyzing,
              activeSymbol: market.activeSymbol,
              onClose: () => setState(() => _currentIndex = 0),
            );
          },
        );
        break;
      case 2:
        // COMMAND — Autopilot execution tab
        activeTab = const CommandTab();
        break;
      case 3:
        // PORTFOLIO — positions + history
        activeTab = const PortfolioTab();
        break;
      default:
        activeTab = Consumer2<TradingController, MarketDataController>(
          builder: (ctx, trading, market, _) =>
            HomeMobileLayout(trading: trading, market: market),
        );
    }

    return activeTab;
  }

  Widget _buildAccessOverlay({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withOpacity(0.05),
              border: Border.all(color: accent.withOpacity(0.2)),
            ),
            child: Icon(icon, color: accent, size: 48),
          ),
          const SizedBox(height: 32),
          Text(
            title,
            textAlign: TextAlign.center,
            style: MehdAiTheme.headingStyle.copyWith(
              fontSize: 16,
              letterSpacing: 2,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: MehdAiTheme.labelStyle.copyWith(
              fontSize: 13,
              color: MehdAiTheme.textSecondary,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
