import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/core/constants.dart';
import 'package:mehd_ai_flutter/models/consensus_result.dart';
import 'package:mehd_ai_flutter/controllers/market_data_controller.dart';
import 'package:mehd_ai_flutter/controllers/trading_controller.dart';
import 'package:mehd_ai_flutter/services/settings_service.dart';
import 'package:mehd_ai_flutter/screens/den/research_room.dart';
import 'package:mehd_ai_flutter/screens/den/strategy_room.dart';
import 'package:mehd_ai_flutter/screens/den/math_room.dart';
import 'package:mehd_ai_flutter/screens/pulse_trading_screen.dart';
import 'package:mehd_ai_flutter/utils/titan_animations.dart';

/// FILE — the_den_screen.dart
///
/// Master Container for The Den.
/// Features a prominent 11-Agent Command Action Header, Symbol Switcher,
/// Autonomous Auto-Swarm toggle, and 1-tap Execution Strike.
class TheDenScreen extends StatefulWidget {
  final ConsensusResult? consensusResult;
  final bool isAnalyzing;
  final String? activeSymbol;
  final VoidCallback onClose;
  
  const TheDenScreen({
    super.key, 
    this.consensusResult,
    this.isAnalyzing = false,
    this.activeSymbol,
    required this.onClose,
  });

  @override
  State<TheDenScreen> createState() => _TheDenScreenState();
}

class _TheDenScreenState extends State<TheDenScreen> {
  final PageController _pageController = PageController(initialPage: 1); // Start in Strategy Room
  int _currentIndex = 1;
  // ignore: unused_field
  bool _autoSwarmActive = true; // Always-on autonomous — no manual scan button
  Timer? _autoSwarmTimer;

  static const List<String> _availablePairs = AppConstants.symbols;

