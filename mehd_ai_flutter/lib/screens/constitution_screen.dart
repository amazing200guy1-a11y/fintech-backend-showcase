import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/core/constitution_service.dart';
import 'package:mehd_ai_flutter/services/settings_service.dart';

// ─────────────────────────────────────────────────────────────
//  The Holy Trinity Constitution
//  "Three unbreakable laws. The Den enforces them automatically."
// ─────────────────────────────────────────────────────────────

/// Default constitution shown when backend is unreachable.
import 'package:mehd_ai_flutter/widgets/constitution_rule_card.dart';
import 'package:mehd_ai_flutter/widgets/constitution_header_widgets.dart';
/// Always shown instantly so the UI never crashes.
AppConstitution _defaultConstitution() => AppConstitution(
      rules: [
        ConstitutionRule(
          id: 'trinity_1',
          name: 'I. The Law of Position Size',
          description:
              'Never risk more than your configured percentage on a single trade. '
              'A trader who survives lives to compound. A trader who over-sizes dies broke.',
          ruleType: 'max_risk_per_trade',
          parameter: 1.0,
          isActive: true,
        ),
        ConstitutionRule(
          id: 'trinity_2',
          name: 'II. The Law of Daily Discipline',
          description:
              'Maximum trades executed per trading day. After reaching this limit, '
              'The Den locks execution — protecting you from revenge trading and emotional spirals.',
          ruleType: 'max_daily_trades',
          parameter: 3.0,
          isActive: true,
        ),
        ConstitutionRule(
          id: 'trinity_3',
          name: 'III. The Law of Consensus',
          description:
              'All 11 AI agents inside The Den must reach this agreement threshold '
              'before a sniper fires. No consensus, no trade. Precision over frequency.',
          ruleType: 'min_consensus',
          parameter: 70.0,
          isActive: true,
        ),
      ],
      dailyTradesCount: 0,
      lastResetDate: DateTime.now().toIso8601String().substring(0, 10),
    );

class ConstitutionScreen extends StatefulWidget {
  final bool showBack;
  const ConstitutionScreen({super.key, this.showBack = false});

  @override
  State<ConstitutionScreen> createState() => _ConstitutionScreenState();
}

