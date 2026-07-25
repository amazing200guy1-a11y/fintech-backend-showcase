import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/core/constants.dart';
import 'package:mehd_ai_flutter/services/settings_service.dart';
import 'package:mehd_ai_flutter/widgets/protection_score.dart';
import 'package:mehd_ai_flutter/widgets/milestone_share_dialog.dart';

/// FILE — journey_screen.dart
///
/// Build Debrief:
/// Mehd AI compresses 8 years of manual trading failures into 24 weeks of 24/5 autonomous discipline.
/// 
/// Key Features:
/// 1. Dynamic Timeline: Calculates current Week (1 to 24) from user account creation date.
/// 2. Protection Score: Dynamic rating derived from SettingsService risk parameters.
/// 3. Certified Alpha Milestones: Unlocks Bronze (Week 1+), Silver (Week 5+), Gold (Week 9+) dynamically.
/// 4. Autonomous Defense DNA: Displays how The Den's 24/5 engine automatically prevented revenge trades,
///    news blackout losses, and over-leveraging on behalf of the trader.

class JourneyScreen extends StatelessWidget {
  /// [showBack] = false when rendered inside the sidebar nav (desktop/mobile layout).
  /// [showBack] = true only when pushed via Navigator.push from drawer or deep links.
  final bool showBack;
  const JourneyScreen({super.key, this.showBack = false});

  int _calculateCurrentWeek() {
    final user = FirebaseAuth.instance.currentUser;
    if (user?.metadata.creationTime != null) {
      final days = DateTime.now().difference(user!.metadata.creationTime!).inDays + 1;
      return ((days / 7).ceil()).clamp(1, 24);
    }
    return 3; // Fallback demo week if unauthenticated
  }

  int _calculateUnlockedStage(int currentWeek) {
    if (currentWeek >= 9) return 3; // Gold
    if (currentWeek >= 5) return 2; // Silver
    return 1; // Bronze
  }

  @override
  Widget build(BuildContext context) {
    final currentWeek = _calculateCurrentWeek();
    final unlockedStage = _calculateUnlockedStage(currentWeek);
    final settings = context.watch<SettingsService>();

    // Protection Score: conservative risk = higher score.
    final protectionScore = settings.riskPerTrade <= 3.0 ? 95
        : settings.riskPerTrade <= 7.0 ? 84
        : 72;

    // Key ecosystem values pulled live from SettingsService
    final userName = settings.profileName.toUpperCase();
    final convictionPct = settings.convictionThreshold.toStringAsFixed(0);
    final killSwitchPct = AppConstants.killSwitchPercent.toStringAsFixed(0);
    final maxTrades = settings.maxDailyTrades;
    final lotSize = settings.defaultLotSize.toStringAsFixed(2);
    final mode = settings.paperMode ? 'PAPER' : 'LIVE';

    return Scaffold(
      backgroundColor: MehdAiTheme.bgPrimary,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: showBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: MehdAiTheme.textSecondary, size: 18),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: Row(
          children: [
            const Icon(Icons.rocket_launch, color: MehdAiTheme.purple),
            const SizedBox(width: 8),
            Text('YOUR JOURNEY', style: MehdAiTheme.headingStyle.copyWith(letterSpacing: 2)),
          ],
        ),
        backgroundColor: MehdAiTheme.bgSecondary,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: MehdAiTheme.borderColor, height: 1),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        physics: const BouncingScrollPhysics(),
        children: [
          _buildHeader(context, currentWeek, unlockedStage, protectionScore, mode),
          const SizedBox(height: 32),
          
          // Responsive layout
          LayoutBuilder(
            builder: (context, constraints) {
              final isMobile = constraints.maxWidth < 800;
              
              if (isMobile) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildTimeline(currentWeek, userName, convictionPct, killSwitchPct, maxTrades, lotSize),
                    const SizedBox(height: 32),
                    ProtectionScore(score: protectionScore),
                    const SizedBox(height: 24),
                    _buildAutonomousDefenseDNA(convictionPct, killSwitchPct, maxTrades),
                  ],
                );
              }
              
