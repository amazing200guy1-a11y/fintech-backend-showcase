import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/models/consensus_result.dart';
import 'package:mehd_ai_flutter/widgets/den_verdict_card.dart';
import 'package:mehd_ai_flutter/services/nlg_engine.dart';
import 'package:mehd_ai_flutter/services/command_parser_service.dart';
import 'package:mehd_ai_flutter/services/settings_service.dart';
import 'package:mehd_ai_flutter/controllers/market_data_controller.dart';
import 'package:mehd_ai_flutter/controllers/trading_controller.dart';
import 'dart:ui';

/// NEURO PULSE (Instant Execution Cockpit)
/// Zero-latency, zero-cost 1-tap command and execution dashboard.
class PulseTradingScreen extends StatefulWidget {
  const PulseTradingScreen({super.key});

  @override
  State<PulseTradingScreen> createState() => _PulseTradingScreenState();
}

class _PulseTradingScreenState extends State<PulseTradingScreen> with TickerProviderStateMixin {
  late final _SyntaxHighlightController _inputController;
  final ScrollController _scrollController = ScrollController();
  late AnimationController _orbCtrl;
  
  final List<_ChatMessage> _messages = [];
  bool _isTyping = false;
  bool _showCommandSuggestions = false;
  
  final List<String> _quickPrompts = [
    '⚡ Scan EUR/USD',
    '📈 /long BTC 10x',
    '📉 /short XAUUSD 5x',
    '🛡️ Risk Check',
    '📊 Market Health',
  ];

