import 'package:flutter/material.dart';
import 'package:mehd_ai_flutter/controllers/trading_controller.dart';
import 'package:mehd_ai_flutter/controllers/market_data_controller.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/widgets/symbol_sidebar.dart';
import 'package:mehd_ai_flutter/widgets/den_chart.dart';
import 'package:mehd_ai_flutter/widgets/consensus_bar.dart';
import 'package:mehd_ai_flutter/widgets/ai_terminal.dart';
import 'package:mehd_ai_flutter/widgets/den_sidebar.dart';
import 'package:mehd_ai_flutter/widgets/data_freshness_indicator.dart';
import 'package:provider/provider.dart';

// Screens
import 'package:mehd_ai_flutter/screens/war_room_screen.dart';
import 'package:mehd_ai_flutter/screens/broker_screen.dart'; // ADDED
import 'package:mehd_ai_flutter/screens/den/terminal_screen.dart';
import 'package:mehd_ai_flutter/screens/den/positions_screen.dart';
import 'package:mehd_ai_flutter/screens/den/the_den_screen.dart';
import 'package:mehd_ai_flutter/screens/tabs/command_tab.dart';
import 'package:mehd_ai_flutter/screens/pulse_trading_screen.dart';
import 'package:mehd_ai_flutter/screens/sandbox_mode_screen.dart';
import 'package:mehd_ai_flutter/screens/history_screen.dart';
import 'package:mehd_ai_flutter/screens/den/network_screen.dart';
import 'package:mehd_ai_flutter/screens/data_moat_screen.dart';
import 'package:mehd_ai_flutter/screens/settings_screen.dart';
import 'package:mehd_ai_flutter/screens/scoreboard_screen.dart';
import 'package:mehd_ai_flutter/screens/journey_screen.dart';

class HomeDesktopLayout extends StatefulWidget {
  final TradingController trading;
  final MarketDataController market;
  final VoidCallback? onLogoTap;
  final ValueNotifier<int>? indexNotifier;

  const HomeDesktopLayout({
    super.key, 
    required this.trading, 
    required this.market,
    this.onLogoTap,
    this.indexNotifier,
  });

  @override
  State<HomeDesktopLayout> createState() => _HomeDesktopLayoutState();
}

class _HomeDesktopLayoutState extends State<HomeDesktopLayout> {
  // INDEX 0 = WAR ROOM (HOME SCREEN)
  int _selectedIndex = 0;
  final GlobalKey<DenChartState> _chartKey = GlobalKey<DenChartState>();

  @override
  void initState() {
    super.initState();
    widget.indexNotifier?.addListener(_onExternalNavigation);
  }

  void _onExternalNavigation() {
    if (mounted && widget.indexNotifier != null) {
      setState(() => _selectedIndex = widget.indexNotifier!.value);
    }
  }

  bool _isMarketsSidebarExpanded = true;
  bool _isTerminalExpanded = true;

  @override
  void dispose() {
    widget.indexNotifier?.removeListener(_onExternalNavigation);
    super.dispose();
  }

