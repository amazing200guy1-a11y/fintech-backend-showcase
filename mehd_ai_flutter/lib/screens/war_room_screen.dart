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
import 'dart:async';

class WarRoomScreen extends StatefulWidget {
  final ConsensusResult? consensus;
  final bool isAnalyzing;
  
  const WarRoomScreen({super.key, this.consensus, required this.isAnalyzing});

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

class NeuralConnectionPainter extends CustomPainter {
  final Animation<double> pulse;
  final Set<String> activeNodes;
  final Color baseColor;

  NeuralConnectionPainter({required this.pulse, required this.activeNodes, required this.baseColor}) : super(repaint: pulse);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = baseColor.withOpacity(0.2 + (pulse.value * 0.3))
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final center = Offset(size.width / 2, size.height / 2);
    final nodes = [
      Offset(center.dx, center.dy - 110),
      Offset(center.dx - 80, center.dy - 50),
      Offset(center.dx + 80, center.dy - 50),
      Offset(center.dx - 120, center.dy + 50),
      Offset(center.dx + 120, center.dy + 50),
      Offset(center.dx, center.dy - 20),
      Offset(center.dx - 80, center.dy + 150),
      Offset(center.dx, center.dy + 130),
      Offset(center.dx + 80, center.dy + 150),
    ];

    // Connect nodes to The Don (center offset 0, 45)
    final theDon = Offset(center.dx, center.dy + 45);
    
    for (var node in nodes) {
      canvas.drawLine(theDon, node, paint);
    }
  }

  @override
  bool shouldRepaint(NeuralConnectionPainter oldDelegate) => true;
}

class RadarPainter extends CustomPainter {
  final double angle;
  final double pulse;
  final ConsensusResult? consensus;
  final Color baseColor;

  RadarPainter({required this.angle, required this.pulse, this.consensus, required this.baseColor});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // ── Background fill ──
    canvas.drawCircle(
      center, radius,
      Paint()
        ..shader = RadialGradient(
          colors: [
            Colors.black.withOpacity(0.5),
            baseColor.withOpacity(0.04),
            Colors.black.withOpacity(0.85),
          ],
          stops: const [0.0, 0.5, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: radius)),
    );

