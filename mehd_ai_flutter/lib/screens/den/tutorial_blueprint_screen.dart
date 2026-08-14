import 'package:flutter/material.dart';
import 'package:mehd_ai_flutter/screens/settings_screen.dart';
import 'package:mehd_ai_flutter/screens/war_room_screen.dart';
import 'package:mehd_ai_flutter/screens/sandbox_mode_screen.dart';
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
import 'package:mehd_ai_flutter/screens/security_screen.dart';

import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/widgets/responsive_layout.dart';
import 'package:flutter/services.dart';

import 'package:mehd_ai_flutter/widgets/blueprint_helpers.dart';
import 'package:mehd_ai_flutter/widgets/blueprint_node_details.dart';
import 'package:mehd_ai_flutter/widgets/blueprint_glass_pill.dart';
class TutorialBlueprintScreen extends StatefulWidget {
  const TutorialBlueprintScreen({super.key});

  @override
  State<TutorialBlueprintScreen> createState() =>
      _TutorialBlueprintScreenState();
}

class _TutorialBlueprintScreenState extends State<TutorialBlueprintScreen> {
  late final List<BlueprintCategory> categories;

  int? _expandedCategoryIndex;
  // ignore: unused_field
  int? _hoveredNodeIndex;

  @override
  void initState() {
    super.initState();

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
                  'The social scanner. It reads news and sentiment constantly to see if market sentiment is bullish or bearish today.',
              icon: Icons.language,
              color: MehdAiTheme.purple),
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
                  'The AI fires trades on your behalf — automatically. You set the conviction threshold (e.g. execute when all 11 agents agree above 92%), and The Den does the rest. Full control, zero emotion.',
              icon: Icons.smart_toy_rounded,
              color: MehdAiTheme.blue,
              routeBuilder: (ctx) => const AutopilotCommandCenter()),
          BlueprintNode(
              id: 'pulse_trading',
              title: 'Neuro Pulse',
              subtitle: 'Manual Mode',
              description:
                  'Manual trading made simple. A clean interface where you can quickly press buy or sell instantly based on 1-tap commands.',
              icon: Icons.waves,
              color: MehdAiTheme.purple,
              routeBuilder: (ctx) => const PulseTradingScreen()),
          BlueprintNode(
              id: 'positions',
              title: 'Positions',
              subtitle: 'Active Trades',
              description:
                  'Track active trades live, with automatic virtual stop-loss enforcement running in the background.',
              icon: Icons.work,
              color: MehdAiTheme.gold),
          BlueprintNode(
              id: 'history',
              title: 'History',
              subtitle: 'Past Trades',
              description:
                  'Your personal trading history. See every trade made along with win rate and profit stats.',
              icon: Icons.history,
              color: Colors.white,
              routeBuilder: (ctx) => const HistoryScreen()),
          BlueprintNode(
              id: 'sandbox_mode',
              title: 'Sandbox Mode',
              subtitle: 'Practice Mode',
              description:
                  'Practice mode. Watch the AI trade on its own using \$10,000 demo money so you can verify accuracy without financial risk.',
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
                  'The institutional accountability dashboard. Shows 30-day win rate trajectory, total signals, capital protected, and agent accuracy scores.',
              icon: Icons.show_chart_rounded,
              color: MehdAiTheme.green,
              routeBuilder: (ctx) => const ScoreboardScreen()),
          BlueprintNode(
              id: 'certified_alpha',
              title: 'Certified Alpha',
              subtitle: 'Your Milestones',
              description:
                  'Earn and share your Bronze, Silver, and Gold achievement cards. Each milestone proves performance milestones.',
              icon: Icons.military_tech_rounded,
              color: MehdAiTheme.gold,
              routeBuilder: (ctx) => const JourneyScreen(showBack: true)),
          BlueprintNode(
              id: 'compliance',
              title: 'Compliance Certificate',
              subtitle: 'Intelligence Cert',
              description:
                  'Formal certificate showing app security standards under AES-256 encryption and 11-Agent verified execution.',
              icon: Icons.verified_rounded,
              color: MehdAiTheme.blue,
              routeBuilder: (ctx) => const ComplianceScreen()),
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
                  'Three unbreakable laws: (I) Max risk per trade, (II) Max trades per day, (III) Min AI consensus required.',
              icon: Icons.gavel_rounded,
              color: MehdAiTheme.red,
              routeBuilder: (ctx) => const ConstitutionScreen()),
          BlueprintNode(
              id: 'security',
              title: 'Security Promise',
              subtitle: 'Anti-Broker',
              description:
                  'Unbreakable commitments protecting you against broker manipulation, spread abuse, and slippage fraud.',
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
    super.dispose();
  }

  void _showNodeDetails(BuildContext context, BlueprintNode node) =>
      showBlueprintNodeDetails(context, node);


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
          // Static Deep Space Slate Background (No laggy particle loops)
          Positioned.fill(
            child: Container(
              color: MehdAiTheme.bgPrimary,
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
    return BlueprintGlassPill(
      node: node,
      uniqueIndex: uniqueIndex,
      pillWidth: pillWidth,
      onTap: () => _showNodeDetails(context, node),
    );
  }
}