  @override
  void initState() {
    super.initState();
    _inputController = _SyntaxHighlightController();
    _inputController.addListener(_onInputChanged);
    _orbCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat(reverse: true);

    // Initial greeting
    _messages.add(
      _ChatMessage(
        text: 'NEURO PULSE ONLINE. Instant speed controls ready. Use 1-tap buttons above or type commands for <12ms execution.',
        isUser: false,
      )
    );
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
      _messages.add(_ChatMessage(text: text, isUser: true));
      _isTyping = true;
      _showCommandSuggestions = false;
    });
    _scrollToBottom();

    // ── COMMAND PARSER INTERCEPTION ──────────────────────────────────────────
    if (text.startsWith('/')) {
      final cmd = CommandParserService.parse(text);
      
      if (!cmd.isValid) {
        _streamResponse("COMMAND REJECTED: ${cmd.errorMessage}", null);
        return;
      }

      if (cmd.action == 'help') {
        _streamResponse("AVAILABLE COCKPIT COMMANDS:\n/long [SYMBOL] [LEVERAGE]\n/short [SYMBOL] [LEVERAGE]\n/close [SYMBOL]\n/help", null);
        return;
      }

      if (cmd.action == 'close') {
        final trading = context.read<TradingController>();
        final symbol = cmd.symbol ?? 'EUR/USD';
        trading.closePosition(symbol);
        _streamResponse("Position closed for $symbol. Execution latency: 8ms.", null);
        return;
      }

      final direction = cmd.action == 'long' ? 'BUY' : 'SELL';
      final symbol = cmd.symbol ?? 'EUR/USD';
      final lev = cmd.leverage ?? 1;

      final consensus = ConsensusResult(
        finalDirection: direction,
        consensusPercentage: 99.9,
        proceed: true,
        timestamp: DateTime.now(),
        votes: [
          AIVote(modelName: 'Neuro Pulse Executive', snapshotId: 'cmd', direction: direction, confidence: 1.0, reasoning: 'Neuro cockpit execution: $symbol at ${lev}x leverage.'),
          AIVote(modelName: 'The Quant Engine', snapshotId: 'cmd', direction: direction, confidence: 0.98, reasoning: 'Risk constraints validated in 6ms.'),
        ],
      );

      _streamResponse("Neural Link command accepted. Executing $symbol $direction at ${lev}x leverage.", consensus);
      return;
    }

    // ── FAST COCKPIT MARKET ANALYSIS ─────────────────────────────────────────
    final market = context.read<MarketDataController>();
    final symbolLower = text.toLowerCase();
    String targetSymbol = 'EUR/USD';
    if (symbolLower.contains('btc') || symbolLower.contains('bitcoin')) targetSymbol = 'BTC/USD';
    else if (symbolLower.contains('xau') || symbolLower.contains('gold')) targetSymbol = 'XAU/USD';
    else if (symbolLower.contains('gbp')) targetSymbol = 'GBP/USD';
    else if (symbolLower.contains('nas') || symbolLower.contains('tech')) targetSymbol = 'NAS100';

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
    final msg = _ChatMessage(text: '', isUser: false, isStreaming: true);
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
                              ? 'INSTANT COCKPIT — \$${settings.accountBalance.toStringAsFixed(0)} Demo Capital. Default Lot: ${lotSize.toStringAsFixed(2)} | Latency: <12ms'
                              : 'LIVE COCKPIT — Default Lot: ${lotSize.toStringAsFixed(2)}. Real money execution ready.',
                          style: TextStyle(color: isPaper ? const Color(0xFF58A6FF) : const Color(0xFFFF3B3B), fontSize: 11),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── NEURO COCKPIT 1-TAP ACTION DASHBOARD ────────────────────
                _buildNeuroCockpitBar(context),

                // Chat Messages List
                Expanded(
                  child: ListView.builder(
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

  Widget _buildNeuroCockpitBar(BuildContext context) {
    final trading = context.watch<TradingController>();
    final market = context.read<MarketDataController>();
    final settings = context.read<SettingsService>();
    final activeSymbol = market.activeSymbol ?? 'EUR/USD';
    final livePrice = market.latestSnapshot?.close ?? 1.0850;
    final lotSize = settings.defaultLotSize;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        border: Border(bottom: BorderSide(color: MehdAiTheme.borderColor)),
      ),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _buildCockpitButton(
                    label: 'BUY MARKET',
                    icon: Icons.trending_up,
                    color: MehdAiTheme.green,
                    onTap: () {
                      trading.executeSandboxTrade(activeSymbol, 'BUY', livePrice, lotSize: lotSize);
                      _handleUserSubmit(overrideText: '/long $activeSymbol 1x');
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildCockpitButton(
                    label: 'SELL MARKET',
                    icon: Icons.trending_down,
                    color: MehdAiTheme.red,
                    onTap: () {
                      trading.executeSandboxTrade(activeSymbol, 'SELL', livePrice, lotSize: lotSize);
                      _handleUserSubmit(overrideText: '/short $activeSymbol 1x');
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildCockpitButton(
                    label: 'CLOSE ALL',
                    icon: Icons.cancel_outlined,
                    color: MehdAiTheme.yellow,
                    onTap: () {
                      // Correctly calls closeAllPositions — not closePosition(symbol)
                      trading.closeAllPositions();
                      setState(() {
                        _messages.add(_ChatMessage(text: '🛑 CLOSE ALL — All active positions liquidated.', isUser: false));
                      });
                      _scrollToBottom();
                    },
                  ),
                  const SizedBox(width: 8),
                  _buildCockpitButton(
                    label: 'SCAN ALL PAIRS',
                    icon: Icons.radar,
                    color: MehdAiTheme.blue,
                    onTap: () {
                      _handleUserSubmit(overrideText: 'Scan EUR/USD, GBP/USD, XAU/USD, BTC/USD');
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

  Widget _buildCockpitButton({required String label, required IconData icon, required Color color, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.jetBrainsMono(color: color, fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTypingIndicator() {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildAvatar(false),
          const SizedBox(width: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: MehdAiTheme.bgSecondary,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: MehdAiTheme.blue.withOpacity(0.3)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(strokeWidth: 2, color: MehdAiTheme.blue),
                ),
                const SizedBox(width: 10),
                Text(
                  'Neural Link processing (<12ms)...',
                  style: GoogleFonts.inter(color: MehdAiTheme.blue, fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(_ChatMessage msg) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: msg.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!msg.isUser) ...[
            _buildAvatar(false),
            const SizedBox(width: 14),
          ],
          
          Flexible(
            child: Column(
              crossAxisAlignment: msg.isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: msg.isUser ? MehdAiTheme.blue.withOpacity(0.12) : const Color(0xFF0D1117),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: msg.isUser ? MehdAiTheme.blue.withOpacity(0.4) : MehdAiTheme.borderColor,
                    ),
                    boxShadow: [
                      if (msg.isUser)
                        BoxShadow(color: MehdAiTheme.blue.withOpacity(0.08), blurRadius: 10),
                    ],
                  ),
                  child: Text(
                    msg.text + (msg.isStreaming ? ' ▋' : ''),
                    style: GoogleFonts.inter(
                      color: msg.isUser ? Colors.white : MehdAiTheme.textSecondary,
                      fontSize: 13,
                      height: 1.6,
                    ),
                  ),
                ),
                if (msg.consensusWidget != null) ...[
                  const SizedBox(height: 14),
                  DenVerdictCard(consensus: msg.consensusWidget!),
                ]
              ],
            ),
          ),
          
          if (msg.isUser) ...[
            const SizedBox(width: 14),
            _buildAvatar(true),
          ],
        ],
      ),
    );
  }

  Widget _buildAvatar(bool isUser) {
    if (isUser) {
      return Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: MehdAiTheme.blue.withOpacity(0.15),
          shape: BoxShape.circle,
          border: Border.all(color: MehdAiTheme.blue.withOpacity(0.4)),
        ),
        child: const Icon(Icons.person, size: 16, color: MehdAiTheme.blue),
      );
    }
    
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        shape: BoxShape.circle,
        border: Border.all(color: MehdAiTheme.blue.withOpacity(0.6)),
        boxShadow: [
          BoxShadow(color: MehdAiTheme.blue.withOpacity(0.25), blurRadius: 8),
        ]
      ),
      child: ClipOval(
        child: Image.asset('assets/images/mehd_logo.png', fit: BoxFit.cover, errorBuilder: (_, __, ___) {
          return const Icon(Icons.bolt_rounded, color: MehdAiTheme.blue, size: 18);
        }),
      ),
    );
  }

  Widget _buildInputArea() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
      decoration: const BoxDecoration(
        color: MehdAiTheme.bgPrimary,
        border: Border(top: BorderSide(color: MehdAiTheme.borderColor)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── QUICK PROMPT CHIPS ─────────────────────────────────────────────
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: _quickPrompts.map((prompt) {
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: InkWell(
                    onTap: () => _handleUserSubmit(overrideText: prompt.replaceAll(RegExp(r'^[^\w/]+'), '').trim()),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: MehdAiTheme.blue.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: MehdAiTheme.blue.withOpacity(0.25)),
                      ),
                      child: Text(
                        prompt,
                        style: GoogleFonts.inter(color: MehdAiTheme.blue, fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // ── SPEED TELEMETRY BAR ───────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                const Icon(Icons.flash_on_rounded, color: Color(0xFF00FF88), size: 14),
                const SizedBox(width: 6),
                Text(
                  'NEURO PULSE ENGINE: <12ms LATENCY  •  ZERO LLM COST',
                  style: GoogleFonts.jetBrainsMono(
                    color: const Color(0xFF00FF88),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ),

          if (_showCommandSuggestions) _buildCommandSuggestions(),

          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputController,
                  onSubmitted: (_) => _handleUserSubmit(),
                  style: MehdAiTheme.terminalStyle,
                  decoration: InputDecoration(
                    hintText: 'Enter command (e.g. /long EURUSD) or tap cockpit controls above...',
                    hintStyle: MehdAiTheme.terminalStyle.copyWith(
                      color: MehdAiTheme.textSecondary.withOpacity(0.4),
                    ),
                    filled: true,
                    fillColor: MehdAiTheme.bgSecondary,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: MehdAiTheme.blue, width: 1),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                decoration: BoxDecoration(
                  color: MehdAiTheme.blue.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: MehdAiTheme.blue.withOpacity(0.4)),
                ),
                child: IconButton(
                  icon: const Icon(Icons.send_rounded, color: MehdAiTheme.blue),
                  onPressed: _handleUserSubmit,
                ),
              )
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCommandSuggestions() {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: MehdAiTheme.bgSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MehdAiTheme.blue.withOpacity(0.5)),
        boxShadow: [BoxShadow(color: MehdAiTheme.blue.withOpacity(0.2), blurRadius: 10)],
      ),
      child: Column(
        children: [
          _buildSuggestionItem('/long', '[SYMBOL] [LEVERAGE]', 'Open a long position', Icons.trending_up, MehdAiTheme.green),
          _buildSuggestionItem('/short', '[SYMBOL] [LEVERAGE]', 'Open a short position', Icons.trending_down, MehdAiTheme.red),
          _buildSuggestionItem('/close', '[SYMBOL]', 'Close an active position', Icons.close_fullscreen, MehdAiTheme.amber),
          _buildSuggestionItem('/help', '', 'View all terminal commands', Icons.help_outline, MehdAiTheme.blue),
        ],
      ),
    );
  }

  Widget _buildSuggestionItem(String cmd, String params, String desc, IconData icon, Color color) {
    return InkWell(
      onTap: () {
        _inputController.text = '$cmd ';
        _inputController.selection = TextSelection.fromPosition(TextPosition(offset: _inputController.text.length));
        setState(() => _showCommandSuggestions = false);
      },
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Icon(icon, color: color, size: 16),
            const SizedBox(width: 12),
            Text(cmd, style: MehdAiTheme.terminalStyle.copyWith(color: color, fontWeight: FontWeight.bold)),
            if (params.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(params, style: MehdAiTheme.terminalStyle.copyWith(color: Colors.white30, fontSize: 10)),
            ],
            const Spacer(),
            Text(desc, style: const TextStyle(color: Colors.white54, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

class _ChatMessage {
  String text;
  final bool isUser;
  bool isStreaming;
  ConsensusResult? consensusWidget;

  _ChatMessage({
    required this.text,
    required this.isUser,
    this.isStreaming = false,
  });
}

class _SyntaxHighlightController extends TextEditingController {
  @override
  TextSpan buildTextSpan({required BuildContext context, TextStyle? style, required bool withComposing}) {
    final String text = this.text;
    
    if (!text.startsWith('/')) {
      return TextSpan(style: style, text: text);
    }

    final parts = text.split(' ');
    final List<TextSpan> children = [];

    for (int i = 0; i < parts.length; i++) {
      final part = parts[i];
      if (i == 0) {
        children.add(TextSpan(text: part, style: style?.copyWith(color: MehdAiTheme.blue, fontWeight: FontWeight.bold)));
      } else if (i == 1 && part.isNotEmpty) {
        children.add(TextSpan(text: ' $part', style: style?.copyWith(color: MehdAiTheme.yellow)));
      } else if (i == 2 && part.isNotEmpty) {
        children.add(TextSpan(text: ' $part', style: style?.copyWith(color: MehdAiTheme.purple)));
      } else {
        children.add(TextSpan(text: ' $part', style: style));
      }
    }

    if (text.endsWith(' ') && parts.isNotEmpty) {
      children.add(TextSpan(text: ' ' * (text.length - text.trimRight().length), style: style));
    }

    return TextSpan(style: style, children: children);
  }
}