  @override
  void initState() {
    super.initState();
    // Boot the autonomous swarm immediately — no user action required
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final market = context.read<MarketDataController>();
        market.triggerSwarmAnalysis();
        _startAutoSwarm();
      }
    });
  }

  @override
  void dispose() {
    _autoSwarmTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _onPageChanged(int index) {
    setState(() => _currentIndex = index);
  }

  void _navTo(int index) {
    _pageController.animateToPage(
      index, 
      duration: TitanAnimations.medium, 
      curve: TitanAnimations.emphasized,
    );
  }

  void _startAutoSwarm() {
    _autoSwarmTimer?.cancel();
    // Re-scan every 30 seconds — fully autonomous, no user input needed
    _autoSwarmTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) {
        final market = context.read<MarketDataController>();
        market.triggerSwarmAnalysis();
      }
    });
  }

  // Keep toggle for the AUTO 24/5 switch UI state only
  // ignore: unused_element
  void _toggleAutoSwarm(bool val) {
    setState(() => _autoSwarmActive = val);
    if (val) {
      _startAutoSwarm();
    } else {
      _autoSwarmTimer?.cancel();
    }
  }

  void _executeDenStrike(BuildContext context) {
    final market = context.read<MarketDataController>();
    final trading = context.read<TradingController>();
    final settings = context.read<SettingsService>();
    final symbol = market.activeSymbol ?? 'EUR/USD';
    final price = market.latestSnapshot?.close ?? 1.0850;
    final lot = settings.defaultLotSize;

    trading.executeSandboxTrade(symbol, 'BUY', price, lotSize: lot);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFF00FF88),
        content: Text('⚡ DEN STRIKE EXECUTED — BUY $symbol @ ${price.toStringAsFixed(4)} (Lot: ${lot.toStringAsFixed(2)})', style: GoogleFonts.outfit(color: Colors.black, fontWeight: FontWeight.bold)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final market = context.watch<MarketDataController>();
    final activeSymbol = market.activeSymbol ?? widget.activeSymbol ?? 'EUR/USD';
    final isAnalyzing = market.isAnalyzing || widget.isAnalyzing;
    final consensus = market.consensus ?? widget.consensusResult;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: MehdAiTheme.bgSecondary,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Row(
          children: [
            // Left: Title & Symbol Selector
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'THE DEN',
                  style: GoogleFonts.outfit(
                    color: const Color(0xFF58A6FF),
                    letterSpacing: 3,
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(width: 12),
                // Pair Selector Dropdown
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1117),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: MehdAiTheme.blue.withOpacity(0.4)),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: _availablePairs.contains(activeSymbol) ? activeSymbol : 'EUR/USD',
                      dropdownColor: const Color(0xFF161B22),
                      style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                      icon: const Icon(Icons.arrow_drop_down, color: MehdAiTheme.blue, size: 16),
                      onChanged: (newPair) {
                        if (newPair != null) {
                          market.selectSymbol(newPair, onStatusMsg: (_) {});
                        }
                      },
                      items: _availablePairs.map((pair) {
                        return DropdownMenuItem<String>(
                          value: pair,
                          child: Text(pair),
                        );
                      }).toList(),
                    ),
                  ),
                ),
              ],
            ),
            const Spacer(),

            // Center-Right: Action Bar Buttons
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (MediaQuery.of(context).size.width >= 768) ...[
                  // DESKTOP: Autonomous status badge — no manual scan button
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: isAnalyzing
                          ? const Color(0xFFFFD700).withOpacity(0.1)
                          : const Color(0xFF00FF88).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: isAnalyzing
                            ? const Color(0xFFFFD700).withOpacity(0.5)
                            : const Color(0xFF00FF88).withOpacity(0.4),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6, height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isAnalyzing ? const Color(0xFFFFD700) : const Color(0xFF00FF88),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          isAnalyzing ? 'SWARM ACTIVE' : 'AUTO 24/5',
                          style: GoogleFonts.outfit(
                            color: isAnalyzing ? const Color(0xFFFFD700) : const Color(0xFF00FF88),
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ] else ...[
                  // MOBILE: simple 24/5 AUTO badge — scanning is always automatic
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00FF88).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF00FF88).withOpacity(0.35)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(width: 6, height: 6, decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFF00FF88))),
                        const SizedBox(width: 6),
                        Text('24/5 AUTO', style: GoogleFonts.outfit(color: const Color(0xFF00FF88), fontSize: 10, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],

                // STRIKE TRADE Button — on all screens
                ElevatedButton.icon(
                  onPressed: () => _executeDenStrike(context),
                  icon: const Icon(Icons.bolt_rounded, size: 14),
                  label: Text('STRIKE TRADE', style: GoogleFonts.outfit(fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF3B3B).withOpacity(0.2),
                    foregroundColor: const Color(0xFFFF3B3B),
                    side: const BorderSide(color: Color(0xFFFF3B3B)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  ),
                ),
              ],
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(66),
          child: _buildRoomTabs(),
        ),
      ),
      body: PageView(
        controller: _pageController,
        onPageChanged: _onPageChanged,
        physics: const BouncingScrollPhysics(),
        children: [
          ResearchRoom(consensusResult: consensus, isAnalyzing: isAnalyzing, activeSymbol: activeSymbol),
          StrategyRoom(consensusResult: consensus, isAnalyzing: isAnalyzing, activeSymbol: activeSymbol),
          MathRoom(consensusResult: consensus, isAnalyzing: isAnalyzing, activeSymbol: activeSymbol),
          const PulseTradingScreen(),
        ],
      ),
    );
  }

  Widget _buildRoomTabs() {
    return Container(
      height: 66,
      decoration: const BoxDecoration(
        color: MehdAiTheme.bgSecondary,
        border: Border(bottom: BorderSide(color: MehdAiTheme.borderColor)),
      ),
      child: SafeArea(
        bottom: true,
        child: Row(
          children: [
            Expanded(
              child: _buildTabCard(
                0,
                'RESEARCH',
                Icons.travel_explore_rounded,
                const [Color(0xFF0F172A), Color(0xFF020617)],
                MehdAiTheme.blue,
              ),
            ),
            Expanded(
              child: _buildTabCard(
                1,
                'STRATEGY',
                Icons.hub_rounded,
                const [Color(0xFF1E1B4B), Color(0xFF0F0E2E)],
                MehdAiTheme.purple,
              ),
            ),
            Expanded(
              child: _buildTabCard(
                2,
                'OLYMPUS',
                Icons.show_chart_rounded,
                const [Color(0xFF1C1917), Color(0xFF0C0A09)],
                MehdAiTheme.gold,
              ),
            ),
            Expanded(
              child: _buildTabCard(
                3,
                'NEURO PULSE',
                Icons.psychology_rounded,
                const [Color(0xFF0A2A18), Color(0xFF06180E)],
                MehdAiTheme.green,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabCard(
    int index,
    String title,
    IconData icon,
    List<Color> bgGradient,
    Color accentColor,
  ) {
    final isSelected = _currentIndex == index;
    return GestureDetector(
      onTap: () => _navTo(index),
      child: AnimatedContainer(
        duration: TitanAnimations.fast,
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isSelected ? bgGradient : [MehdAiTheme.bgSecondary, MehdAiTheme.bgSecondary],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? accentColor.withOpacity(0.6) : MehdAiTheme.borderColor.withOpacity(0.5),
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: accentColor.withOpacity(0.2),
                    blurRadius: 8,
                    spreadRadius: 1,
                  )
                ]
              : [],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? accentColor : MehdAiTheme.textSecondary,
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: TextStyle(
                color: isSelected ? Colors.white : MehdAiTheme.textSecondary,
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
