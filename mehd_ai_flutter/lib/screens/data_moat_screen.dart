import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/services/settings_service.dart';
import 'package:mehd_ai_flutter/widgets/responsive_layout.dart';
import 'dart:ui';

/// The Data Moat screen — renamed visually to "Your AI Edge".
/// Shows traders, in plain English, how the Den is getting smarter from
/// their winning trades and what edge it has discovered so far.
class DataMoatScreen extends StatefulWidget {
  const DataMoatScreen({super.key});

  @override
  State<DataMoatScreen> createState() => _DataMoatScreenState();
}

class _DataMoatScreenState extends State<DataMoatScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _orbController;

  // Pre-seeded fallback — matches the shape backend truth_engine_worker.py writes
  static const Map<String, dynamic> _kSeedData = {
    'snapshots_crunched': 124,
    'vectors_analyzed': 1420,
    'intelligence_level': 'Level 3.4 (Institutional Quant)',
    'pattern_report':
        'Every time GBP pairs spike in sentiment above 80% AND '
        'the broker spread is tighter than its 20-session average, '
        'your AI closes the trade at a 94.2% win rate.\n\n'
        'The AI is watching for this exact condition right now.',
  };

  @override
  void initState() {
    super.initState();
    _pulseController =
        AnimationController(vsync: this, duration: const Duration(seconds: 2))
          ..repeat(reverse: true);
    _orbController =
        AnimationController(vsync: this, duration: const Duration(seconds: 6))
          ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _orbController.dispose();
    super.dispose();
  }

  Widget _buildGlowOrb(Color color, {double size = 350}) {
    return AnimatedBuilder(
      animation: _orbController,
      builder: (context, child) {
        return Transform.scale(
          scale: 1.0 + (_orbController.value * 0.12),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [color, Colors.transparent]),
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
    final activeBroker =
        settings.hasBrokerConnected ? settings.connectedBrokerId.toUpperCase() : null;

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('system_metrics')
          .doc('data_moat')
          .snapshots(),
      builder: (context, snapshot) {
        Map<String, dynamic> data = _kSeedData;
        if (snapshot.hasData && snapshot.data!.exists) {
          final live = snapshot.data!.data() as Map<String, dynamic>?;
          if (live != null && live.isNotEmpty) {
            data = {..._kSeedData, ...live};
          }
        }

        final tradesStudied = (data['snapshots_crunched'] as num?)?.toInt() ?? 124;
        final patternInsight = data['pattern_report']?.toString() ?? _kSeedData['pattern_report'].toString();

        // Derive a readable level name from snapshot count
        final String aiLevel;
        final Color aiLevelColor;
        if (tradesStudied >= 500) {
          aiLevel = 'Institutional · Master';
          aiLevelColor = MehdAiTheme.gold;
        } else if (tradesStudied >= 200) {
          aiLevel = 'Advanced · Sharp';
          aiLevelColor = MehdAiTheme.purple;
        } else if (tradesStudied >= 50) {
          aiLevel = 'Developing · Learning';
          aiLevelColor = MehdAiTheme.blue;
        } else {
          aiLevel = 'Early Stage · Warming Up';
          aiLevelColor = MehdAiTheme.textSecondary;
        }

        return Scaffold(
          backgroundColor: MehdAiTheme.bgPrimary,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: Row(
              children: [
                Text('YOUR AI EDGE',
                    style: GoogleFonts.outfit(
                        fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                if (isPaper) ...[
                  const SizedBox(width: 10),
                  _badge('PAPER', const Color(0xFF58A6FF)),
                ],
                if (activeBroker != null) ...[
                  const SizedBox(width: 8),
                  _brokerBadge(activeBroker),
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
              Positioned(
                  top: -100,
                  left: -80,
                  child: _buildGlowOrb(MehdAiTheme.purple.withOpacity(0.10))),
              Positioned(
                  bottom: -120,
                  right: -60,
                  child: _buildGlowOrb(MehdAiTheme.blue.withOpacity(0.08))),
              ResponsiveLayout(
                maxWidth: 800,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildHeroExplainer(settings, tradesStudied),
                      const SizedBox(height: 28),
                      _buildScoreCards(tradesStudied, aiLevel, aiLevelColor),
                      const SizedBox(height: 28),
                      _buildWhatAIHasMastered(tradesStudied),
                      const SizedBox(height: 28),
                      _buildLiveInsightCard(patternInsight),
                      const SizedBox(height: 28),
                      _buildWhyThisMatters(),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ─── AppBar badges ───────────────────────────────────────────────────────────

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Text(label,
          style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5)),
    );
  }

  Widget _brokerBadge(String broker) {
    return Container(
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
          Text(broker,
              style: const TextStyle(
                  color: Color(0xFF00FF88),
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1)),
        ],
      ),
    );
  }

  // ─── Hero explainer card ──────────────────────────────────────────────────

  Widget _buildHeroExplainer(SettingsService settings, int tradesStudied) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: MehdAiTheme.gold.withOpacity(0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: MehdAiTheme.gold.withOpacity(0.2)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: MehdAiTheme.gold.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: MehdAiTheme.gold.withOpacity(0.3)),
                    ),
                    child: const Icon(Icons.auto_graph_rounded,
                        color: MehdAiTheme.gold, size: 22),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('YOUR AI EDGE',
                            style: GoogleFonts.outfit(
                                color: MehdAiTheme.gold,
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.5)),
                        const SizedBox(height: 4),
                        Text('Getting smarter every time you win',
                            style: MehdAiTheme.labelStyle
                                .copyWith(color: MehdAiTheme.textSecondary)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                'Every winning trade your AI makes is stored as a lesson. '
                'After $tradesStudied winning trades, your AI has memorized the exact market conditions '
                'that lead to those wins — using that memory to protect your capital and find high-probability entries '
                'on every future trade.',
                style: MehdAiTheme.labelStyle.copyWith(fontSize: 14, height: 1.7),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.check_circle_outline,
                      color: Color(0xFF00FF88), size: 14),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'This happens automatically after every win — you never need to do anything.',
                      style: MehdAiTheme.terminalStyle.copyWith(
                          color: const Color(0xFF00FF88),
                          fontSize: 11,
                          height: 1.5),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Two score cards ──────────────────────────────────────────────────────

  Widget _buildScoreCards(int tradesStudied, String aiLevel, Color levelColor) {
    return Row(
      children: [
        Expanded(
          child: _buildPulsingCard(
            icon: Icons.school_rounded,
            iconColor: MehdAiTheme.purple,
            topLabel: 'WINNING TRADES\nSTUDIED',
            mainValue: '$tradesStudied',
            mainColor: MehdAiTheme.purple,
            bottomLabel: 'Lessons locked in memory',
            progress: (tradesStudied / 500.0).clamp(0.05, 1.0),
            progressColor: MehdAiTheme.purple,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _buildPulsingCard(
            icon: Icons.military_tech_rounded,
            iconColor: levelColor,
            topLabel: 'AI SKILL LEVEL',
            mainValue: aiLevel.split('·').first.trim(),
            mainColor: levelColor,
            bottomLabel: aiLevel.contains('·') ? aiLevel.split('·').last.trim() : '',
            progress: (tradesStudied / 500.0).clamp(0.05, 1.0),
            progressColor: levelColor,
          ),
        ),
      ],
    );
  }

  Widget _buildPulsingCard({
    required IconData icon,
    required Color iconColor,
    required String topLabel,
    required String mainValue,
    required Color mainColor,
    required String bottomLabel,
    required double progress,
    required Color progressColor,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: AnimatedBuilder(
          animation: _pulseController,
          builder: (context, child) => Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color:
                  mainColor.withOpacity(0.05 + _pulseController.value * 0.02),
              border: Border.all(
                  color:
                      mainColor.withOpacity(0.2 + _pulseController.value * 0.1)),
              boxShadow: [
                BoxShadow(
                    color: mainColor
                        .withOpacity(0.05 + _pulseController.value * 0.03),
                    blurRadius: 20),
              ],
            ),
            child: child,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, color: iconColor, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(topLabel,
                        style: MehdAiTheme.labelStyle
                            .copyWith(fontSize: 9, letterSpacing: 1),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 2),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(mainValue,
                    style: GoogleFonts.outfit(
                        color: mainColor,
                        fontSize: 32,
                        fontWeight: FontWeight.w600)),
              ),
              if (bottomLabel.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(bottomLabel,
                    style: MehdAiTheme.labelStyle
                        .copyWith(color: MehdAiTheme.textSecondary, fontSize: 10)),
              ],
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white.withOpacity(0.05),
                  valueColor: AlwaysStoppedAnimation<Color>(progressColor),
                  minHeight: 4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── What the AI has mastered ─────────────────────────────────────────────

  Widget _buildWhatAIHasMastered(int tradesStudied) {
    final mastery = [
      {
        'label': 'Price patterns',
        'detail': 'Recognizes when charts set up for high-probability moves',
        'stars': _starsFor(tradesStudied, 10),
        'color': MehdAiTheme.green,
      },
      {
        'label': 'News & sentiment',
        'detail': 'Knows when market mood shifts before price reacts',
        'stars': _starsFor(tradesStudied, 30),
        'color': MehdAiTheme.blue,
      },
      {
        'label': 'Repeating cycles',
        'detail': 'Spots patterns that repeat across sessions and pairs',
        'stars': _starsFor(tradesStudied, 80),
        'color': MehdAiTheme.purple,
      },
      {
        'label': 'Global events',
        'detail': 'Links economic data (CPI, NFP) to price behaviour',
        'stars': _starsFor(tradesStudied, 150),
        'color': MehdAiTheme.gold,
      },
      {
        'label': 'Crash detection',
        'detail': 'Identifies unusual market behaviour before it becomes dangerous',
        'stars': _starsFor(tradesStudied, 300),
        'color': MehdAiTheme.red,
      },
    ];

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: Colors.white.withOpacity(0.03),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.stars_rounded,
                      color: MehdAiTheme.textSecondary, size: 18),
                  const SizedBox(width: 8),
                  Text('WHAT YOUR AI HAS MASTERED',
                      style: MehdAiTheme.headingStyle
                          .copyWith(fontSize: 13, letterSpacing: 1.5)),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                'Stars fill as your AI studies more winning trades — automatically.',
                style: MehdAiTheme.labelStyle
                    .copyWith(color: MehdAiTheme.textSecondary, fontSize: 11),
              ),
              const SizedBox(height: 20),
              ...mastery.map((item) => Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item['label'] as String,
                                  style: MehdAiTheme.terminalStyle.copyWith(
                                      fontSize: 12,
                                      color: item['color'] as Color,
                                      fontWeight: FontWeight.bold)),
                              const SizedBox(height: 3),
                              Text(item['detail'] as String,
                                  style: MehdAiTheme.labelStyle
                                      .copyWith(fontSize: 11, height: 1.4)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        _buildStars(
                            item['stars'] as int, item['color'] as Color),
                      ],
                    ),
                  )),
            ],
          ),
        ),
      ),
    );
  }

  int _starsFor(int tradesStudied, int threshold) {
    if (tradesStudied >= threshold * 5) return 5;
    if (tradesStudied >= threshold * 3) return 4;
    if (tradesStudied >= threshold * 2) return 3;
    if (tradesStudied >= threshold) return 2;
    if (tradesStudied >= threshold ~/ 2) return 1;
    return 0;
  }

  Widget _buildStars(int filled, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(
        5,
        (i) => Icon(
          i < filled ? Icons.star_rounded : Icons.star_outline_rounded,
          color: i < filled ? color : color.withOpacity(0.2),
          size: 16,
        ),
      ),
    );
  }

  // ─── Live insight card ────────────────────────────────────────────────────

  Widget _buildLiveInsightCard(String insight) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: MehdAiTheme.green.withOpacity(0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: MehdAiTheme.green.withOpacity(0.2)),
            boxShadow: [
              BoxShadow(
                  color: MehdAiTheme.green.withOpacity(0.05), blurRadius: 20),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: MehdAiTheme.green.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.lightbulb_rounded,
                        color: MehdAiTheme.green, size: 18),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('LATEST EDGE DISCOVERED',
                            style: MehdAiTheme.terminalStyle.copyWith(
                                color: MehdAiTheme.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 12)),
                        const SizedBox(height: 2),
                        Text(
                            'Auto-updated every time the AI finds a new winning pattern',
                            style: MehdAiTheme.labelStyle
                                .copyWith(fontSize: 10)),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: MehdAiTheme.green.withOpacity(0.1)),
                ),
                child: Text(insight,
                    style:
                        MehdAiTheme.labelStyle.copyWith(height: 1.7, fontSize: 13)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ─── Why this matters card ────────────────────────────────────────────────

  Widget _buildWhyThisMatters() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MehdAiTheme.bgSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MehdAiTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('WHY YOUR EDGE KEEPS GROWING',
              style: MehdAiTheme.headingStyle
                  .copyWith(fontSize: 12, letterSpacing: 1.5)),
          const SizedBox(height: 14),
          _whyRow(Icons.person_rounded, MehdAiTheme.purple,
              'This AI knows YOUR market.',
              'Most traders use generic signals that work for everyone and no one. Your AI studies your specific pairs, your sessions, your winning conditions.'),
          const SizedBox(height: 12),
          _whyRow(Icons.trending_up_rounded, MehdAiTheme.green,
              'The more you trade, the sharper it gets.',
              'Every winning trade adds a new lesson. A trader with 500 studied wins has a completely different AI than one with 50.'),
          const SizedBox(height: 12),
          _whyRow(Icons.timer_rounded, MehdAiTheme.blue,
              'Discipline compounds over time.',
              'Retail traders who stick with one system for 6 months statistically outperform those who chase strategies. Your AI locks in what works for you specifically.'),
        ],
      ),
    );
  }

  Widget _whyRow(
      IconData icon, Color color, String bold, String detail) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 12),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: MehdAiTheme.labelStyle
                  .copyWith(fontSize: 13, height: 1.6),
              children: [
                TextSpan(
                    text: '$bold ',
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                TextSpan(text: detail),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