  // Sidebar index mapping (matches den_sidebar.dart order):
  // 0 = War Room (HOME)
  // 1 = Terminal
  // 2 = Markets
  // 3 = Positions
  // 4 = The Den
  // 5 = Autopilot
  // 6 = Pulse Trading
  // 7 = Sandbox Mode
  // 8 = History
  // 9 = Network
  // 10 = Scoreboard
  // 11 = Data Moat
  // 12 = Brokers (Broker Shield)
  // 13 = Settings
  // 14 = Journey

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MehdAiTheme.background(context),
      body: Stack(
        children: [
          // Ambient background orbs for glassmorphism
          Positioned(
            top: -200,
            left: -100,
            child: Container(
              width: 600,
              height: 600,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [MehdAiTheme.blue.withOpacity(0.05), Colors.transparent],
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -300,
            right: 100,
            child: Container(
              width: 800,
              height: 800,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [MehdAiTheme.purple.withOpacity(0.04), Colors.transparent],
                ),
              ),
            ),
          ),
          // Main UI
          Row(
            children: [
              DenSidebar(
                selectedIndex: _selectedIndex,
                onLogoTap: widget.onLogoTap,
                onSelect: (int index) {
                  // ALL screens render inline — sidebar always stays visible
                  setState(() => _selectedIndex = index);
                },
              ),
              VerticalDivider(width: 1, color: MehdAiTheme.border(context)),
              
              // Show symbol sidebar only when on Markets tab
              if (_selectedIndex == 2) ...[
                SymbolSidebar(
                  activeSymbol: widget.market.activeSymbol ?? '', 
                  onSymbolSelected: (s) => widget.market.selectSymbol(s, onStatusMsg: (_) {}),
                  isExpanded: _isMarketsSidebarExpanded,
                  onToggle: () => setState(() => _isMarketsSidebarExpanded = !_isMarketsSidebarExpanded),
                  snapshot: widget.market.latestSnapshot,
                ),
                VerticalDivider(width: 1, color: MehdAiTheme.border(context)),
              ],
              
              // MAIN CONTENT AREA
              Expanded(
                flex: 7,
                child: _buildMainContent(),
              ),
              
              // AI TERMINAL SIDEBAR (shown on Markets view)
              if (_selectedIndex == 2) ...[
                VerticalDivider(width: 1, color: MehdAiTheme.border(context)),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeInOut,
                  width: _isTerminalExpanded ? 320 : 48,
                  child: !_isTerminalExpanded
                      ? GestureDetector(
                          onTap: () => setState(() => _isTerminalExpanded = true),
                          child: Container(
                            color: MehdAiTheme.bgSecondary,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 16.0),
                                  child: Icon(Icons.keyboard_double_arrow_left, color: MehdAiTheme.textSecondary, size: 20),
                                ),
                                const Spacer(),
                                RotatedBox(
                                  quarterTurns: 3,
                                  child: Text('AI TERMINAL', style: MehdAiTheme.labelStyle.copyWith(letterSpacing: 2, fontSize: 10)),
                                ),
                                const SizedBox(height: 100),
                              ],
                            ),
                          ),
                        )
                      : Column(
                          children: [
                            Container(
                              height: 48,
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              decoration: BoxDecoration(
                                color: MehdAiTheme.bgSecondary,
                                border: Border(bottom: BorderSide(color: MehdAiTheme.border(context))),
                              ),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('AI TERMINAL', style: MehdAiTheme.labelStyle.copyWith(letterSpacing: 1.5, fontSize: 11)),
                                  IconButton(
                                    icon: const Icon(Icons.keyboard_double_arrow_right, color: MehdAiTheme.textSecondary, size: 20),
                                    onPressed: () => setState(() => _isTerminalExpanded = false),
                                    tooltip: 'Collapse Terminal',
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                  ),
                                ],
                              ),
                            ),
                            Expanded(
                              child: AiTerminal(
                                consensusResult: widget.market.consensus, 
                                isAnalyzing: widget.market.isAnalyzing, 
                                drawings: const [],
                                onStrikeComplete: () => widget.market.executeDrawings(),
                              ),
                            ),
                          ],
                        ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    switch (_selectedIndex) {
      case 0:
        // WAR ROOM — THE HOME SCREEN — Live connected
        return WarRoomScreen(
          isAnalyzing: widget.market.isAnalyzing,
          consensus: widget.market.consensus,
        );
      case 1:
        // TERMINAL MATRIX
        return const TerminalScreen();
      case 2:
        // MARKETS (Chart + Consensus)
        return _buildMarketsView();
      case 3:
        // POSITIONS LEDGER
        return const PositionsScreen();
      case 4:
        // THE DEN (Research/Strategy/Math rooms)
        return TheDenScreen(
          consensusResult: widget.market.consensus,
          isAnalyzing: widget.market.isAnalyzing,
          activeSymbol: widget.market.activeSymbol,
          onClose: () => setState(() => _selectedIndex = 0),
        );
      case 5:
        // AUTOPILOT COMMAND CENTER
        return const CommandTab();
      case 6:
        // PULSE TRADING
        return const PulseTradingScreen();
      case 7:
        // SANDBOX MODE
        return const SandboxModeScreen();
      case 8:
        // HISTORY
        return const HistoryScreen();
      case 9:
        // NETWORK
        return const NetworkScreen();
      case 10:
        // SCOREBOARD
        return const ScoreboardScreen();
      case 11:
        // DATA MOAT
        return const DataMoatScreen();
      case 12:
        // BROKER SHIELD (Health Score Dashboard)
        return const BrokerScreen();
      case 13:
        // SETTINGS
        return const SettingsScreen();
      case 14:
        // JOURNEY
        return const JourneyScreen();
      default:
        return WarRoomScreen(
          isAnalyzing: widget.market.isAnalyzing,
          consensus: widget.market.consensus,
        );
    }
  }

  Widget _buildMarketsView() {
    return Stack(
      children: [
        Column(
          children: [
            Expanded(
              child: widget.market.activeSymbol == null 
                ? _buildEmptyMarketState()
                : Column(
                    children: [
                      _buildChartHeaderArea(),
                      Expanded(
                        // Consumer ensures that when activeInterval changes and
                        // notifyListeners() fires, DenChart rebuilds with the new interval
                        child: Consumer<MarketDataController>(
                          builder: (ctx, market, _) => DenChart(
                            key: _chartKey,
                            symbol: market.activeSymbol!,
                            interval: market.activeInterval,
                            basePrice: market.latestSnapshot?.close ?? 0.0,
                            isAutoMode: market.drawingMode != 'MANUAL',
                            activeTool: market.activeTool,
                            commands: market.aiCommands,
                            onEvent: (data) async {
                               if (data['type'] == 'price_update') {
                                  final price = (data['price'] as num).toDouble();
                                  widget.market.updatePriceFromChart(price);
                               }
                               if (data['type'] == 'validate_request') {
                                  final price = (data['price'] as num).toDouble();
                                  await widget.market.validateManualLevel(price);
                               }
                            },
                          ),
                        ),
                      ),
                    ],
                  ),
            ),
            if (widget.market.activeSymbol != null)
              ConsensusBar(
                consensus: widget.market.consensus,
                buttonState: widget.market.btnState,
                onTradePressed: () => widget.trading.executeTrade(
                  context: context,
                  consensus: widget.market.consensus,
                  latestSnapshot: widget.market.latestSnapshot,
                  showError: (_) {},
                  onSuccess: () {},
                  onShowBrief: (_) {},
                  onShowAudit: (_) {},
                ),
                currentSpread: widget.market.latestSnapshot?.spread ?? 0.0,
              ),
          ],
        ),
      ],
    );
  }

  /// Premium empty state for when no symbol is selected
  Widget _buildEmptyMarketState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: MehdAiTheme.blue.withOpacity(0.05),
              border: Border.all(color: MehdAiTheme.blue.withOpacity(0.2)),
            ),
            child: Icon(Icons.candlestick_chart_rounded, 
              color: MehdAiTheme.blue.withOpacity(0.5), size: 36),
          ),
          const SizedBox(height: 24),
          Text('SELECT A SYMBOL', 
            style: MehdAiTheme.headingStyle.copyWith(
              fontSize: 16, letterSpacing: 3, color: MehdAiTheme.textSecondary)),
          const SizedBox(height: 8),
          Text('Choose a currency pair from the sidebar to begin analysis',
            style: MehdAiTheme.labelStyle.copyWith(
              color: MehdAiTheme.textSecondary.withOpacity(0.5), fontSize: 12)),
        ],
      ),
    );
  }

  Widget _buildChartHeaderArea() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: MehdAiTheme.surface(context),
        border: Border(bottom: BorderSide(color: MehdAiTheme.border(context))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          _buildChartHeader(),
          if (widget.market.drawingMode == "MANUAL") ...[
            const SizedBox(height: 8),
            _buildManualToolbar(),
          ],
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildChartHeader() {
    return Row(
      children: [
        Text(widget.market.activeSymbol ?? '', style: MehdAiTheme.labelStyle.copyWith(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
        const SizedBox(width: 16),
        DataFreshnessIndicator(snapshot: widget.market.latestSnapshot),
        const SizedBox(width: 24),
        // Timeframes
        Row(
          children: [
            _buildTimeframeBtn('1s'),
            const SizedBox(width: 4),
            _buildTimeframeBtn('1m'),
            const SizedBox(width: 4),
            _buildTimeframeBtn('5m'),
            const SizedBox(width: 4),
            _buildTimeframeBtn('15m'),
            const SizedBox(width: 4),
            _buildTimeframeBtn('1h'),
            const SizedBox(width: 4),
            _buildTimeframeBtn('1d'),
          ],
        ),
        const Spacer(),
        _buildToggleBtn("AUTO"),
        const SizedBox(width: 8),
        _buildToggleBtn("MANUAL"),
      ],
    );
  }

  Widget _buildTimeframeBtn(String tf) {
    final isActive = widget.market.activeInterval == tf;
    return InkWell(
      onTap: () {
        widget.market.setActiveInterval(tf);
      },
      borderRadius: BorderRadius.circular(4),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive ? MehdAiTheme.blue.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: isActive ? MehdAiTheme.blue : Colors.transparent),
        ),
        child: Text(
          tf.toUpperCase(),
          style: TextStyle(
            color: isActive ? MehdAiTheme.blue : Colors.grey,
            fontSize: 12,
            fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildManualToolbar() {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: MehdAiTheme.background(context).withOpacity(0.5),
        border: Border(bottom: BorderSide(color: MehdAiTheme.border(context))),
      ),
      child: Row(
        children: [
          _buildToolBtn('H-LINE', 'hline'),
          _buildToolBtn('FIB', 'fib'),
          _buildToolBtn('TREND', 'trend'),
          const Spacer(),
          GestureDetector(
            onTap: () {
              _chartKey.currentState?.clearDrawings();
              widget.market.clearConsensus();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF1A0000)),
                borderRadius: BorderRadius.circular(3)
              ),
              child: const Text('CLR', style: TextStyle(color: Color(0xFFFF3B3B), fontSize: 9)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToolBtn(String label, String tool) {
    final isActive = widget.market.activeTool == tool;
    return GestureDetector(
      onTap: () => widget.market.setActiveTool(tool),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        margin: const EdgeInsets.only(right: 8),
        decoration: BoxDecoration(
          border: Border.all(color: isActive ? const Color(0xFF58A6FF) : const Color(0xFF222222)),
          color: isActive ? const Color(0xFF020810) : Colors.transparent,
          borderRadius: BorderRadius.circular(3)
        ),
        child: Text(label, style: TextStyle(color: isActive ? const Color(0xFF58A6FF) : const Color(0xFF666666), fontSize: 9, letterSpacing: 0.5, fontWeight: FontWeight.bold)),
      ),
    );
  }

  Widget _buildToggleBtn(String mode) {
    final isSelected = widget.market.drawingMode == mode;
    return GestureDetector(
      onTap: () => widget.market.toggleDrawingMode(mode),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF58A6FF).withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: isSelected ? const Color(0xFF58A6FF) : MehdAiTheme.border(context)),
        ),
        child: Text(
          mode, 
          style: TextStyle(
            color: isSelected ? const Color(0xFF58A6FF) : MehdAiTheme.textSecondary,
            fontSize: 11,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
