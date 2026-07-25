import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/core/constitution_service.dart';
import 'package:mehd_ai_flutter/services/settings_service.dart';

// ─────────────────────────────────────────────────────────────
//  The Holy Trinity Constitution
//  "Three unbreakable laws. The Den enforces them automatically."
// ─────────────────────────────────────────────────────────────

/// Default constitution shown when backend is unreachable.
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
  const ConstitutionScreen({super.key});

  @override
  State<ConstitutionScreen> createState() => _ConstitutionScreenState();
}

class _ConstitutionScreenState extends State<ConstitutionScreen>
    with SingleTickerProviderStateMixin {
  final _service = ConstitutionService();

  // Always starts with beautiful default data — never crashes
  AppConstitution _constitution = _defaultConstitution();
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: MehdAiTheme.textSecondary, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
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
    return Column(
      children: [
        // Glow badge
        Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF1A3A5C), Color(0xFF0D1F33)],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: MehdAiTheme.blue.withOpacity(0.5)),
              boxShadow: [
                BoxShadow(
                  color: MehdAiTheme.blue.withOpacity(0.2),
                  blurRadius: 20,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.auto_awesome, color: MehdAiTheme.blue, size: 14),
                const SizedBox(width: 8),
                Text(
                  'DEN LAW · CONSTITUTION v1.0',
                  style: MehdAiTheme.terminalStyle.copyWith(
                    color: MehdAiTheme.blue,
                    letterSpacing: 2.0,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'The Trader\'s Constitution',
          style: MehdAiTheme.headingStyle.copyWith(fontSize: 26),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 10),
        Text(
          'Three unbreakable laws. Follow them and protect your capital.\n'
          'Break them and The Den stops you — automatically, without mercy.',
          style: MehdAiTheme.labelStyle.copyWith(height: 1.6, fontSize: 13),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        // Hard enforcement banner
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: MehdAiTheme.red.withOpacity(0.07),
            border: Border.all(color: MehdAiTheme.red.withOpacity(0.3)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              const Icon(Icons.shield_outlined, color: MehdAiTheme.red, size: 18),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Enforced by the Hard Risk Kernel. If a trade breaks these laws, '
                  'execution is blocked — no exceptions, no override.',
                  style: MehdAiTheme.labelStyle.copyWith(
                    color: MehdAiTheme.textSecondary,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ────────────────────────────────────────────────
  //  Stats Row
  // ────────────────────────────────────────────────

  Widget _buildStatsRow() {
    return Row(
      children: [
        Expanded(
          child: _buildStatChip(
            icon: Icons.today_rounded,
            label: 'TRADES TODAY',
            value: '${_constitution.dailyTradesCount}',
            color: MehdAiTheme.blue,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatChip(
            icon: Icons.gavel_rounded,
            label: 'ACTIVE LAWS',
            value: '${_constitution.rules.where((r) => r.isActive).length}',
            color: MehdAiTheme.green,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatChip(
            icon: Icons.calendar_today_rounded,
            label: 'LAST RESET',
            value: _constitution.lastResetDate.isEmpty
                ? 'TODAY'
                : _constitution.lastResetDate.substring(5),
            color: MehdAiTheme.gold,
          ),
        ),
      ],
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 20,
              fontWeight: FontWeight.bold,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: MehdAiTheme.labelStyle.copyWith(fontSize: 9, letterSpacing: 1),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────
  //  Trinity Card
  // ────────────────────────────────────────────────

  Widget _buildTrinityCard(ConstitutionRule rule, int index) {
    final colors = [MehdAiTheme.blue, MehdAiTheme.gold, MehdAiTheme.purple];
    final icons = [
      Icons.balance_rounded,
      Icons.bar_chart_rounded,
      Icons.groups_rounded,
    ];
    final accent = colors[index % colors.length];
    final cardIcon = icons[index % icons.length];

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: MehdAiTheme.bgSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withOpacity(0.25)),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.06),
            blurRadius: 20,
            spreadRadius: 2,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Card header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [accent.withOpacity(0.12), Colors.transparent],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: accent.withOpacity(0.15),
                    shape: BoxShape.circle,
                    border: Border.all(color: accent.withOpacity(0.4)),
                  ),
                  child: Icon(cardIcon, color: accent, size: 18),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    rule.name.toUpperCase(),
                    style: MehdAiTheme.headingStyle.copyWith(
                      fontSize: 13,
                      color: accent,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                // Active toggle
                Transform.scale(
                  scale: 0.85,
                  child: Switch(
                    value: rule.isActive,
                    activeColor: accent,
                    activeTrackColor: accent.withOpacity(0.25),
                    inactiveThumbColor: Colors.grey,
                    inactiveTrackColor: Colors.white10,
                    onChanged: (val) {
                      // Optimistic toggle
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
                  ),
                ),
              ],
            ),
          ),
          // Rule description
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rule.description,
                  style: MehdAiTheme.labelStyle.copyWith(
                    height: 1.7,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 20),
                // Parameter control
                _buildParameterControl(rule, accent),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ────────────────────────────────────────────────
  //  Parameter Controls
  // ────────────────────────────────────────────────

  Widget _buildParameterControl(ConstitutionRule rule, Color accent) {
    if (rule.ruleType == 'max_daily_trades') {
      return _buildCountControl(
        label: 'Max Trades Per Day',
        value: rule.parameter.toInt(),
        min: 1,
        max: 10,
        accent: accent,
        onDecrement: rule.parameter > 1
            ? () => _updateRuleParameter(rule, rule.parameter - 1)
            : null,
        onIncrement: rule.parameter < 10
            ? () => _updateRuleParameter(rule, rule.parameter + 1)
            : null,
      );
    }

    if (rule.ruleType == 'min_consensus') {
      return _buildSliderControl(
        label: 'Consensus Required',
        value: rule.parameter,
        displayText: '${rule.parameter.toInt()}%',
        min: 50,
        max: 100,
        minLabel: '50% (Lenient)',
        maxLabel: '100% (Unanimous)',
        accent: accent,
        onChanged: (val) => _updateRuleParameter(rule, val),
      );
    }

    if (rule.ruleType == 'max_risk_per_trade') {
      return _buildSliderControl(
        label: 'Risk Per Trade',
        value: rule.parameter.clamp(0.1, 10.0),
        displayText: '${rule.parameter.toStringAsFixed(1)}%',
        min: 0.1,
        max: 10.0,
        divisions: 99,
        minLabel: '0.1% (Conservative)',
        maxLabel: '10% (Aggressive)',
        accent: accent,
        onChanged: (val) => _updateRuleParameter(
          rule,
          double.parse(val.toStringAsFixed(1)),
        ),
      );
    }

    // AI-managed rule
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: MehdAiTheme.bgPrimary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        children: [
          const Icon(Icons.psychology_rounded, color: MehdAiTheme.purple, size: 16),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'This rule is managed autonomously by The Den AI.',
              style: MehdAiTheme.labelStyle.copyWith(
                color: MehdAiTheme.textSecondary,
                fontStyle: FontStyle.italic,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCountControl({
    required String label,
    required int value,
    required int min,
    required int max,
    required Color accent,
    required VoidCallback? onDecrement,
    required VoidCallback? onIncrement,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: MehdAiTheme.labelStyle
                .copyWith(color: MehdAiTheme.textSecondary, fontSize: 11)),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _counterButton(
              icon: Icons.remove_rounded,
              color: MehdAiTheme.red,
              onTap: onDecrement,
            ),
            const SizedBox(width: 24),
            Text(
              '$value',
              style: TextStyle(
                color: accent,
                fontSize: 36,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
            const SizedBox(width: 24),
            _counterButton(
              icon: Icons.add_rounded,
              color: MehdAiTheme.green,
              onTap: onIncrement,
            ),
          ],
        ),
        const SizedBox(height: 4),
        Center(
          child: Text(
            '$min–$max trades per day',
            style: MehdAiTheme.labelStyle
                .copyWith(fontSize: 10, color: MehdAiTheme.textSecondary),
          ),
        ),
      ],
    );
  }

  Widget _counterButton({
    required IconData icon,
    required Color color,
    required VoidCallback? onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
        color: onTap == null ? Colors.white.withOpacity(0.05) : color.withOpacity(0.12),
          shape: BoxShape.circle,
          border:
              Border.all(color: onTap == null ? Colors.white10 : color.withOpacity(0.4)),
        ),
        child: Icon(
          icon,
          color: onTap == null ? Colors.white24 : color,
          size: 20,
        ),
      ),
    );
  }

  Widget _buildSliderControl({
    required String label,
    required double value,
    required String displayText,
    required double min,
    required double max,
    required String minLabel,
    required String maxLabel,
    required Color accent,
    required ValueChanged<double> onChanged,
    int? divisions,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label,
                style: MehdAiTheme.labelStyle
                    .copyWith(color: MehdAiTheme.textSecondary, fontSize: 11)),
            Text(
              displayText,
              style: TextStyle(
                color: accent,
                fontSize: 20,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: accent,
            inactiveTrackColor: accent.withOpacity(0.15),
            thumbColor: accent,
            overlayColor: accent.withOpacity(0.12),
            trackHeight: 3,
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: divisions ?? ((max - min).round()),
            onChanged: onChanged,
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(minLabel,
                style: MehdAiTheme.labelStyle
                    .copyWith(fontSize: 10, color: MehdAiTheme.textSecondary)),
            Text(maxLabel,
                style: MehdAiTheme.labelStyle
                    .copyWith(fontSize: 10, color: MehdAiTheme.textSecondary)),
          ],
        ),
      ],
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
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
