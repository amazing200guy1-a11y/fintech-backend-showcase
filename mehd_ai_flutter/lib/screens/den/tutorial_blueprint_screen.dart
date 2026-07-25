import 'package:flutter/material.dart';
import 'package:mehd_ai_flutter/screens/settings_screen.dart';
import 'package:mehd_ai_flutter/screens/war_room_screen.dart';
import 'package:mehd_ai_flutter/screens/war_room_community_screen.dart';
import 'package:mehd_ai_flutter/screens/sandbox_mode_screen.dart';
import 'package:mehd_ai_flutter/screens/rejection_feed_screen.dart';
import 'package:mehd_ai_flutter/screens/history_screen.dart';
import 'package:mehd_ai_flutter/screens/data_moat_screen.dart';
import 'package:mehd_ai_flutter/screens/broker_screen.dart';
import 'package:mehd_ai_flutter/screens/pulse_trading_screen.dart';
import 'package:mehd_ai_flutter/screens/journey_screen.dart';
import 'package:mehd_ai_flutter/screens/terms_screen.dart';
import 'package:mehd_ai_flutter/screens/autopilot_command_center.dart';
import 'package:mehd_ai_flutter/screens/scoreboard_screen.dart';
import 'package:mehd_ai_flutter/screens/compliance_screen.dart';
import 'package:mehd_ai_flutter/screens/constitution_screen.dart';
import 'package:mehd_ai_flutter/screens/community_fund_screen.dart';
import 'package:mehd_ai_flutter/screens/security_screen.dart';

import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/widgets/responsive_layout.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'dart:math' as math;

class TutorialBlueprintScreen extends StatefulWidget {
  const TutorialBlueprintScreen({super.key});

  @override
  State<TutorialBlueprintScreen> createState() =>
      _TutorialBlueprintScreenState();
}

