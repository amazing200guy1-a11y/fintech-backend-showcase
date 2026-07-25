import 'package:flutter/material.dart';
import 'dart:ui';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/models/consensus_result.dart';


/// FILE — den_verdict_card.dart
///
/// Build Debrief:
/// The DenVerdictCard represents the final decision of the 11-agent architecture.
/// Displays votes grouped by layer (RESEARCH, STRATEGY, OLYMPUS) and final system checks.

class DenVerdictCard extends StatelessWidget {
  final ConsensusResult consensus;

  const DenVerdictCard({super.key, required this.consensus});

  @override
  Widget build(BuildContext context) {
    final proceed = consensus.proceed;
    final primaryColor = proceed ? MehdAiTheme.green : MehdAiTheme.red;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: const Color(0xFF58A6FF).withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: primaryColor.withOpacity(0.3),
          width: 0.5,
        ),
        boxShadow: proceed
            ? [BoxShadow(color: primaryColor.withOpacity(0.15), blurRadius: 30, spreadRadius: 4)]
            : [],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  'THE DEN HAS SPOKEN',
                  style: MehdAiTheme.headingStyle.copyWith(letterSpacing: 2, color: Colors.white),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const Icon(Icons.shield, color: MehdAiTheme.gold, size: 20),
            ],
          ),
          Text(
            'Den Analysis™',
            style: MehdAiTheme.labelStyle.copyWith(color: MehdAiTheme.gold),
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 24),
          const Divider(height: 1, color: MehdAiTheme.borderColor),
          const SizedBox(height: 16),
          
          _buildLayerStatus('THE RESEARCH', ['grok', 'perplexity', 'gemini']),
          const SizedBox(height: 12),
          _buildLayerStatus('THE STRATEGY', ['gpt-4', 'claude', 'llama']),
          const SizedBox(height: 12),
          _buildLayerStatus('OLYMPUS', ['deepseek', 'openai-o3', 'codestral']),

          const SizedBox(height: 16),
          const Divider(height: 1, color: MehdAiTheme.borderColor),
          const SizedBox(height: 16),

          _buildFinalChecks(),

          const SizedBox(height: 16),
          const Divider(height: 1, color: MehdAiTheme.borderColor),
          const SizedBox(height: 24),

          Row(
            children: [
              Icon(
                proceed ? Icons.check_circle : Icons.warning_rounded,
                color: primaryColor,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  proceed 
                      ? '24/5 AUTONOMOUS SIGNAL VERIFIED' 
                      : 'HARD FREEZE — ${consensus.rejectionReason?.toUpperCase() ?? "SYSTEM LOCKED"}',
                  style: MehdAiTheme.headingStyle.copyWith(
                    fontSize: 20,
                    color: primaryColor,
                  ),
                  overflow: TextOverflow.ellipsis,
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

  Widget _buildLayerStatus(String layerName, List<String> agentIds) {
    final layerVotes = consensus.votes.where((v) => agentIds.contains(v.modelName.toLowerCase())).toList();
    if (layerVotes.isEmpty) return const SizedBox.shrink();

    final agreeCount = layerVotes.where((v) => v.direction == consensus.finalDirection).length;
    final total = agentIds.length;
    final isFull = agreeCount == total;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text(
            '$layerName:',
            style: MehdAiTheme.terminalStyle.copyWith(color: MehdAiTheme.textSecondary, fontWeight: FontWeight.bold),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                '$agreeCount/$total',
                style: MehdAiTheme.terminalStyle.copyWith(color: Colors.white),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Icon(isFull ? Icons.check : Icons.circle_outlined, color: isFull ? MehdAiTheme.green : MehdAiTheme.textSecondary, size: 16),
            const SizedBox(width: 16),
            SizedBox(
              width: 50,
              child: Text(
                consensus.finalDirection,
                style: MehdAiTheme.terminalStyle.copyWith(color: isFull ? MehdAiTheme.green : MehdAiTheme.textSecondary, fontWeight: FontWeight.bold),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        )
      ],
    );
  }

  Widget _buildFinalChecks() {
    final primaryColor = consensus.proceed ? MehdAiTheme.green : MehdAiTheme.red;
    
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(child: Text('THE DON:', style: MehdAiTheme.terminalStyle.copyWith(color: MehdAiTheme.gold, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
            Expanded(
              child: Text(
                ' "${consensus.consensusPercentage.toInt()} confidence. Strike."',
                style: MehdAiTheme.terminalStyle.copyWith(color: MehdAiTheme.textPrimary),
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(child: Text('SENTINEL:', style: MehdAiTheme.terminalStyle.copyWith(color: MehdAiTheme.red, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(consensus.proceed ? 'All clear ' : 'Paradox detected ', style: MehdAiTheme.terminalStyle, overflow: TextOverflow.ellipsis)),
                Icon(consensus.proceed ? Icons.check : Icons.close, color: primaryColor, size: 16),
              ],
            )
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Flexible(child: Text('KERNEL:', style: MehdAiTheme.terminalStyle.copyWith(color: MehdAiTheme.purple, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(child: Text(consensus.proceed ? 'Verified ' : 'Locked ', style: MehdAiTheme.terminalStyle, overflow: TextOverflow.ellipsis)),
                Icon(consensus.proceed ? Icons.check : Icons.close, color: primaryColor, size: 16),
              ],
            )
          ],
        ),
      ],
    );
  }
}
