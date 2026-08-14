import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/models/consensus_result.dart';
import 'package:mehd_ai_flutter/core/den_identity.dart';
import 'package:mehd_ai_flutter/core/performance_tracker.dart';
import 'package:mehd_ai_flutter/core/cache_service.dart';
import 'package:mehd_ai_flutter/core/api_service.dart';
import 'package:mehd_ai_flutter/services/settings_service.dart';
import 'dart:math' as math;
import 'package:mehd_ai_flutter/widgets/war_room_painters.dart';
import 'dart:async';

class WarRoomScreen extends StatefulWidget {
  final ConsensusResult? consensus;
  final bool isAnalyzing;
  final bool showBack;
  
  const WarRoomScreen({
    super.key,
    this.consensus,
    required this.isAnalyzing,
    this.showBack = false,
  });

  @override
  State<WarRoomScreen> createState() => _WarRoomScreenState();
}


class _WarRoomScreenState extends State<WarRoomScreen> with TickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late AnimationController _radarCtrl;
  
  String _liveText = "";
  Timer? _typewriterTimer;
  final PerformanceTracker _perf = PerformanceTracker();
  final CacheService _cache = CacheService();
  final ApiService _apiService = ApiService();
  
  Map<String, dynamic>? _healthData;
  Timer? _healthTimer;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    _radarCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
    _startTypewriter();
    _fetchHealth();
    _healthTimer = Timer.periodic(const Duration(seconds: 5), (_) => _fetchHealth());
  }

  Future<void> _fetchHealth() async {
    try {
      final data = await _apiService.getSystemHealth();
      if (mounted && data.isNotEmpty) {
        setState(() => _healthData = data);
      }
    } catch (e) {
      // Non-fatal — timer will retry in 5 seconds
      debugPrint('WarRoom: Health fetch error (non-fatal): $e');
    }
  }

  @override
  void didUpdateWidget(WarRoomScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isAnalyzing != oldWidget.isAnalyzing) {
      if (widget.isAnalyzing) {
         setState(() => _liveText = "");
         _startTypewriter();
      }
    }
  }

  void _startTypewriter() {
    _typewriterTimer?.cancel();
    const fullText = "THE DON HAS INITIATED ANALYSIS...\n\n"
        "THE RESEARCH: Gathering street intelligence and sentiment.\n"
        "THE STRATEGY: Formulating imperial strategy and risk protocols.\n"
        "OLYMPUS: Calculating quantitative probabilities.\n\n"
        "11-AGENT SWARM ACTIVE — 24/5 LIVE MONITORING...";
    
    int charIndex = 0;
    _typewriterTimer = Timer.periodic(const Duration(milliseconds: 50), (timer) {
      if (charIndex < fullText.length) {
        if (mounted) setState(() => _liveText = fullText.substring(0, charIndex + 1));
        charIndex++;
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    _radarCtrl.dispose();
    _typewriterTimer?.cancel();
    _healthTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final activeBroker = settings.hasBrokerConnected ? settings.connectedBrokerId.toUpperCase() : null;

    return Scaffold(
      backgroundColor: Colors.black, // Dark cinematic
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: widget.showBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: MehdAiTheme.red, size: 18),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,

        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.shield, color: MehdAiTheme.red),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                'INSTITUTIONAL WAR ROOM',
                style: MehdAiTheme.headingStyle.copyWith(color: MehdAiTheme.red, letterSpacing: 4),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: MehdAiTheme.red),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(25),
          child: Container(
            color: const Color(0xFF0D1117),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: Text(
                    '${_perf.warRoomSummary} | Cache: ${_cache.hitRate.toStringAsFixed(0)}% hit',
                    style: MehdAiTheme.terminalStyle.copyWith(color: MehdAiTheme.green, fontSize: 11),
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (activeBroker != null) ...[
                  const SizedBox(width: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00FF88).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: const Color(0xFF00FF88).withOpacity(0.4)),
                    ),
                    child: Text(
                      'BROKER: $activeBroker',
                      style: const TextStyle(color: Color(0xFF00FF88), fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 1200;
          if (isMobile) {
            return SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(height: 350, child: _buildRadar()),
                  Divider(height: 1, color: MehdAiTheme.red.withOpacity(0.2)),
                  SizedBox(height: 400, child: _buildNeuralMap()),
                  Divider(height: 1, color: MehdAiTheme.red.withOpacity(0.2)),
                  SizedBox(height: 400, child: _buildLiveDecrypt()),
                ],
              ),
            );
          }
          return Row(
            children: [
              // LEFT: Neural Map
              Expanded(flex: 3, child: _buildNeuralMap()),
              VerticalDivider(width: 1, color: MehdAiTheme.red.withOpacity(0.2)),
              
              // CENTER: 3D Radar/Cylinder
              Expanded(flex: 4, child: _buildRadar()),
              VerticalDivider(width: 1, color: MehdAiTheme.red.withOpacity(0.2)),
              
              // RIGHT: Live Decrypt Stream
              Expanded(flex: 3, child: _buildLiveDecrypt()),
            ],
          );
        },
      ),
    );
  }

  Widget _buildNeuralMap() {
    final isBuy = widget.consensus?.finalDirection == 'BUY';
    final isSell = widget.consensus?.finalDirection == 'SELL';
    final baseColor = isBuy ? const Color(0xFF00FF88) : (isSell ? const Color(0xFFFF3B3B) : MehdAiTheme.red);

    return Container(
      decoration: BoxDecoration(
        gradient: RadialGradient(
          colors: [baseColor.withOpacity(0.1), Colors.black],
          radius: 0.8,
        )
      ),
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size(double.infinity, double.infinity),
            painter: NeuralConnectionPainter(pulse: _pulseCtrl, activeNodes: _getActiveAgentIds(), baseColor: baseColor),
          ),
          // 9 Outer Agent Nodes + THE DON (center) + SENTINEL (eye) = 11 total
          // OLYMPUS
          _buildNode(0, -110, "vanguard", baseColor),
          
          // THE STRATEGY
          _buildNode(-80, -50, "guardian", baseColor), 
          _buildNode(80, -50, "titan", baseColor),
          _buildNode(-120, 50, "atlas", baseColor), 
          _buildNode(120, 50, "forge", baseColor), 
          
          // THE RESEARCH
          _buildNode(0, -20, "phantom", baseColor), 
          _buildNode(-80, 150, "oracle", baseColor), 
          _buildNode(0, 130, "caesar", baseColor), 
          _buildNode(80, 150, "sage", baseColor),
          
          // THE DON (Center - white, large)
          Transform.translate(
            offset: const Offset(0, 45),
            child: AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, __) => Container(
                width: 70, height: 70,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: Colors.white, width: 2),
                  boxShadow: [BoxShadow(color: Colors.white.withOpacity(_pulseCtrl.value), blurRadius: 40)],
                ),
                child: const Icon(Icons.account_balance, color: Colors.black, size: 35),
              ),
            ),
          ),
          // THE DON LABEL
          Transform.translate(
            offset: const Offset(0, 95),
            child: Text('THE DON', style: MehdAiTheme.labelStyle.copyWith(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
          
          // SENTINEL (Eye shape around center)
          Transform.translate(
            offset: const Offset(0, 45),
            child: AnimatedBuilder(
              animation: _pulseCtrl,
              builder: (_, __) => Container(
                width: 140, height: 100, // Wide eye shape
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.all(Radius.elliptical(140, 100)),
                  border: Border.all(color: baseColor.withOpacity(0.3 + (_pulseCtrl.value * 0.4)), width: 3),
                  boxShadow: [BoxShadow(color: baseColor.withOpacity(0.1), blurRadius: 20)],
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: const Offset(0, -15),
            child: Text('SENTINEL WATCHING', style: MehdAiTheme.terminalStyle.copyWith(color: baseColor, fontSize: 10, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Set<String> _getActiveAgentIds() {
    if (widget.consensus == null) return {};
    return widget.consensus!.votes.map((v) => v.modelName.toLowerCase()).toSet();
  }

  Widget _buildNode(double dx, double dy, String rawModelName, Color baseColor) {
    final settings = context.read<SettingsService>();
    final convictionThreshold = settings.convictionThreshold; // e.g. 75.0
    final showNames = settings.showAgentNames;

    final identity = DenIdentity.getIdentity(rawModelName);
    final hasVoted = widget.consensus?.votes.any((v) => v.modelName.toLowerCase() == rawModelName.toLowerCase()) ?? false;

    // Check if this agent's vote meets the conviction threshold
    final agentVote = widget.consensus?.votes.firstWhere(
      (v) => v.modelName.toLowerCase() == rawModelName.toLowerCase(),
      orElse: () => AIVote(modelName: rawModelName, snapshotId: '', direction: 'HOLD', confidence: 0.0, reasoning: ''),
    );
    final agentConfidence = (agentVote?.confidence ?? 0).toDouble();
    final meetsThreshold = !hasVoted || agentConfidence >= convictionThreshold;

    // Dim agents that voted but didn't meet the threshold
    final color = hasVoted
        ? (meetsThreshold ? baseColor : baseColor.withOpacity(0.25))
        : baseColor.withOpacity(0.3);
    final size = hasVoted ? 16.0 : 12.0;

    return Transform.translate(
      offset: Offset(dx, dy),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (context, child) {
              final scale = hasVoted ? 1.0 + (_pulseCtrl.value * 0.3) : 1.0;
              return Transform.scale(
                scale: scale,
                child: Container(
                  width: size, height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: color,
                    boxShadow: hasVoted && meetsThreshold ? [BoxShadow(color: color.withOpacity(0.8), blurRadius: 15 * scale, spreadRadius: 2 * scale)] : [],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          // Only show agent names if the setting is ON
          if (showNames)
            Text(
              identity.displayName,
              style: MehdAiTheme.labelStyle.copyWith(
                color: color,
                fontSize: 10,
                fontWeight: hasVoted ? FontWeight.bold : FontWeight.normal,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRadar() {
    final isBuy = widget.consensus?.finalDirection == 'BUY';
    final isSell = widget.consensus?.finalDirection == 'SELL';
    final baseColor = isBuy ? const Color(0xFF00FF88) : (isSell ? const Color(0xFFFF3B3B) : MehdAiTheme.red);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // HUD Panel frame
        AnimatedBuilder(
          animation: _pulseCtrl,
          builder: (_, __) => Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: baseColor.withOpacity(0.25 + _pulseCtrl.value * 0.2),
                width: 1.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: baseColor.withOpacity(0.08 + _pulseCtrl.value * 0.06),
                  blurRadius: 40,
                  spreadRadius: 4,
                ),
              ],
            ),
            // Radar content: all drawn on canvas, no Text widgets
            child: AnimatedBuilder(
              animation: _radarCtrl,
              builder: (_, __) => CustomPaint(
                size: const Size(300, 300),
                painter: RadarPainter(
                  angle: _radarCtrl.value * 2 * math.pi,
                  pulse: _pulseCtrl.value,
                  consensus: widget.consensus,
                  baseColor: baseColor,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        if (widget.consensus != null) ...[
          Text('CONSENSUS: ${widget.consensus!.consensusPercentage}%', style: MehdAiTheme.headingStyle.copyWith(fontSize: 24, color: baseColor)),
          Builder(builder: (ctx) {
            final threshold = ctx.watch<SettingsService>().convictionThreshold;
            final pct = widget.consensus!.consensusPercentage.toDouble();
            final passes = pct >= threshold;
            return Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(passes ? Icons.check_circle_rounded : Icons.cancel_rounded,
                    color: passes ? const Color(0xFF00FF88) : const Color(0xFFFF3B3B), size: 14),
                  const SizedBox(width: 4),
                  Text(
                    passes ? 'ABOVE YOUR ${threshold.toInt()}% THRESHOLD' : 'BELOW YOUR ${threshold.toInt()}% THRESHOLD',
                    style: MehdAiTheme.labelStyle.copyWith(
                      color: passes ? const Color(0xFF00FF88) : const Color(0xFFFF3B3B),
                      fontSize: 10, fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
            );
          }),
        ] else
           Text('SIGNAL PIPELINE ACTIVE — CONNECTING...', style: MehdAiTheme.headingStyle.copyWith(color: MehdAiTheme.textSecondary)),
      ],
    );
  }

  Widget _buildLiveDecrypt() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('LIVE DECRYPT STREAM', style: MehdAiTheme.terminalStyle.copyWith(color: MehdAiTheme.red, fontWeight: FontWeight.bold)),
          const Divider(color: MehdAiTheme.red),
          const SizedBox(height: 16),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _liveText,
                    style: MehdAiTheme.terminalStyle.copyWith(height: 1.5, color: MehdAiTheme.textPrimary),
                  ),
                  if (_healthData != null) ...[
                    const SizedBox(height: 40),
                    const Divider(color: MehdAiTheme.red),
                    const SizedBox(height: 16),
                    Text('WAR ROOM TELEMETRY', style: MehdAiTheme.terminalStyle.copyWith(color: MehdAiTheme.red, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 16),
                    _buildMetricRow('Consensus Avg Time', _healthData!['avg_consensus_time'] ?? 'N/A'),
                    _buildMetricRow('Market Feed Latency', _healthData!['price_feed_latency'] ?? 'N/A'),
                    _buildMetricRow('Agent Cache Hit Rate', _healthData!['cache_hit_rate'] ?? 'N/A'),
                    _buildMetricRow('System Error Rate', _healthData!['error_rate'] ?? 'N/A'),
                    _buildMetricRow('API Budget', _healthData!['api_budget_remaining'] ?? 'N/A'),
                    const SizedBox(height: 16),
                    Text('AGENT RESPONSE RATES', style: MehdAiTheme.terminalStyle.copyWith(color: MehdAiTheme.gold, fontSize: 10)),
                    const SizedBox(height: 8),
                    if (_healthData!['model_response_times'] != null)
                      ...(_healthData!['model_response_times'] as Map<String, dynamic>).entries.map(
                        (e) {
                          final showNames = context.read<SettingsService>().showAgentNames;
                          final displayName = showNames ? DenIdentity.getIdentity(e.key).displayName : e.key.toUpperCase();
                          return _buildMetricRow(" > $displayName", e.value?.toString() ?? 'N/A');
                        }
                      ),

                  ]
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _buildMetricRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: MehdAiTheme.terminalStyle.copyWith(color: MehdAiTheme.textSecondary, fontSize: 12)),
          Text(value, style: MehdAiTheme.terminalStyle.copyWith(color: MehdAiTheme.green, fontSize: 12, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}