              // Desktop two-column layout
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left: Timeline List
                  Expanded(
                    flex: 3,
                    child: _buildTimeline(currentWeek, userName, convictionPct, killSwitchPct, maxTrades, lotSize),
                  ),
                  const SizedBox(width: 24),
                  // Right: Stats & DNA
                  Expanded(
                    flex: 4,
                    child: Column(
                      children: [
                        ProtectionScore(score: protectionScore),
                        const SizedBox(height: 24),
                        _buildAutonomousDefenseDNA(convictionPct, killSwitchPct, maxTrades),
                      ],
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, int currentWeek, int unlockedStage, int protectionScore, String mode) {
    final progress = (currentWeek / 24.0).clamp(0.04, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 16,
          runSpacing: 8,
          children: [
            Text(
              '6-MONTH TRANSFORMATION',
              style: MehdAiTheme.headingStyle.copyWith(color: MehdAiTheme.textSecondary, letterSpacing: 1),
            ),
            Builder(
              builder: (ctx) => InkWell(
                onTap: () {
                  showDialog(
                    context: ctx,
                    builder: (context) => MilestoneShareDialog(
                      initialStage: unlockedStage,
                      protectionScore: protectionScore,
                    ),
                  );
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: MehdAiTheme.yellow.withOpacity(0.1),
                    border: Border.all(color: MehdAiTheme.yellow),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.workspace_premium, color: MehdAiTheme.yellow, size: 16),
                      const SizedBox(width: 6),
                      Text(
                        unlockedStage == 3 ? 'GOLD QUANT ALPHA' : (unlockedStage == 2 ? 'SILVER EDGE ALPHA' : 'BRONZE ALIGNED ALPHA'),
                        style: MehdAiTheme.terminalStyle.copyWith(color: MehdAiTheme.yellow, fontWeight: FontWeight.bold, fontSize: 10),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '$mode MODE — Compressing 8 years of failure into 24 weeks of 24/5 autonomous discipline.',
          style: MehdAiTheme.labelStyle.copyWith(fontSize: 14, color: MehdAiTheme.textPrimary),
        ),
        const SizedBox(height: 16),
        LinearProgressIndicator(
          value: progress,
          backgroundColor: MehdAiTheme.bgTertiary,
          valueColor: const AlwaysStoppedAnimation<Color>(MehdAiTheme.blue),
          minHeight: 8,
          borderRadius: BorderRadius.circular(4),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Week $currentWeek of 24', style: MehdAiTheme.labelStyle.copyWith(color: MehdAiTheme.blue, fontWeight: FontWeight.bold)),
            Text('${(progress * 100).toInt()}% Complete', style: MehdAiTheme.labelStyle.copyWith(color: MehdAiTheme.green)),
          ],
        ),
      ],
    );
  }

  Widget _buildTimeline(int currentWeek, String userName, String convictionPct, String killSwitchPct, int maxTrades, String lotSize) {
    // Determine active & completed status based on currentWeek
    final phase1Active = currentWeek >= 1 && currentWeek <= 4;
    final phase1Complete = currentWeek > 4;

    final phase2Active = currentWeek >= 5 && currentWeek <= 8;
    final phase2Complete = currentWeek > 8;

    final phase3Active = currentWeek >= 9 && currentWeek <= 16;
    final phase3Complete = currentWeek > 16;

    final phase4Active = currentWeek >= 17;
    final phase4Complete = currentWeek >= 24;

    return Container(
      decoration: BoxDecoration(
        color: MehdAiTheme.bgSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MehdAiTheme.borderColor),
      ),
      child: Column(
        children: [
          _buildPhase(1, 'Survival & Preservation', 'Weeks 1-4', phase1Active, phase1Complete,
              'Capital preserved 24/5 by HardRiskKernel.\n'
              'Kill-switch: $killSwitchPct% daily drawdown limit enforced.\n'
              'Max $maxTrades trades/day — Constitution Law II.\n'
              'Your risk protocol is locked to your configured settings.'),
          const Divider(color: MehdAiTheme.borderColor, height: 1),
          _buildPhase(2, 'Pattern Recognition', 'Weeks 5-8', phase2Active, phase2Complete,
              'The Den 11 agents identify your winning edge.\n'
              'Only signals with >$convictionPct% consensus reach execution.\n'
              'Broker zero-trust verification active on every signal.\n'
              'Default lot size at $lotSize lots per position.'),
          const Divider(color: MehdAiTheme.borderColor, height: 1),
          _buildPhase(3, 'Execution Edge', 'Weeks 9-16', phase3Active, phase3Complete,
              'Compounding safely with your proven edge.\n'
              'Execution runs 24/5 under your Constitution rules.\n'
              'Consensus threshold: $convictionPct% — no compromise.\n'
              'Kill-switch monitors broker vs oracle price every tick.'),
          const Divider(color: MehdAiTheme.borderColor, height: 1),
          _buildPhase(4, 'Unconscious Competence', 'Weeks 17-24', phase4Active, phase4Complete,
              '$userName — trading is now mechanical and stress-free.\n'
              '24/5 autonomous execution without manual intervention.\n'
              'Constitution upheld. Capital compounds. The Den never sleeps.\n'
              'You are a Sovereign Quant Alpha.'),
        ],
      ),
    );
  }

  Widget _buildPhase(int num, String title, String weeks, bool active, bool completed, String phaseDetail) {
    return Builder(
      builder: (context) {
        Color iconColor = MehdAiTheme.textSecondary;
        if (active) iconColor = MehdAiTheme.blue;
        if (completed && !active) iconColor = MehdAiTheme.green;

        return InkWell(
          onTap: () {
            showModalBottomSheet(
              context: context,
              backgroundColor: MehdAiTheme.bgSecondary,
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              ),
              builder: (ctx) => Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(completed ? Icons.check_circle : (active ? Icons.play_circle_fill : Icons.lock_outline), color: iconColor),
                        const SizedBox(width: 12),
                        Text('PHASE $num', style: MehdAiTheme.headingStyle.copyWith(color: iconColor)),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(title, style: MehdAiTheme.terminalStyle.copyWith(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    Text(weeks, style: MehdAiTheme.labelStyle),
                    const SizedBox(height: 16),
                    const Divider(color: MehdAiTheme.borderColor),
                    const SizedBox(height: 16),
                    Text(
                      phaseDetail,
                      style: MehdAiTheme.labelStyle.copyWith(height: 1.6, color: Colors.white70),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            );
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            color: active ? MehdAiTheme.blue.withOpacity(0.05) : Colors.transparent,
            child: Row(
              children: [
                Icon(
                  completed ? Icons.check_circle : (active ? Icons.play_circle_fill : Icons.lock_outline),
                  color: iconColor,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('PHASE $num • $weeks', style: MehdAiTheme.labelStyle.copyWith(fontSize: 10, color: active ? MehdAiTheme.blue : MehdAiTheme.textSecondary)),
                      const SizedBox(height: 4),
                      Text(
                        title,
                        style: MehdAiTheme.terminalStyle.copyWith(
                          fontWeight: active ? FontWeight.bold : FontWeight.normal,
                          color: active ? MehdAiTheme.textPrimary : MehdAiTheme.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }
    );
  }

  Widget _buildAutonomousDefenseDNA(String convictionPct, String killSwitchPct, int maxTrades) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MehdAiTheme.bgSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MehdAiTheme.blue.withOpacity(0.4)),
        boxShadow: [
          BoxShadow(
            color: MehdAiTheme.blue.withOpacity(0.05),
            blurRadius: 20,
            spreadRadius: 2,
          )
        ]
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_outlined, color: MehdAiTheme.blue, size: 20),
              const SizedBox(width: 8),
              Text('AUTONOMOUS DEFENSE DNA', style: MehdAiTheme.headingStyle.copyWith(color: MehdAiTheme.blue)),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'The Den 24/5 engine automatically eliminates human flaws before they touch capital.',
            style: MehdAiTheme.labelStyle,
          ),
          const SizedBox(height: 20),
          _buildDNATrait('REVENGE TRADE BLOCKING',
              'Auto-blocked emotional re-entries. Every signal needs $convictionPct%+ consensus — emotion cannot force a trade.',
              0.95, MehdAiTheme.green),
          const SizedBox(height: 16),
          _buildDNATrait('NEWS BLACKOUT ENFORCEMENT',
              'Secretary paused execution 30m before High-Impact events. Constitution allows max $maxTrades trades/day.',
              0.88, MehdAiTheme.blue),
          const SizedBox(height: 16),
          _buildDNATrait('OVER-LEVERAGE CAP',
              'HardRiskKernel enforced your risk protocol. Kill-switch at $killSwitchPct% daily drawdown — no exception, no override.',
              0.92, MehdAiTheme.purple),
        ],
      ),
    );
  }

  Widget _buildDNATrait(String title, String desc, double efficiency, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(child: Text(title, style: MehdAiTheme.terminalStyle.copyWith(fontWeight: FontWeight.bold, fontSize: 12), overflow: TextOverflow.ellipsis)),
            Text('${(efficiency * 100).toInt()}% Protection', style: MehdAiTheme.labelStyle.copyWith(color: color, fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 6),
        LinearProgressIndicator(
          value: efficiency,
          backgroundColor: MehdAiTheme.bgTertiary,
          valueColor: AlwaysStoppedAnimation<Color>(color),
          minHeight: 4,
          borderRadius: BorderRadius.circular(2),
        ),
        const SizedBox(height: 8),
        Text(desc, style: MehdAiTheme.labelStyle.copyWith(color: MehdAiTheme.textSecondary, height: 1.4)),
      ],
    );
  }
}

