import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mehd_ai_flutter/core/den_identity.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/models/consensus_result.dart';
import 'package:mehd_ai_flutter/widgets/agent_symbol_painter.dart';

/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
///  GLASSMORPHISM AGENT CARD
///  Premium frosted-glass card for each of the 11 agents.
///  Features:
///  • BackdropFilter frosted glass with luminous border
///  • Procedurally rendered 3D geometric symbol per agent
///  • Ambient pulse animation on the border glow
///  • Vote status indicator with direction color
///  • Tap to expand reasoning (optional)
/// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

class GlassAgentCard extends StatefulWidget {
  final AgentIdentity agent;
  final AIVote? vote;
  final bool compact;

  const GlassAgentCard({
    super.key,
    required this.agent,
    this.vote,
    this.compact = false,
  });

  @override
  State<GlassAgentCard> createState() => _GlassAgentCardState();
}

class _GlassAgentCardState extends State<GlassAgentCard>
    with TickerProviderStateMixin {
  late AnimationController _pulseCtrl;
  late Animation<double> _pulseAnim;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    // Pulse: breathing glow on border + symbol
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final agent = widget.agent;
    final vote = widget.vote;
    final hasVoted = vote != null;
    final accentColor = agent.nodeColor;

    // Vote direction color
    Color voteColor = MehdAiTheme.textSecondary;
    String voteText = '—';
    if (hasVoted) {
      switch (vote.direction) {
        case 'BUY':
          voteColor = MehdAiTheme.green;
          voteText = 'BUY';
          break;
        case 'SELL':
          voteColor = MehdAiTheme.red;
          voteText = 'SELL';
          break;
        default:
          voteColor = MehdAiTheme.grey; // HOLD = grey (idle/neutral)
          voteText = 'HOLD';
      }
    }

    final symbolSize = widget.compact ? 28.0 : 40.0;

    return GestureDetector(
      onTap: hasVoted ? () => setState(() => _expanded = !_expanded) : null,
      child: AnimatedBuilder(
        animation: _pulseAnim,
        builder: (context, _) {
          final pulseVal = _pulseAnim.value;

          return Container(
            padding: EdgeInsets.symmetric(
              horizontal: widget.compact ? 6 : 10,
              vertical: widget.compact ? 8 : 10,
            ),
            decoration: BoxDecoration(
              // Sharp glass fill — no blur
              color: const Color(0xFF101820),
              borderRadius: BorderRadius.circular(12),
              // Luminous border that breathes
              border: Border.all(
                color: accentColor.withOpacity(
                  0.2 + (hasVoted ? pulseVal * 0.4 : 0),
                ),
                width: hasVoted ? 1.0 : 0.5,
              ),
              // Ambient glow
              boxShadow: [
                if (hasVoted)
                  BoxShadow(
                    color: accentColor.withOpacity(0.06 + pulseVal * 0.14),
                    blurRadius: 20,
                    spreadRadius: -2,
                  ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Animated Geometric Symbol ──
                Transform.scale(
                  scale: 1.0 + (pulseVal * 0.08),
                  child: Transform.rotate(
                    angle: (pulseVal - 0.5) * 0.4,
                    child: SizedBox(
                      width: symbolSize,
                      height: symbolSize,
                      child: CustomPaint(
                        painter: AgentSymbolPainter(
                          agentId: agent.id,
                          color: accentColor,
                          pulse: pulseVal,
                          hasVoted: hasVoted,
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(height: widget.compact ? 4 : 6),

                // ── Agent Name ──
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    agent.displayName,
                    style: GoogleFonts.jetBrainsMono(
                      color: hasVoted
                          ? Colors.white
                          : Colors.white.withOpacity(0.5),
                      fontSize: widget.compact ? 9 : 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                  ),
                ),

                if (!widget.compact) ...[
                  const SizedBox(height: 2),
                  // ── Personality Subtitle ──
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      agent.personality,
                      style: GoogleFonts.outfit(
                        color: accentColor.withOpacity(0.6),
                        fontSize: 9,
                        fontWeight: FontWeight.w400,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                    ),
                  ),
                ],

                SizedBox(height: widget.compact ? 3 : 6),

                // ── Vote Status ──
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Pulsing status dot
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: hasVoted
                              ? voteColor
                              : Colors.grey.withOpacity(0.3),
                          boxShadow: hasVoted
                              ? [
                                  BoxShadow(
                                    color: voteColor.withOpacity(0.6),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ]
                              : [],
                        ),
                      ),
                      const SizedBox(width: 5),
                      Text(
                        hasVoted
                            ? '$voteText ${(vote.confidence * 100).toInt()}%'
                            : 'STANDBY',
                        style: GoogleFonts.jetBrainsMono(
                          color: hasVoted
                              ? voteColor
                              : Colors.grey.withOpacity(0.4),
                          fontSize: widget.compact ? 8 : 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Expanded Reasoning ──
                if (_expanded && hasVoted) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.4),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: accentColor.withOpacity(0.15),
                      ),
                    ),
                    child: Text(
                      vote.reasoning,
                      style: GoogleFonts.jetBrainsMono(
                        color: Colors.white.withOpacity(0.6),
                        fontSize: 8,
                        height: 1.4,
                      ),
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════
//  AGENT GRID — Displays all 11 agents in glassmorphism
//  cards grouped by layer. Used in the VOTES tab.
// ═══════════════════════════════════════════════════════════

class AgentGlassGrid extends StatelessWidget {
  final ConsensusResult? consensus;

  const AgentGlassGrid({super.key, this.consensus});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildLayerSection(
            'THE RESEARCH',
            'Intelligence Layer',
            const Color(0xFF6A0DAD),
            ['don', 'phantom', 'oracle'],
          ),
          const SizedBox(height: 16),
          _buildLayerSection(
            'THE STRATEGY',
            'Strategy Layer',
            MehdAiTheme.gold,
            ['caesar', 'sage', 'guardian'],
          ),
          const SizedBox(height: 16),
          _buildLayerSection(
            'OLYMPUS',
            'Quantitative Layer',
            MehdAiTheme.blue,
            ['titan', 'atlas', 'forge'],
          ),
          const SizedBox(height: 16),
          _buildLayerSection(
            'SUPREME & GUARDIAN',
            'Override Layer',
            Colors.white,
            ['the don', 'sentinel'],
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildLayerSection(
    String layerName,
    String subtitle,
    Color accent,
    List<String> agentIds,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Layer header
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: accent,
                  boxShadow: [
                    BoxShadow(
                      color: accent.withOpacity(0.5),
                      blurRadius: 6,
                      spreadRadius: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                layerName,
                style: GoogleFonts.jetBrainsMono(
                  color: accent,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                subtitle,
                style: GoogleFonts.outfit(
                  color: accent.withOpacity(0.4),
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
        // Agent cards row
        Row(
          children: agentIds.map((id) {
            final agent = DenIdentity.getIdentity(id);
            final vote = _findVoteForAgent(id);
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: GlassAgentCard(
                  agent: agent,
                  vote: vote,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  AIVote? _findVoteForAgent(String agentId) {
    if (consensus == null) return null;

    // Map agent IDs to backend model names
    const agentToModel = {
      'don': 'grok',
      'phantom': 'perplexity',
      'oracle': 'gemini',
      'caesar': 'gpt-4',
      'sage': 'claude',
      'guardian': 'llama',
      'titan': 'deepseek',
      'atlas': 'openai-o3',
      'forge': 'codestral',
      'the don': 'chairman',
      'sentinel': 'sentinel',
    };

    final modelName = agentToModel[agentId.toLowerCase()];
    if (modelName == null) return null;

    try {
      return consensus!.votes.firstWhere(
        (v) => v.modelName.toLowerCase() == modelName,
      );
    } catch (_) {
      return null;
    }
  }
}
