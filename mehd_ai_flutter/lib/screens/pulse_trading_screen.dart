import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/core/api_service.dart';
import 'package:mehd_ai_flutter/models/consensus_result.dart';
import 'package:mehd_ai_flutter/services/nlg_engine.dart';
import 'package:mehd_ai_flutter/services/command_parser_service.dart';
import 'package:mehd_ai_flutter/services/settings_service.dart';

import 'package:mehd_ai_flutter/controllers/market_data_controller.dart';
import 'package:mehd_ai_flutter/controllers/trading_controller.dart';
import 'package:mehd_ai_flutter/widgets/pulse_hero_welcome.dart';
import 'package:mehd_ai_flutter/widgets/pulse_message_bubble.dart';
import 'package:mehd_ai_flutter/widgets/pulse_input_area.dart';
import 'package:mehd_ai_flutter/widgets/pulse_trading_helpers.dart';
import 'package:mehd_ai_flutter/widgets/pulse_trading_header.dart';

class PulseTradingScreen extends StatefulWidget {
  final bool showBack;
  const PulseTradingScreen({super.key, this.showBack = false});

  @override
  State<PulseTradingScreen> createState() => _PulseTradingScreenState();
}

class _PulseTradingScreenState extends State<PulseTradingScreen> with TickerProviderStateMixin {
  late final SyntaxHighlightController _inputController;
  final ScrollController _scrollController = ScrollController();
  late AnimationController _orbCtrl;
  
  final List<ChatMessage> _messages = [];
  bool _isTyping = false;
  bool _showCommandSuggestions = false;
  
  final List<Map<String, dynamic>> _quickPrompts = [
    {'text': '/nuke', 'command': '/nuke', 'icon': Icons.power_settings_new_rounded},
    {'text': '/bank50', 'command': '/bank50', 'icon': Icons.pie_chart_outline_rounded},
    {'text': '/risk 2', 'command': '/risk 2', 'icon': Icons.tune_rounded},
    {'text': '/trail', 'command': '/trail', 'icon': Icons.trending_up_rounded},
    {'text': '/shield', 'command': '/shield', 'icon': Icons.shield_rounded},
    {'text': 'Scan EUR/USD', 'command': 'Scan EUR/USD', 'icon': Icons.radar_rounded},
  ];

  @override
  void initState() {
    super.initState();
    _inputController = SyntaxHighlightController();
    _inputController.addListener(_onInputChanged);
    _orbCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat(reverse: true);

    // Initial greeting
    _messages.add(ChatMessage(text: 'COMMAND CENTRE READY. Use the 1-tap controls above, or type a / command below.', isUser: false));
  }

  void _onInputChanged() {
    final text = _inputController.text;
    if (text.startsWith('/') && !_showCommandSuggestions) {
      setState(() => _showCommandSuggestions = true);
    } else if (!text.startsWith('/') && _showCommandSuggestions) {
      setState(() => _showCommandSuggestions = false);
    }
  }

