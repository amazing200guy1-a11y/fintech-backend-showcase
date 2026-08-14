import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/layouts/home_mobile_layout.dart';
import 'package:mehd_ai_flutter/layouts/home_tablet_layout.dart';
import 'package:mehd_ai_flutter/layouts/home_desktop_layout.dart';
import 'package:mehd_ai_flutter/controllers/trading_controller.dart';
import 'package:mehd_ai_flutter/controllers/market_data_controller.dart';
import 'dart:ui' show ImageFilter;
import 'package:mehd_ai_flutter/services/payment_service.dart';
import 'package:mehd_ai_flutter/widgets/tutorial_overlay.dart';
import 'package:mehd_ai_flutter/widgets/onboarding_tips.dart';
import 'package:shared_preferences/shared_preferences.dart';

// New Tabs
import 'package:mehd_ai_flutter/screens/tabs/command_tab.dart';
import 'package:mehd_ai_flutter/screens/tabs/portfolio_tab.dart';
import 'package:mehd_ai_flutter/screens/den/the_den_screen.dart';

import 'package:mehd_ai_flutter/screens/settings_screen.dart';

import 'package:mehd_ai_flutter/widgets/autopilot_nav_menu.dart';
import 'package:mehd_ai_flutter/core/api_service.dart';
class AutopilotCommandCenter extends StatefulWidget {
  const AutopilotCommandCenter({super.key});

  @override
  State<AutopilotCommandCenter> createState() => _AutopilotCommandCenterState();
}

class _AutopilotCommandCenterState extends State<AutopilotCommandCenter> with SingleTickerProviderStateMixin {
  int _currentIndex = 0;
  Timer? _pollingTimer;
  bool _showOnboarding = false;
  Map<String, dynamic>? _commandCenterStatus;
  final ApiService _apiService = ApiService();
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
      final data = await _apiService.getCommandCenterStatus();
      if (data != null && mounted) {
        setState(() => _commandCenterStatus = data);
      }
    } catch (e) {
      debugPrint("Command Center status fetch failed: $e");
    }
  }

  void _showDenActionMenu(BuildContext context) =>
      showDenActionMenu(context, _desktopIndexNotifier);


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
                      _commandCenterStatus != null
                          ? (_commandCenterStatus!['system_status'] as String? ?? 'ACTIVE')
                          : (isLive ? 'LIVE' : 'IDLE'),
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
          const SizedBox(height: 28),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: MehdAiTheme.blue,
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bolt, color: Colors.black, size: 20),
                SizedBox(width: 8),
                Text(
                  'UPGRADE ACCOUNT — FROM \$79/MO',
                  style: TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
