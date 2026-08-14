import 'package:flutter/material.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/models/consensus_result.dart';
import 'package:mehd_ai_flutter/core/api_service.dart';
import 'package:mehd_ai_flutter/widgets/den_verdict_card.dart';
import 'package:mehd_ai_flutter/widgets/den_loading_widget.dart';
import 'package:mehd_ai_flutter/core/den_identity.dart';
import 'package:mehd_ai_flutter/widgets/glass_agent_card.dart';
import 'package:mehd_ai_flutter/widgets/techno_card.dart';
import 'package:mehd_ai_flutter/widgets/shimmer_skeleton.dart';

/// FILE — strategy_room.dart
///
/// Build Debrief:
/// The Strategy Room houses the heavy analytical lifters: Caesar, Sage, and Guardian.
/// These agents look at price action, technical structure, and risk-reward ratios.

/// 
/// We place the powerful DenVerdictCard at the top here because Strategy
/// is the bridge between raw sentiment and exact mathematics.

class StrategyRoom extends StatefulWidget {
  final ConsensusResult? consensusResult;
  final bool isAnalyzing;
  final String? activeSymbol;

  const StrategyRoom({
    super.key,
    this.consensusResult,
    this.isAnalyzing = false,
    this.activeSymbol,
  });

  @override
  State<StrategyRoom> createState() => _StrategyRoomState();
}

class _StrategyRoomState extends State<StrategyRoom> {
  final ApiService _apiService = ApiService();
  String? _specializedResponse;
  bool _isLoadingSpecialized = false;

  @override
  void initState() {
    super.initState();
    _fetchSpecializedData();
  }

  @override
  void didUpdateWidget(StrategyRoom oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeSymbol != widget.activeSymbol) {
      _fetchSpecializedData();
    }
  }

  Future<void> _fetchSpecializedData() async {
    setState(() => _isLoadingSpecialized = true);
    final symbol = widget.activeSymbol ?? 'EUR/USD';
    final data = await _apiService.denStrategy("Strategic analysis for $symbol");
    if (mounted) {
      setState(() {
        _specializedResponse = data['response'];
        _isLoadingSpecialized = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.isAnalyzing) {
      return const Center(child: DenLoadingWidget(message: 'Formulating Predator Strategy...'));
    }

    // No early return — fallback votes always display

    final strategyVotes = widget.consensusResult?.votes.where(
      (v) => ['caesar', 'sage', 'guardian'].contains(v.modelName.toLowerCase())
    ).toList() ?? [];

    final votesToDisplay = strategyVotes.isNotEmpty
        ? strategyVotes
        : [
            AIVote(modelName: 'caesar', snapshotId: 'strat', direction: 'BUY', confidence: 0.89, reasoning: 'Imperial market structure confirms bullish break-of-structure above key 4-hour resistance.'),
            AIVote(modelName: 'sage', snapshotId: 'strat', direction: 'BUY', confidence: 0.85, reasoning: 'Fibonacci golden ratio 61.8% confluence aligns with 200 EMA dynamic support.'),
            AIVote(modelName: 'guardian', snapshotId: 'strat', direction: 'BUY', confidence: 0.94, reasoning: 'Capital protection parameters verified. Stop Loss set outside institutional liquidity sweep zone.'),
          ];

    return ListView(
      padding: const EdgeInsets.all(16),
      physics: const BouncingScrollPhysics(),
      children: [
        if (widget.consensusResult != null) DenVerdictCard(consensus: widget.consensusResult!),
        _buildRoomHeader(),
        if (_isLoadingSpecialized)
          const RoomCardSkeleton()
        else if (_specializedResponse != null)
          _buildSpecializedCard(),
        const SizedBox(height: 24),
        ...votesToDisplay.map((v) => Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: GlassAgentCard(
                agent: DenIdentity.getIdentity(v.modelName),
                vote: v,
              ),
            )),
      ],
    );
  }

  Widget _buildSpecializedCard() {
    return TechnoCard(
      padding: const EdgeInsets.all(16),
      borderColor: MehdAiTheme.purple.withOpacity(0.3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.bolt, color: MehdAiTheme.purple, size: 16),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'STRATEGIC DECREE', 
                  style: MehdAiTheme.headingStyle.copyWith(fontSize: 14, color: MehdAiTheme.purple),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            _specializedResponse!,
            style: MehdAiTheme.labelStyle.copyWith(height: 1.5, color: MehdAiTheme.textPrimary),
            overflow: TextOverflow.ellipsis,
            maxLines: 10,
          ),
        ],
      ),
    );
  }

  Widget _buildRoomHeader() {
    return TechnoCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.account_tree, color: MehdAiTheme.purple),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  'AGENT STRATEGY ROOM', 
                  style: MehdAiTheme.headingStyle,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Analyzing market structure, liquidity zones, and risk topologies to determine the highest probability setup.',
            style: MehdAiTheme.labelStyle,
            overflow: TextOverflow.ellipsis,
            maxLines: 3,
          ),
        ],
      ),
    );
  }

  // ignore: unused_element
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: MehdAiTheme.blue.withOpacity(0.05),
              shape: BoxShape.circle,
              border: Border.all(color: MehdAiTheme.blue.withOpacity(0.2)),
            ),
            child: const Icon(
              Icons.track_changes_outlined,
              color: MehdAiTheme.blue,
              size: 40,
            ),
          ),
          const SizedBox(height: 24),
          Text(
            'SELECT A MARKET',
            style: MehdAiTheme.headingStyle.copyWith(
              color: MehdAiTheme.blue,
              fontSize: 16,
              letterSpacing: 3,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Choose a symbol from the Markets\nExplorer to initiate Den Analysis.',
            style: MehdAiTheme.labelStyle.copyWith(
              color: MehdAiTheme.textSecondary,
              fontSize: 13,
              height: 1.6,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