class _TutorialBlueprintScreenState extends State<TutorialBlueprintScreen>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _driftController;

  late final List<DataParticle> particles;
  late final List<BlueprintCategory> categories;

  int? _expandedCategoryIndex;
  int? _hoveredNodeIndex;

  @override
  void initState() {
    super.initState();
    _pulseController =
        AnimationController(vsync: this, duration: const Duration(seconds: 4))
          ..repeat(reverse: true);
    _driftController =
        AnimationController(vsync: this, duration: const Duration(seconds: 60))
          ..repeat();

    // Background drift stars
    particles = List.generate(150, (index) {
      return DataParticle(
        startX: (index * 47.0) % 2800,
        startY: (index * 133.0) % 4000,
        vx: (index % 2 == 0 ? 1 : -1) * (index % 100).toDouble() / 2,
        vy: -50.0 - (index % 150),
        size: (index % 3) + 1.0,
        blinkOffset: (index % 10) / 10.0,
        color: index % 6 == 0
            ? MehdAiTheme.blue
            : (index % 7 == 0 ? MehdAiTheme.purple : Colors.white),
      );
    });

    categories = [
      BlueprintCategory(
        title: 'INTELLIGENCE',
        description:
            'The AI Neural Network and Analysis Engines. This is where market psychology meets mathematics.',
        color: MehdAiTheme.purple,
        nodes: [
          BlueprintNode(
              id: 'war_room',
              title: 'War Room',
              subtitle: 'AI Team',
              description:
                  'Your personal AI trading team. 11 smart agents look at the charts and vote on whether a trade is safe. If they don\'t agree on a high enough consensus, no trade fires.',
              icon: Icons.radar,
              color: MehdAiTheme.red,
              routeBuilder: (ctx) => const WarRoomScreen(isAnalyzing: false)),
          BlueprintNode(
              id: 'strategy',
              title: 'The Strategy',
              subtitle: 'Global Events',
              description:
                  'The big-picture macro scanner. It watches world events and economic releases to make sure the AI never fires a trade during a major unpredictable crash.',
              icon: Icons.account_balance,
              color: MehdAiTheme.gold),
          BlueprintNode(
              id: 'news_blackout',
              title: 'News Blackout',
              subtitle: 'Pre-Event Guard',
              description:
                  'An automatic safety gate. 30 minutes before any high-impact economic event (like CPI or NFP), The Den completely stops taking new trades. It resumes automatically once the storm passes.',
              icon: Icons.event_busy_rounded,
              color: MehdAiTheme.red),
          BlueprintNode(
              id: 'olympus',
              title: 'Olympus',
              subtitle: 'Math Engine',
              description:
                  'The pure math calculator. It looks entirely at chart patterns and numbers, ignoring emotions to find the absolute safest entry points.',
              icon: Icons.assessment,
              color: MehdAiTheme.blue),
          BlueprintNode(
              id: 'research',
              title: 'The Research',
              subtitle: 'Social News',
              description:
                  'The social scanner. It reads news and sentiment constantly to see if people feel positive or negative about the market today.',
              icon: Icons.language,
              color: MehdAiTheme.purple),
          BlueprintNode(
              id: 'votes',
              title: 'Rejection Feed',
              subtitle: 'AI Logic',
              description:
                  'The transparent audit log. Read exactly why the AI accepted or rejected every trade in plain English — no black boxes here.',
              icon: Icons.how_to_vote,
              color: MehdAiTheme.green,
              routeBuilder: (ctx) => const RejectionFeedScreen()),
        ],
      ),
      BlueprintCategory(
        title: 'EXECUTION',
        description:
            'The Trade Terminals. Real-time interfaces for pulling the trigger based on intelligence.',
        color: MehdAiTheme.blue,
        nodes: [
          BlueprintNode(
              id: 'autopilot',
              title: 'Autopilot',
              subtitle: 'Auto Execution',
              description:
                  'The AI fires trades on your behalf — automatically. You set the conviction threshold (e.g. only execute when all 11 agents agree above 92%), and The Den does the rest. Full control, zero emotion.',
              icon: Icons.smart_toy_rounded,
              color: MehdAiTheme.blue,
              routeBuilder: (ctx) => const AutopilotCommandCenter()),
          BlueprintNode(
              id: 'terminal',
              title: 'Terminal',
              subtitle: 'Live Data',
              description:
                  'Your fast, real-time command center. Watch live price movements and market changes as they happen without any lag or confusion.',
              icon: Icons.monitor,
              color: MehdAiTheme.blue),
          BlueprintNode(
              id: 'pulse_trading',
              title: 'Neuro Pulse',
              subtitle: 'Manual Mode',
              description:
                  'Manual trading made simple. A clean interface where you can quickly press buy or sell instantly based on your own instinct.',
              icon: Icons.waves,
              color: MehdAiTheme.purple,
              routeBuilder: (ctx) => const PulseTradingScreen()),
          BlueprintNode(
              id: 'market',
              title: 'Market',
              subtitle: 'Live Charts',
              description:
                  'A clean, easy-to-read view of the current market charts and prices, directly connected to your live broker.',
              icon: Icons.candlestick_chart,
              color: MehdAiTheme.green),
          BlueprintNode(
              id: 'positions',
              title: 'Positions',
              subtitle: 'Active Trades',
              description:
                  'Track the trades you are currently in. Watch your floating profit and loss live, with automatic virtual stop-loss enforcement running in the background.',
              icon: Icons.work,
              color: MehdAiTheme.gold),
          BlueprintNode(
              id: 'history',
              title: 'History',
              subtitle: 'Past Trades',
              description:
                  'Your personal trading history. See every trade you have ever made, along with your win rate and overall profits.',
              icon: Icons.history,
              color: Colors.white,
              routeBuilder: (ctx) => const HistoryScreen()),
          BlueprintNode(
              id: 'sandbox_mode',
              title: 'Sandbox Mode',
              subtitle: 'Practice Mode',
              description:
                  'A safe practice mode. Watch the AI trade on its own using \$10,000 demo money so you can verify its accuracy without risking a single penny.',
              icon: Icons.visibility_off,
              color: Colors.grey,
              routeBuilder: (ctx) => const SandboxModeScreen()),
        ],
      ),
      BlueprintCategory(
        title: 'PERFORMANCE & PROOF',
        description:
            'Accountability screens. Real data. Real results. Nothing hidden.',
        color: MehdAiTheme.green,
        nodes: [
          BlueprintNode(
              id: 'truth_engine',
              title: 'Truth Engine',
              subtitle: '30-Day Dashboard',
              description:
                  'The institutional accountability dashboard. Shows the 30-day win rate trajectory, total signals fired, capital protected, and each agent\'s individual accuracy score. This is proof — not marketing.',
              icon: Icons.show_chart_rounded,
              color: MehdAiTheme.green,
              routeBuilder: (ctx) => const ScoreboardScreen()),
          BlueprintNode(
              id: 'certified_alpha',
              title: 'Certified Alpha',
              subtitle: 'Your Milestones',
              description:
                  'Earn and share your Bronze, Silver, and Gold achievement cards. Each milestone proves you have reached a real performance threshold. Download and share your certificate with pride.',
              icon: Icons.military_tech_rounded,
              color: MehdAiTheme.gold,
              routeBuilder: (ctx) => const JourneyScreen(showBack: true)),
          BlueprintNode(
              id: 'compliance',
              title: 'Compliance Certificate',
              subtitle: 'Intelligence Cert',
              description:
                  'Download your official Certificate of Intelligence. A formal document showing the app operates under AES-256 encryption, Zero-Trust protocols, and 11-Agent verified execution standards.',
              icon: Icons.verified_rounded,
              color: MehdAiTheme.blue,
              routeBuilder: (ctx) => const ComplianceScreen()),
        ],
      ),
      BlueprintCategory(
        title: 'COMMUNITY',
        description:
            'The Social Topology. Learn alongside other quantitative operators.',
        color: MehdAiTheme.gold,
        nodes: [
          BlueprintNode(
              id: 'network',
              title: 'The Network',
              subtitle: 'Community',
              description:
                  'The social network. Connect with other users, share your trading ideas, and learn safely from the growing community of MEHD AI operators.',
              icon: Icons.group_work,
              color: MehdAiTheme.gold,
              routeBuilder: (ctx) => const WarRoomCommunityScreen()),
          BlueprintNode(
              id: 'community_fund',
              title: 'Community Fund',
              subtitle: 'Shared Capital',
              description:
                  'A shared mission fund. As the community grows, a portion of platform revenue flows into a collective fund that rewards top-performing community members.',
              icon: Icons.savings_rounded,
              color: MehdAiTheme.green,
              routeBuilder: (ctx) => const CommunityFundScreen()),
        ],
      ),
      BlueprintCategory(
        title: 'LAWS & PROTECTION',
        description:
            'The Three Unbreakable Laws and the security manifesto. The Den enforces these automatically.',
        color: MehdAiTheme.red,
        nodes: [
          BlueprintNode(
              id: 'constitution',
              title: 'Holy Trinity',
              subtitle: 'The 3 Laws',
              description:
                  'Three laws that can never be broken: (I) Maximum risk per trade, (II) Maximum trades per day, (III) Minimum AI consensus required. The Den enforces all three automatically — no exceptions.',
              icon: Icons.gavel_rounded,
              color: MehdAiTheme.red,
              routeBuilder: (ctx) => const ConstitutionScreen()),
          BlueprintNode(
              id: 'security',
              title: 'Security Promise',
              subtitle: 'Anti-Broker',
              description:
                  'The security manifesto. A formal, unbreakable set of commitments protecting you against broker manipulation, spread abuse, and slippage fraud.',
              icon: Icons.security_rounded,
              color: MehdAiTheme.green,
              routeBuilder: (ctx) => const SecurityScreen()),
        ],
      ),
      BlueprintCategory(
        title: 'SYSTEM CORE',
        description:
            'Infrastructure and configuration. The foundational architecture powering the engine.',
        color: Colors.white,
        nodes: [
          BlueprintNode(
              id: 'den',
              title: 'THE DEN',
              subtitle: 'The Core App',
              description:
                  'The main dashboard of the entire app. Everything connects here, making it simple to navigate between your tools and live trades.',
              icon: Icons.hub,
              color: Colors.white),
          BlueprintNode(
              id: 'data_moat',
              title: 'Data Moat',
              subtitle: 'Security Vault',
              description:
                  'The security vault. Your personal passwords and financial data are deeply encrypted and never shared with third parties.',
              icon: Icons.shield,
              color: MehdAiTheme.blue,
              routeBuilder: (ctx) => const DataMoatScreen()),
          BlueprintNode(
              id: 'accounts',
              title: 'Broker Bridge',
              subtitle: 'Connections',
              description:
                  'Connect the app to the real world. Link your MetaTrader, ECN, or exchange account. Monitor latency, spread stability, and withdrawal scores in real-time.',
              icon: Icons.account_box,
              color: MehdAiTheme.red,
              routeBuilder: (ctx) => const BrokerScreen()),
          BlueprintNode(
              id: 'settings',
              title: 'Settings',
              subtitle: 'Preferences',
              description:
                  'Control how the app works. Switch between paper and live trading, adjust your lot size, set conviction thresholds, and configure autopilot behavior.',
              icon: Icons.settings,
              color: Colors.grey,
              routeBuilder: (ctx) => const SettingsScreen()),
          BlueprintNode(
              id: 'terms',
              title: 'Terms',
              subtitle: 'Our Rules',
              description:
                  'The core rules of the app. Read how we protect your money and why we designed this engine to put your capital safety above everything else.',
              icon: Icons.gavel,
              color: Colors.grey,
              routeBuilder: (ctx) => const TermsScreen()),
        ],
      ),
    ];
  }


  @override
  void dispose() {
    _pulseController.dispose();
    _driftController.dispose();
    super.dispose();
  }

  void _showNodeDetails(BuildContext context, BlueprintNode node) {
    HapticFeedback.lightImpact();
    showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        barrierColor: Colors.black.withOpacity(0.6),
        isScrollControlled: true,
        builder: (context) {
          return Container(
            padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 32,
                bottom: 24 + MediaQuery.of(context).padding.bottom),
            decoration: BoxDecoration(
                color: const Color(0xFF020306).withOpacity(0.95),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(30)),
                border: Border(
                    top: BorderSide(
                        color: node.color.withOpacity(0.3), width: 1.5)),
                boxShadow: [
                  BoxShadow(
                      color: node.color.withOpacity(0.1),
                      blurRadius: 40,
                      offset: const Offset(0, -10))
                ]),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 50,
                      height: 50,
                      decoration: BoxDecoration(
                        color: node.color.withOpacity(0.1),
                        shape: BoxShape.circle,
                        border: Border.all(color: node.color.withOpacity(0.3)),
                      ),
                      child: Icon(node.icon, color: node.color, size: 28),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(node.title.toUpperCase(),
                              style: MehdAiTheme.headingStyle.copyWith(
                                  color: Colors.white,
                                  fontSize: 18,
                                  letterSpacing: 2)),
                          const SizedBox(height: 4),
                          Text(node.subtitle,
                              style: MehdAiTheme.terminalStyle.copyWith(
                                  color: node.color.withOpacity(0.8),
                                  fontSize: 12)),
                        ],
                      ),
                    )
                  ],
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.02),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.05)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('> DECRYPTING NODE DATA...',
                          style: MehdAiTheme.terminalStyle
                              .copyWith(color: Colors.grey, fontSize: 10)),
                      const SizedBox(height: 12),
                      TypewriterText(
                        text: node.description,
                        style: MehdAiTheme.bodyStyle.copyWith(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 14,
                            height: 1.6),
                        typingSpeed: const Duration(milliseconds: 15),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                if (node.routeBuilder != null) ...[
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: node.color.withOpacity(0.2),
                        padding: const EdgeInsets.symmetric(vertical: 18),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16)),
                        elevation: 0,
                      ),
                      onPressed: () {
                        Navigator.pop(context);
                        Navigator.push(context,
                            MaterialPageRoute(builder: node.routeBuilder!));
                      },
                      child: Text('ENTER ${node.title.toUpperCase()}',
                          style: MehdAiTheme.terminalStyle.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 2.0,
                              fontSize: 14)),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: node.routeBuilder != null
                          ? Colors.transparent
                          : node.color.withOpacity(0.1),
                      side: BorderSide(color: node.color.withOpacity(0.5)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: Text('CLOSE DIAGNOSTICS',
                        style: MehdAiTheme.terminalStyle.copyWith(
                            color: node.color,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5)),
                  ),
                ),
              ],
            ),
          );
        });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF020306),
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('THE DEN // ARCHITECTURE ALGORITHM',
            style: MehdAiTheme.terminalStyle.copyWith(
                color: Colors.white70,
                fontSize: 13,
                letterSpacing: 2.0,
                fontWeight: FontWeight.bold)),
      ),
      body: Stack(
        children: [
          // Deep Space / Radar Glow beneath the grid
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                return Container(
                  decoration: BoxDecoration(
                    gradient: RadialGradient(
                      center: Alignment.center,
                      radius: 1.0 + (_pulseController.value * 0.1),
                      colors: [
                        MehdAiTheme.purple.withOpacity(0.08),
                        MehdAiTheme.blue.withOpacity(0.03),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.4, 1.0],
                    ),
                  ),
                );
              },
            ),
          ),
          Positioned.fill(child: CustomPaint(painter: GridPainter())),
          // Elegant wireframe typography watermark with Shimmer Sweep
          Positioned.fill(
            child: IgnorePointer(
              child: Center(
                child: Opacity(
                  opacity: 0.18,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, child) {
                        // Creates a scanning sweep from left to right and back
                        final shift = (_pulseController.value * 3.0) - 1.0;

                        return ShaderMask(
                          blendMode: BlendMode.srcIn,
                          shaderCallback: (bounds) {
                            return LinearGradient(
                              begin: Alignment(shift - 0.5, -0.5),
                              end: Alignment(shift + 0.5, 0.5),
                              colors: [
                                Colors.white.withOpacity(0.1),
                                Colors.white,
                                MehdAiTheme.blue,
                                Colors.white.withOpacity(0.1),
                              ],
                              stops: const [0.0, 0.4, 0.5, 1.0],
                            ).createShader(bounds);
                          },
                          child: Text(
                            'MEHD AI',
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            style: GoogleFonts.syncopate(
                              fontSize: MediaQuery.of(context).size.width > 600
                                  ? 120
                                  : MediaQuery.of(context).size.width * 0.18,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 30.0,
                            ).copyWith(
                              foreground: Paint()
                                ..style = PaintingStyle.stroke
                                ..strokeWidth = 1.8
                                ..color = Colors.white,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          ),
          // The floating particles layer (Flat, on top of the Grid)
          Positioned.fill(
            child: CustomPaint(
              painter: CyberStarsPainter(
                  particles: particles,
                  pulse: _pulseController,
                  drift: _driftController),
            ),
          ),
          SafeArea(
            child: ResponsiveLayout(
              child: ListView.builder(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
                physics: const BouncingScrollPhysics(),
                itemCount: categories.length,
                itemBuilder: (context, index) {
                  return _buildAccordion(index);
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccordion(int index) {
    final category = categories[index];
    final isExpanded = _expandedCategoryIndex == index;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        decoration: BoxDecoration(
            color: const Color(0xFF13151B).withOpacity(0.95),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isExpanded
                  ? category.color.withOpacity(0.5)
                  : Colors.white.withOpacity(0.08),
              width: isExpanded ? 2.0 : 1.0,
            ),
            boxShadow: [
              if (isExpanded)
                BoxShadow(
                  color: category.color.withOpacity(0.15),
                  blurRadius: 30,
                  offset: const Offset(0, 10),
                )
            ]),
        child: Column(
          children: [
            InkWell(
              onTap: () {
                setState(() {
                  _expandedCategoryIndex = isExpanded ? null : index;
                });
                HapticFeedback.lightImpact();
              },
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: category.color.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                        border:
                            Border.all(color: category.color.withOpacity(0.3)),
                      ),
                      child: Icon(Icons.folder_shared_outlined,
                          color: category.color, size: 24),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(category.title,
                              style: MehdAiTheme.headingStyle.copyWith(
                                  color: Colors.white,
                                  fontSize: 16,
                                  letterSpacing: 2.0)),
                          const SizedBox(height: 4),
                          Text(
                              isExpanded
                                  ? '> ACCESS GRANTED // DECRYPTING FOLDER...'
                                  : '> FOLDER LOCKED',
                              style: MehdAiTheme.terminalStyle.copyWith(
                                  color: isExpanded
                                      ? category.color
                                      : Colors.white38,
                                  fontSize: 10)),
                        ],
                      ),
                    ),
                    Icon(
                      isExpanded
                          ? Icons.keyboard_arrow_up
                          : Icons.keyboard_arrow_down,
                      color: isExpanded ? category.color : Colors.white54,
                    )
                  ],
                ),
              ),
            ),

            // Nested Node Grid
            AnimatedCrossFade(
              firstChild: const SizedBox(width: double.infinity, height: 0),
              secondChild: Container(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Divider(color: Colors.white.withOpacity(0.05)),
                    const SizedBox(height: 12),
                    Text(
                      category.description,
                      style: MehdAiTheme.labelStyle.copyWith(
                          color: Colors.white70,
                          fontStyle: FontStyle.italic,
                          height: 1.5),
                    ),
                    const SizedBox(height: 20),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        // Dynamically calculate pill width to guarantee 2 per row
                        // on any screen. Accounts for 12px spacing between pills.
                        const pillSpacing = 12.0;
                        final availableWidth = constraints.maxWidth;
                        final pillWidth = ((availableWidth - pillSpacing) / 2).clamp(120.0, 180.0);
                        return Wrap(
                          spacing: pillSpacing,
                          runSpacing: 12,
                          alignment: WrapAlignment.center,
                          children: category.nodes.asMap().entries.map((entry) {
                            return _build3DGlassPill(entry.value,
                                index * 100 + entry.key, pillWidth);
                          }).toList(),
                        );
                      },
                    ),
                  ],
                ),
              ),
              crossFadeState: isExpanded
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 300),
              sizeCurve: Curves.easeInOut,
            ),
          ],
        ),
      ),
    );
  }

  // The Masterpiece 3D Glass Pill Design (Now adaptable for Grid)
  Widget _build3DGlassPill(BlueprintNode node, int uniqueIndex, [double pillWidth = 160]) {
    bool isHovered = _hoveredNodeIndex == uniqueIndex;

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredNodeIndex = uniqueIndex),
      onExit: (_) => setState(() => _hoveredNodeIndex = null),
      child: GestureDetector(
        onTap: () => _showNodeDetails(context, node),
        child: AnimatedScale(
          scale: isHovered ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: Container(
            width: pillWidth, // Dynamically calculated to fit 2 per row
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF232532).withOpacity(0.85),
                      const Color(0xFF13151B).withOpacity(0.95),
                    ]),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: isHovered
                        ? node.color.withOpacity(0.5)
                        : Colors.white.withOpacity(0.08),
                    width: 1.5),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 5)),
                  if (isHovered)
                    BoxShadow(
                        color: node.color.withOpacity(0.15),
                        blurRadius: 20,
                        spreadRadius: -2),
                ]),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withOpacity(0.15),
                            Colors.white.withOpacity(0.02),
                          ]),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                      boxShadow: [
                        BoxShadow(
                            color: node.color.withOpacity(0.2),
                            blurRadius: 10,
                            spreadRadius: 1)
                      ]),
                  child: Center(
                    child: Icon(node.icon,
                        color: node.color.withOpacity(0.9), size: 22),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  node.title,
                  style: MehdAiTheme.headingStyle.copyWith(
                      color: Colors.white,
                      fontSize: 12,
                      letterSpacing: 0.5,
                      fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  node.subtitle,
                  style: MehdAiTheme.bodyStyle.copyWith(
                      color: Colors.white.withOpacity(0.6), fontSize: 9),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class BlueprintCategory {
  final String title;
  final String description;
  final Color color;
  final List<BlueprintNode> nodes;

  BlueprintCategory(
      {required this.title,
      required this.description,
      required this.color,
      required this.nodes});
}

class BlueprintNode {
  final String id;
  final String title;
  final String subtitle;
  final String description;
  final IconData icon;
  final Color color;
  final Widget Function(BuildContext)? routeBuilder;

  BlueprintNode(
      {required this.id,
      required this.title,
      required this.subtitle,
      required this.description,
      required this.icon,
      required this.color,
      this.routeBuilder});
}

// Hacker Style Typewriter Animation Widget
class TypewriterText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final Duration typingSpeed;

  const TypewriterText(
      {super.key,
      required this.text,
      required this.style,
      this.typingSpeed = const Duration(milliseconds: 20)});

  @override
  State<TypewriterText> createState() => _TypewriterTextState();
}

class _TypewriterTextState extends State<TypewriterText> {
  String _displayedText = "";
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _startTyping();
  }

  void _startTyping() async {
    while (_currentIndex < widget.text.length) {
      if (!mounted) return;
      await Future.delayed(widget.typingSpeed);
      setState(() {
        int charsToAdd = 4;
        if (_currentIndex + charsToAdd > widget.text.length) {
          charsToAdd = widget.text.length - _currentIndex;
        }
        _displayedText +=
            widget.text.substring(_currentIndex, _currentIndex + charsToAdd);
        _currentIndex += charsToAdd;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Text(_displayedText, style: widget.style);
  }
}

// Background Blueprint Grid
class GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white.withOpacity(0.015)
      ..strokeWidth = 1.0;

    double gridSpace = 60.0;
    for (double i = 0; i < size.width; i += gridSpace) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += gridSpace) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class DataParticle {
  final double startX;
  final double startY;
  final double vx;
  final double vy;
  final double size;
  final double blinkOffset;
  final Color color;

  DataParticle(
      {required this.startX,
      required this.startY,
      required this.vx,
      required this.vy,
      required this.size,
      required this.blinkOffset,
      required this.color});
}

// Sparkles / Galaxy Stars Background Animation
class CyberStarsPainter extends CustomPainter {
  final List<DataParticle> particles;
  final Animation<double> pulse;
  final Animation<double> drift;

  CyberStarsPainter(
      {required this.particles, required this.pulse, required this.drift})
      : super(repaint: Listenable.merge([pulse, drift]));

  @override
  void paint(Canvas canvas, Size size) {
    // Only particles are drawn here in this top layer!

    for (var p in particles) {
      double baseX = p.startX + (p.vx * drift.value);
      double baseY = p.startY + (p.vy * drift.value);
      double swirlX =
          math.sin((drift.value * 20 * math.pi) + (p.blinkOffset * 20)) *
              (p.size * 30);
      double swirlY =
          math.cos((drift.value * 15 * math.pi) + (p.blinkOffset * 20)) *
              (p.size * 30);

      double currentX = (baseX + swirlX) % size.width;
      double currentY = (baseY + swirlY) % size.height;

      if (currentX < 0) currentX += size.width;
      if (currentY < 0) currentY += size.height;

      double blink = (pulse.value + p.blinkOffset) % 1.0;
      double opacity = (blink > 0.5 ? 1.0 - blink : blink) * 2.0;

      final paint = Paint()
        ..color = p.color.withOpacity(opacity * 0.8)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, p.size * 2);

      canvas.drawCircle(Offset(currentX, currentY), p.size + 1.0, paint);

      final corePaint = Paint()..color = Colors.white.withOpacity(opacity);
      canvas.drawCircle(Offset(currentX, currentY), p.size / 1.5, corePaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