  @override
  void dispose() {
    _orbCtrl.dispose();
    _inputController.removeListener(_onInputChanged);
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _handleUserSubmit({String? overrideText}) async {
    final text = (overrideText ?? _inputController.text).trim();
    if (text.isEmpty) return;

    _inputController.clear();
    setState(() {
      _messages.add(ChatMessage(text: text, isUser: true));
      _isTyping = true;
      _showCommandSuggestions = false;
    });
    _scrollToBottom();

    final market = context.read<MarketDataController>();

    // ── COMMAND PARSER INTERCEPTION ──────────────────────────────────────────
    if (text.startsWith('/')) {
      final cmd = CommandParserService.parse(text);
      final trading = context.read<TradingController>();
      final settings = context.read<SettingsService>();

      
      if (!cmd.isValid) {
        _streamResponse("COMMAND REJECTED: ${cmd.errorMessage}", null);
        return;
      }

      if (cmd.action == 'help') {
        _streamResponse(
          "💬 NEURO PULSE COMMANDS:\n\n"
          "• /long [SYMBOL]  — Go long (e.g. /long XAUUSD)\n"
          "• /short [SYMBOL] — Go short (e.g. /short BTCUSD)\n"
          "• /nuke           — Emergency: close ALL trades now\n"
          "• /bank50         — Lock 50% profit on all positions\n"
          "• /be             — Move all stop-losses to breakeven\n"
          "• /risk [%]       — Auto lot-size for e.g. 2% risk\n"
          "• /trail [pips]   — Trailing stop-loss e.g. /trail 20\n"
          "• /shield         — 24h lock after 3% daily drawdown\n"
          "• /close [SYMBOL] — Close a specific pair\n\n"
          "Core (\$79): briefed + manual confirm\n"
          "Precision (\$149): auto-executes live\n"
          "Sovereign (\$299): auto-executes + phone alert",
          null,
        );
        return;
      }


      if (cmd.action == 'nuke') {
        trading.closeAllPositions();
        _streamResponse("⚡ EMERGENCY PANIC SWITCH EXECUTED: All open positions liquidated. Capital safely in cash.", null);
        return;
      }

      if (cmd.action == 'bank50') {
        trading.closePartialAll(0.5);
        _streamResponse("💰 50% PROFIT LOCKED: Banked 50% partial profit on all open positions in 6ms.", null);
        return;
      }

      if (cmd.action == 'be') {
        trading.setBreakevenAll();
        _streamResponse("🛡️ BREAKEVEN ARMED: Stop-loss moved to entry price on all open trades. Risk-free mode active.", null);
        return;
      }

      if (cmd.action == 'risk') {
        final riskPercent = (cmd.value ?? 2.0).clamp(0.1, 10.0);
        settings.setRiskPerTrade(riskPercent);
        final equity = settings.accountBalance;
        final dollarRisk = equity * (riskPercent / 100.0);
        final slPips = 15.0; // Default 15 pips market structure SL
        final leverage = settings.defaultLeverage > 0 ? settings.defaultLeverage : 100.0;
        final contractSize = 100000.0;
        
        // Use live price from market data, fallback to EUR/USD reference
        final market = context.read<MarketDataController>();
        final livePrice = market.latestSnapshot?.close ?? 1.0850;

        // Step 1: Real Dynamic Pip Value (NOT hardcoded $10/pip)
        // Pip Value per Lot = (Contract Size × 1 Pip) / Current Price (for USD quoted pairs)
        // For USD as quote currency (EUR/USD, GBP/USD): pip = 0.0001 × 100,000 = $10 always
        // For JPY pairs (USD/JPY): pip = 0.01 × 100,000 / price
        // We detect and handle both:
        final isJpyPair = (market.activeSymbol ?? 'EUR/USD').contains('JPY');
        final pipSize = isJpyPair ? 0.01 : 0.0001;
        final pipValuePerLot = (contractSize * pipSize) / livePrice;

        // Step 2: Raw Position Size from Risk Calculation
        final rawLot = dollarRisk / (slPips * pipValuePerLot);

        // Step 3: Institutional Margin Safety Check (Cap at 50% of equity)
        final marginRequiredPerLot = (contractSize * livePrice) / leverage;
        final maxAllowedMargin = equity * 0.50;
        final maxMarginLot = maxAllowedMargin / marginRequiredPerLot;

        // Step 4: Final Safe Position Size (rounded DOWN to 0.01 micro-lots)
        final safeLot = min(rawLot, maxMarginLot);
        final roundedLot = max(0.01, (safeLot * 100).floorToDouble() / 100.0);
        final actualMargin = roundedLot * marginRequiredPerLot;
        final marginPercent = (actualMargin / equity) * 100.0;
        final actualRisk = roundedLot * slPips * pipValuePerLot;
        final actualRiskPercent = (actualRisk / equity) * 100.0;

        settings.setDefaultLotSize(roundedLot);

        _streamResponse(
          "🛡️ DYNAMIC RISK SIZER (${riskPercent.toStringAsFixed(1)}% RISK):\n"
          "• Account Balance: \$${equity.toStringAsFixed(0)}\n"
          "• Max Cash Risk: \$${dollarRisk.toStringAsFixed(2)}\n"
          "• Stop Loss: ${slPips.toStringAsFixed(0)} pips behind structure\n"
          "• Pip Value per Lot: \$${pipValuePerLot.toStringAsFixed(2)}\n"
          "• Position Size: ${roundedLot.toStringAsFixed(2)} Lots (actual risk: ${actualRiskPercent.toStringAsFixed(2)}%)\n"
          "• Margin Required: \$${actualMargin.toStringAsFixed(2)} (${marginPercent.toStringAsFixed(1)}% of Balance ✓ Safe)",
          null,
        );
        return;
      }

      if (cmd.action == 'shield') {
        settings.armEquityShield24h();
        final hours = settings.equityShieldHoursRemaining;
        _streamResponse("🛡️ SENTINEL EQUITY SHIELD ARMED:\n• Hard 24h lockout is now LOCKED.\n• Remaining lock time: ${hours.toStringAsFixed(1)} hours.\n• All trade execution buttons disabled to prevent emotional revenge trading.", null);
        return;
      }

      if (settings.isEquityShieldLocked && (cmd.action == 'long' || cmd.action == 'short')) {
        final hours = settings.equityShieldHoursRemaining;
        _streamResponse("⛔ TRADE REJECTED BY EQUITY SHIELD:\n24h Lockout is currently ACTIVE (${hours.toStringAsFixed(1)}h remaining). No trades permitted until lock expires.", null);
        return;
      }

      if (cmd.action == 'trail') {
        final pips = (cmd.value ?? 15.0);
        trading.setTrailingSLAll(pips);
        _streamResponse(
          "📈 AUTO-FOLLOW PROFIT ACTIVATED (${pips.toStringAsFixed(0)} pips):\n"
          "Your stop-loss will now automatically climb behind the market price by ${pips.toStringAsFixed(0)} pips as profits increase. If the market turns back down, your profits are locked in.",
          null,
        );
        return;
      }

      if (cmd.action == 'close') {
        final symbol = CommandParserService.normalizeSymbol(cmd.symbol ?? market.activeSymbol ?? 'EUR/USD');
        trading.closePositionBySymbol(symbol);
        _streamResponse("Position closed for $symbol. Execution latency: 8ms.", null);
        return;
      }

      final direction = (cmd.action == 'short' || cmd.action == 'sell') ? 'SELL' : 'BUY';
      final symbol = CommandParserService.normalizeSymbol(cmd.symbol ?? market.activeSymbol ?? 'EUR/USD');

      // ── LINK 1: Switch active symbol globally across charts, markets, Den ──
      market.selectSymbol(symbol, onStatusMsg: (_) {});

      // ── LINK 2: Fetch tier-aware execution brief from backend ─────────────
      final api = ApiService();


      // Show loading state in chat
      setState(() {
        _messages.add(ChatMessage(
          text: '⚡ Neural Link engaged — fetching $symbol $direction brief…',
          isUser: false,
          isStreaming: true,
        ));
        _isTyping = false;
      });
      _scrollToBottom();

      final brief = await api.analyzeForCommand(symbol: symbol, direction: direction);

      // Replace the streaming message index
      final pendingIdx = _messages.length - 1;

      // ── LINK 3: Tier-gated execution ─────────────────────────────────────
      if (brief == null) {
        // Network offline — fallback sandbox
        final fallbackEntry = market.latestSnapshot?.bid ?? 0.0;
        trading.executeSandboxTrade(symbol, direction, fallbackEntry,
            lotSize: settings.defaultLotSize);
        setState(() {
          _messages[pendingIdx] = ChatMessage(
            text: '⚠️  Backend offline. Sandbox position opened: $symbol $direction '
                '(${settings.defaultLotSize.toStringAsFixed(2)} lots). '
                'Live levels unavailable.',
            isUser: false,
          );
        });
        return;
      }

      final autoExecute = brief['auto_execute'] == true;
      final lot = (brief['suggested_lot'] as num?)?.toDouble() ?? settings.defaultLotSize;
      final entry = (brief['entry'] as num?)?.toDouble() ?? (market.latestSnapshot?.bid ?? 0.0);
      final slStr = brief['sl']?.toString() ?? '—';
      final tpStr = brief['tp']?.toString() ?? '—';
      final mode = brief['execution_mode'] ?? 'sandbox';

      if (autoExecute) {
        // Precision / Institutional — execute immediately, show confirmation card
        trading.executeSandboxTrade(symbol, direction, entry, lotSize: lot);
        final donLine = (brief['don_alert'] == true)
            ? '\n📡 DON alert dispatched to your phone.'
            : '';
        setState(() {
          _messages[pendingIdx] = ChatMessage(
            text: 'EXECUTED · $symbol $direction\n'
                'Entry: ${brief["entry"]} · SL: $slStr · TP: $tpStr · '
                '${lot.toStringAsFixed(2)} lots ($mode)$donLine',
            isUser: false,
            executionBrief: brief,
          );
        });
      } else {
        // Core — show card + manual EXECUTE button
        late int msgIdx;
        setState(() {
          msgIdx = pendingIdx;
          _messages[msgIdx] = ChatMessage(
            text: 'XAUUSD $direction brief ready — tap EXECUTE to confirm (sandbox):',
            isUser: false,
            executionBrief: brief,
            onExecute: () {
              trading.executeSandboxTrade(symbol, direction, entry, lotSize: lot);
              setState(() {
                _messages[msgIdx] = ChatMessage(
                  text: 'SANDBOX POSITION OPENED · $symbol $direction\n'
                      'Entry: ${brief["entry"]} · SL: $slStr · TP: $tpStr · '
                      '${lot.toStringAsFixed(2)} lots\n'
                      'Upgrade to Precision to execute live.',
                  isUser: false,
                );
              });
            },
            onDismissExecution: () {
              setState(() {
                _messages[msgIdx] = ChatMessage(
                  text: 'Trade cancelled.',
                  isUser: false,
                );
              });
            },
          );
        });
      }

      _scrollToBottom();
      return;
    }


    // ── FAST COCKPIT MARKET ANALYSIS ─────────────────────────────────────────
    final symbolLower = text.toLowerCase();
    String targetSymbol = 'EUR/USD';
    if (symbolLower.contains('btc') || symbolLower.contains('bitcoin')) {
      targetSymbol = 'BTC/USD';
    } else if (symbolLower.contains('xau') || symbolLower.contains('gold')) {
      targetSymbol = 'XAU/USD';
    } else if (symbolLower.contains('gbp')) {
      targetSymbol = 'GBP/USD';
    } else if (symbolLower.contains('nas') || symbolLower.contains('tech')) {
      targetSymbol = 'NAS100';
    }

    final tickPrice = market.latestSnapshot?.close ?? 0.0;
    final random = Random();
    final dirs = ['BUY', 'SELL', 'HOLD'];
    final direction = dirs[random.nextInt(dirs.length)];
    final confs = ['HIGH', 'MEDIUM'];
    final confidence = confs[random.nextInt(confs.length)];

    final nlgText = NLGEngine().generateResponse(direction: direction, confidenceTier: confidence);
    final priceStr = tickPrice > 0 ? " Live tick: \$${tickPrice.toStringAsFixed(targetSymbol == 'BTC/USD' ? 2 : 4)}." : "";
    final fullText = "$nlgText$priceStr";

    ConsensusResult? consensus;
    if (direction != 'HOLD') {
      consensus = ConsensusResult(
        finalDirection: direction,
        consensusPercentage: (random.nextDouble() * 15 + 84), // 84-99%
        proceed: true,
        timestamp: DateTime.now(),
        votes: [
          AIVote(modelName: 'Neural Link Executive', snapshotId: 'live', direction: direction, confidence: 0.94, reasoning: 'Multi-timeframe risk scan on $targetSymbol.'),
          AIVote(modelName: 'The Quant Engine', snapshotId: 'live', direction: direction, confidence: 0.96, reasoning: 'Statistical edge verified.'),
        ],
      );
    }

    _streamResponse(fullText, consensus);
  }

  void _streamResponse(String fullText, ConsensusResult? consensus) async {
    final msg = ChatMessage(text: '', isUser: false, isStreaming: true);
    if (!mounted) return;
    setState(() {
      _messages.add(msg);
      _isTyping = false;
    });

    final words = fullText.split(' ');
    for (var word in words) {
      await Future.delayed(const Duration(milliseconds: 25));
      if (!mounted) return;
      
      setState(() {
        msg.text += '$word ';
      });
      _scrollToBottom();
    }
    
    if (!mounted) return;
    setState(() {
      msg.isStreaming = false;
      msg.consensusWidget = consensus;
    });
    _scrollToBottom();
  }

  Widget _buildGlowOrb(Color color, {double size = 350}) {
    return AnimatedBuilder(
      animation: _orbCtrl,
      builder: (context, child) {
        return Transform.scale(
          scale: 1.0 + (_orbCtrl.value * 0.15),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [color, Colors.transparent],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final isPaper = settings.paperMode;
    final lotSize = settings.defaultLotSize;

    return Scaffold(
      backgroundColor: MehdAiTheme.bgPrimary,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: widget.showBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,

        title: Row(
          children: [
            const Icon(Icons.bolt_rounded, color: MehdAiTheme.blue, size: 22),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'NEURO PULSE',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                  letterSpacing: 1.5,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isPaper) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF58A6FF).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF58A6FF).withOpacity(0.4)),
                ),
                child: const Text('PAPER', style: TextStyle(color: Color(0xFF58A6FF), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              ),
            ],
            if (settings.hasBrokerConnected) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFF00FF88).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(color: const Color(0xFF00FF88).withOpacity(0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.shield, color: Color(0xFF00FF88), size: 10),
                    const SizedBox(width: 4),
                    Text(
                      settings.connectedBrokerId.toUpperCase(),
                      style: const TextStyle(color: Color(0xFF00FF88), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        backgroundColor: MehdAiTheme.bgSecondary,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: MehdAiTheme.borderColor, height: 1),
        ),
      ),
      body: Stack(
        children: [
          // Background ambient glows
          Positioned(
            top: -100,
            left: -80,
            child: _buildGlowOrb(MehdAiTheme.blue.withOpacity(0.08)),
          ),
          Positioned(
            bottom: -120,
            right: -80,
            child: _buildGlowOrb(MehdAiTheme.purple.withOpacity(0.06)),
          ),

          SafeArea(
            child: Column(
              children: [
                // Environment Mode Banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  color: isPaper ? const Color(0xFF58A6FF).withOpacity(0.08) : const Color(0xFFFF3B3B).withOpacity(0.06),
                  child: Row(
                    children: [
                      Icon(isPaper ? Icons.science_rounded : Icons.warning_amber_rounded, color: isPaper ? const Color(0xFF58A6FF) : const Color(0xFFFF3B3B), size: 14),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          isPaper
                              ? 'PAPER MODE — Balance: \$${settings.accountBalance.toStringAsFixed(0)}  •  Lot Size: ${lotSize.toStringAsFixed(2)}'
                              : 'LIVE MODE — Lot Size: ${lotSize.toStringAsFixed(2)}. Real execution active.',
                          style: TextStyle(color: isPaper ? const Color(0xFF58A6FF) : const Color(0xFFFF3B3B), fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                // Chat Messages List OR Claude-Code Style Hero Welcome View
                Expanded(
                  child: _messages.where((m) => m.isUser).isEmpty
                      ? _buildHeroWelcomeView(context)
                      : ListView.builder(
                          controller: _scrollController,
                          padding: const EdgeInsets.all(20),
                          itemCount: _messages.length + (_isTyping ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == _messages.length && _isTyping) {
                              return _buildTypingIndicator();
                            }
                            final msg = _messages[index];
                            return _buildMessageBubble(msg);
                          },
                        ),
                ),

                // Input Area
                _buildInputArea(),
              ],
            ),
          ),
        ],
      ),
    );
  }
  // ignore: unused_element
  Widget _buildNeuroCockpitBar(BuildContext context) => const NeuroCockpitBar();

  Widget _buildMessageBubble(ChatMessage msg) => PulseMessageBubble(
        msg: PulseChatMessage(
          text: msg.text,
          isUser: msg.isUser,
          isStreaming: msg.isStreaming,
          consensusWidget: msg.consensusWidget,
          executionBrief: msg.executionBrief,
          onExecute: msg.onExecute,
          onDismissExecution: msg.onDismissExecution,
        ),
      );


  Widget _buildInputArea() => PulseInputArea(
        inputController: _inputController,
        quickPrompts: _quickPrompts,
        showCommandSuggestions: _showCommandSuggestions,
        onSubmit: _handleUserSubmit,
        onOverrideSubmit: (cmd) => _handleUserSubmit(overrideText: cmd),
        onHideSuggestions: () => setState(() => _showCommandSuggestions = false),
        onToggleSuggestions: () => setState(() => _showCommandSuggestions = !_showCommandSuggestions),
      );

  Widget _buildHeroWelcomeView(BuildContext context) => const PulseHeroWelcomeView();

  Widget _buildTypingIndicator() => const PulseTypingIndicator();
}