    // ── Subtle wireframe terrain grid ──
    final gridPaint = Paint()
      ..color = baseColor.withOpacity(0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (double i = 0; i < size.width; i += 22) {
      final path = Path()..moveTo(i, 0);
      for (double j = 0; j < size.height; j += 22) {
        path.quadraticBezierTo(i + 7 * math.sin(j / 40), j + 11, i, j + 22);
      }
      canvas.drawPath(path, gridPaint);
    }

    // ── Concentric rings ──
    final ringPaint = Paint()
      ..color = baseColor.withOpacity(0.28)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final brightRingPaint = Paint()
      ..color = baseColor.withOpacity(0.65 + pulse * 0.2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2;

    canvas.drawCircle(center, radius * 0.95, brightRingPaint);
    canvas.drawCircle(center, radius * 0.70, ringPaint);
    canvas.drawCircle(center, radius * 0.46, ringPaint);
    canvas.drawCircle(center, radius * 0.23, ringPaint);

    // ── Crosshairs ──
    canvas.drawLine(Offset(center.dx, radius * 0.04), Offset(center.dx, size.height - radius * 0.04), ringPaint);
    canvas.drawLine(Offset(radius * 0.04, center.dy), Offset(size.width - radius * 0.04, center.dy), ringPaint);

    // ── Ring distance labels ──
    _label(canvas, '1KM', Offset(center.dx + radius * 0.23 + 3, center.dy + 3), baseColor, 7.5);
    _label(canvas, '2KM', Offset(center.dx + radius * 0.46 + 3, center.dy + 3), baseColor, 7.5);
    _label(canvas, '3KM', Offset(center.dx + radius * 0.70 + 3, center.dy + 3), baseColor, 7.5);
    _label(canvas, '4KM', Offset(center.dx + radius * 0.95 + 2, center.dy + 3), baseColor, 7.5);

    // ── Degree labels ──
    _label(canvas, '0°',   Offset(center.dx - 6,  3),                       baseColor, 7.5);
    _label(canvas, '90°',  Offset(size.width - 24, center.dy - 8),           baseColor, 7.5);
    _label(canvas, '180°', Offset(center.dx - 9,   size.height - 14),        baseColor, 7.5);
    _label(canvas, '270°', Offset(3,               center.dy - 8),           baseColor, 7.5);

    // ── Header / footer labels (all on canvas) ──
    _label(canvas, 'ACTIVE SCAN | 3D HUD',
        Offset(center.dx - 62, 5), Colors.white70, 8.5);
    _label(canvas, 'SYSTEM: READY | SENSORS: ONLINE',
        Offset(8, size.height - 14), baseColor.withOpacity(0.7), 7);
    _label(canvas, 'HDG: 047° | ALT: 210M',
        Offset(size.width - 108, size.height - 14), baseColor.withOpacity(0.7), 7);

    // ── Degree tick marks ──
    final tickPaint = Paint()
      ..color = baseColor.withOpacity(0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (int i = 0; i < 360; i += 10) {
      final tickAngle = i * math.pi / 180;
      final isMajor = i % 30 == 0;
      final inner = isMajor ? radius * 0.91 : radius * 0.94;
      canvas.drawLine(
        Offset(center.dx + math.cos(tickAngle) * inner, center.dy + math.sin(tickAngle) * inner),
        Offset(center.dx + math.cos(tickAngle) * (radius * 0.96), center.dy + math.sin(tickAngle) * (radius * 0.96)),
        isMajor ? brightRingPaint : tickPaint,
      );
    }

    // ── Narrow sweep wedge ──
    canvas.drawCircle(
      center, radius * 0.95,
      Paint()
        ..shader = SweepGradient(
          center: Alignment.center,
          startAngle: 0.0,
          endAngle: math.pi / 5,
          colors: [
            baseColor.withOpacity(0.0),
            baseColor.withOpacity(0.18),
            baseColor.withOpacity(0.85),
          ],
          stops: const [0.0, 0.6, 1.0],
          transform: GradientRotation(angle - (math.pi / 5)),
        ).createShader(Rect.fromCircle(center: center, radius: radius))
        ..style = PaintingStyle.fill,
    );

    // ── Leading edge bright line ──
    canvas.drawLine(
      center,
      Offset(center.dx + math.cos(angle) * radius * 0.95, center.dy + math.sin(angle) * radius * 0.95),
      Paint()
        ..color = baseColor
        ..strokeWidth = 4.0
        ..strokeCap = StrokeCap.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.solid, 3),
    );

    // ── Metallic hub (drawn entirely on canvas) ──
    final hubR = radius * 0.13;
    // Outer metallic ring
    canvas.drawCircle(center, hubR,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.4, -0.5),
          colors: const [Color(0xFFCCCCCC), Color(0xFF333333)],
        ).createShader(Rect.fromCircle(center: center, radius: hubR))
        ..style = PaintingStyle.fill,
    );
    canvas.drawCircle(center, hubR, Paint()..color = Colors.black..style = PaintingStyle.stroke..strokeWidth = 2);
    // Inner gloss
    canvas.drawCircle(center, hubR * 0.75,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: const [Color(0xFFEEEEEE), Color(0xFF555555)],
        ).createShader(Rect.fromCircle(center: center, radius: hubR * 0.75))
        ..style = PaintingStyle.fill,
    );
    // Glow on hub
    canvas.drawCircle(center, hubR * 0.6,
      Paint()
        ..color = baseColor.withOpacity(0.15 + pulse * 0.2)
        ..style = PaintingStyle.fill
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
    );
    // Hub label
    _label(canvas, 'HUB', Offset(center.dx - 9, center.dy - 5), Colors.black87, 7);

    // ── Agent / target nodes ──
    final int activeCount = consensus?.votes.length ?? 0;
    final bracketPaint = Paint()
      ..color = baseColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (int i = 0; i < 11; i++) {
      final nodeAngle = (i * (math.pi * 2) / 11) - (math.pi / 2);
      final dist = i < activeCount ? radius * 0.62 : radius * 0.38;
      final alpha = i < activeCount ? 1.0 : 0.22;
      final nc = Offset(center.dx + math.cos(nodeAngle) * dist, center.dy + math.sin(nodeAngle) * dist);

      // Glow orb
      canvas.drawCircle(nc, 7.0,
        Paint()
          ..color = baseColor.withOpacity(alpha * 0.45)
          ..style = PaintingStyle.fill
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      // Solid core
      canvas.drawCircle(nc, 3.0,
        Paint()..color = Colors.white.withOpacity(alpha)..style = PaintingStyle.fill,
      );

      // Targeting brackets on every 3rd active node
      if (i < activeCount && i % 3 == 0) {
        const s = 11.0;
        canvas.drawLine(Offset(nc.dx - s, nc.dy - s), Offset(nc.dx - s + 5, nc.dy - s), bracketPaint);
        canvas.drawLine(Offset(nc.dx - s, nc.dy - s), Offset(nc.dx - s, nc.dy - s + 5), bracketPaint);
        canvas.drawLine(Offset(nc.dx + s, nc.dy + s), Offset(nc.dx + s - 5, nc.dy + s), bracketPaint);
        canvas.drawLine(Offset(nc.dx + s, nc.dy + s), Offset(nc.dx + s, nc.dy + s - 5), bracketPaint);
        _label(canvas, 'TGT-${String.fromCharCode(65 + i)} [${(dist / 45).toStringAsFixed(1)}KM]',
            Offset(nc.dx + s + 3, nc.dy - s), baseColor.withOpacity(0.85), 7);
      }
    }

    // ── Outer ring clip (hide anything drawn outside) ──
    final clipPath = Path()..addOval(Rect.fromCircle(center: center, radius: radius * 0.975));
    canvas.clipPath(clipPath);
  }

  void _label(Canvas canvas, String text, Offset offset, Color color, double fontSize) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(color: color, fontSize: fontSize, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(RadarPainter oldDelegate) => true;
}