class _ConstitutionScreenState extends State<ConstitutionScreen>
    with SingleTickerProviderStateMixin {
  final _service = ConstitutionService();

  // Always starts with beautiful default data — never crashes
  AppConstitution _constitution = _defaultConstitution();
  // ignore: unused_field
  bool _isLoadingFromServer = true;
  bool _isOffline = false;
  late final AnimationController _shimmerCtrl;

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _loadConstitution();
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConstitution() async {
    if (!mounted) return;
    setState(() {
      _isLoadingFromServer = true;
      _isOffline = false;
    });
    try {
      final live = await _service.getConstitution();
      if (mounted) {
        setState(() {
          _constitution = live;
          _isOffline = false;
        });
      }
    } catch (_) {
      // Backend offline — keep showing the gorgeous default data
      if (mounted) setState(() => _isOffline = true);
    } finally {
      if (mounted) setState(() => _isLoadingFromServer = false);
    }
  }

  Future<void> _updateRuleParameter(ConstitutionRule rule, double newParam) async {
    final settings = context.read<SettingsService>();
    
    // Sync directly to master SettingsService (persists local + cloud)
    if (rule.ruleType == 'max_risk_per_trade') {
      await settings.setRiskPerTrade(newParam);
    } else if (rule.ruleType == 'max_daily_trades') {
      await settings.setMaxDailyTrades(newParam.toInt());
    } else if (rule.ruleType == 'min_consensus') {
      await settings.setConvictionThreshold(newParam);
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Constitution law updated & enforced across ecosystem.', style: TextStyle(color: Color(0xFF00FF88))),
          backgroundColor: Color(0xFF020810),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // ────────────────────────────────────────────────
  //  Build
  // ────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsService>();
    final activeRules = [
      ConstitutionRule(
        id: 'trinity_1',
        name: 'I. The Law of Position Size',
        description: 'Never risk more than your configured percentage on a single trade. A trader who survives lives to compound. A trader who over-sizes dies broke.',
        ruleType: 'max_risk_per_trade',
        parameter: settings.riskPerTrade,
        isActive: true,
      ),
      ConstitutionRule(
        id: 'trinity_2',
        name: 'II. The Law of Daily Discipline',
        description: 'Maximum trades executed per trading day. After reaching this limit, The Den locks execution — protecting you from revenge trading and emotional spirals.',
        ruleType: 'max_daily_trades',
        parameter: settings.maxDailyTrades.toDouble(),
        isActive: true,
      ),
      ConstitutionRule(
        id: 'trinity_3',
        name: 'III. The Law of Consensus',
        description: 'All 11 AI agents inside The Den must reach this agreement threshold before a sniper fires. No consensus, no trade. Precision over frequency.',
        ruleType: 'min_consensus',
        parameter: settings.convictionThreshold,
        isActive: true,
      ),
    ];

    return Scaffold(
      backgroundColor: MehdAiTheme.bgPrimary,
      appBar: AppBar(
        backgroundColor: MehdAiTheme.bgSecondary,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: widget.showBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: MehdAiTheme.textSecondary, size: 18),
                onPressed: () => Navigator.pop(context),
              )
            : null,

        title: Row(
          children: [
            const Icon(Icons.menu_book_rounded, color: MehdAiTheme.blue, size: 18),
            const SizedBox(width: 10),
            Text(
              'THE HOLY TRINITY',
              style: MehdAiTheme.terminalStyle.copyWith(
                color: MehdAiTheme.blue,
                letterSpacing: 2.5,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        children: [
          // Header
          _buildHeader(),
          if (_isOffline) ...[
            const SizedBox(height: 16),
            _buildOfflineBadge(),
          ],
          const SizedBox(height: 32),

          // Stats row
          _buildStatsRow(),
          const SizedBox(height: 32),

          // The Trinity Cards
          ...List.generate(activeRules.length, (i) {
            return _buildTrinityCard(activeRules[i], i);
          }),

          const SizedBox(height: 32),
          _buildFooter(),
          const SizedBox(height: 80),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────
  //  Offline Badge
  // ────────────────────────────────────────────────

  Widget _buildOfflineBadge() {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFD29922).withOpacity(0.1),
        border: Border.all(color: const Color(0xFFD29922).withOpacity(0.3)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Icon(Icons.cloud_off_rounded, color: Color(0xFFD29922), size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Backend offline — showing local Constitution. Start the server to sync live rules.',
              style: MehdAiTheme.labelStyle
                  .copyWith(color: const Color(0xFFD29922), fontSize: 11),
            ),
          ),
          TextButton(
            onPressed: _loadConstitution,
            child: Text('RETRY', style: MehdAiTheme.terminalStyle.copyWith(fontSize: 10)),
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────
  //  Header
  // ────────────────────────────────────────────────
  Widget _buildHeader() {
    return ConstitutionHeaderSection(constitution: _constitution);
  }


  Widget _buildTrinityCard(ConstitutionRule rule, int index) {
    return ConstitutionRuleCard(
      rule: rule,
      index: index,
      onToggleActive: (val) {
        final updated = _constitution.rules.map((r) {
          if (r.id == rule.id) {
            return ConstitutionRule(
              id: r.id,
              name: r.name,
              description: r.description,
              ruleType: r.ruleType,
              parameter: r.parameter,
              isActive: val,
            );
          }
          return r;
        }).toList();
        setState(() {
          _constitution = AppConstitution(
            rules: updated,
            dailyTradesCount: _constitution.dailyTradesCount,
            lastResetDate: _constitution.lastResetDate,
          );
        });
      },
      onUpdateParameter: (val) => _updateRuleParameter(rule, val),
    );
  }

  // ────────────────────────────────────────────────
  //  Footer
  // ────────────────────────────────────────────────

  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MehdAiTheme.bgSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MehdAiTheme.blue.withOpacity(0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.psychology_rounded, color: MehdAiTheme.purple, size: 18),
              const SizedBox(width: 10),
              Text(
                'THE DEN AUDITOR',
                style: MehdAiTheme.headingStyle.copyWith(
                  fontSize: 13,
                  color: MehdAiTheme.purple,
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'After every losing trade, The Den\'s Post-Mortem Agent runs a full analysis. '
            'If it discovers a pattern — overtrading on Fridays, ignoring London opens, trading during '
            'high-impact news — it will PROPOSE a new law to this Constitution. '
            'You review it. You approve it. The Den enforces it.',
            style: MehdAiTheme.labelStyle.copyWith(
              height: 1.7,
              fontSize: 12,
              color: MehdAiTheme.textSecondary,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildFooterTag('✓  Hard Kernel Enforced', MehdAiTheme.green),
              const SizedBox(width: 8),
              _buildFooterTag('✓  AI Self-Learning', MehdAiTheme.purple),
              const SizedBox(width: 8),
              _buildFooterTag('✓  You Approve Rules', MehdAiTheme.blue),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFooterTag(String text, Color color) {
    return Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: color,
            fontSize: 9,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
          ),
        ),
      ),
    );
  }

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(child: _buildStatItem('LAWS ENFORCED', '3 PRECEPTS', const Color(0xFF00FF88))),
        const SizedBox(width: 12),
        Expanded(child: _buildStatItem('BYPASS STATUS', 'HARD-LOCKED', const Color(0xFF58A6FF))),
        const SizedBox(width: 12),
        Expanded(child: _buildStatItem('RISK GUARANTEE', '0% DEVIATION', const Color(0xFFFFD700))),
      ],
    );
  }

  Widget _buildStatItem(String label, String val, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Column(
        children: [
          Text(label, style: GoogleFonts.inter(color: Colors.white54, fontSize: 9, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(val, style: GoogleFonts.orbitron(color: color, fontSize: 11, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
