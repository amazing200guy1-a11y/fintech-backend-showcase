import 'package:flutter/material.dart';
import 'package:mehd_ai_flutter/widgets/agent_symbol_drawers.dart';
import 'package:mehd_ai_flutter/widgets/agent_symbol_drawers_secondary.dart';

class AgentSymbolPainter extends CustomPainter {
  final String agentId;
  final Color color;
  final double pulse;
  final bool hasVoted;

  const AgentSymbolPainter({
    required this.agentId,
    required this.color,
    required this.pulse,
    required this.hasVoted,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 2;
    final alpha = hasVoted ? 1.0 : 0.5;

    switch (agentId.toLowerCase()) {
      case 'phantom':
        AgentSymbolDrawers.drawPhantomRing(canvas, center, radius, alpha);
        break;
      case 'oracle':
        AgentSymbolDrawers.drawOraclePrism(canvas, center, radius, alpha);
        break;
      case 'don':
        AgentSymbolDrawers.drawDonCrown(canvas, center, radius, alpha);
        break;
      case 'caesar':
        AgentSymbolDrawers.drawCaesarSigil(canvas, center, radius, alpha);
        break;
      case 'sage':
        AgentSymbolDrawers.drawSageSphere(canvas, center, radius, alpha);
        break;
      case 'guardian':
        AgentSymbolDrawers.drawGuardianShield(canvas, center, radius, alpha);
        break;

      case 'titan':
        AgentSymbolDrawersSecondary.drawTitanCube(canvas, center, radius, alpha);
        break;
      case 'atlas':
        AgentSymbolDrawersSecondary.drawAtlasWeb(canvas, center, radius, alpha);
        break;
      case 'forge':
        AgentSymbolDrawersSecondary.drawForgeAnvil(canvas, center, radius, alpha);
        break;
      case 'the don':
        AgentSymbolDrawersSecondary.drawSupremeStar(canvas, center, radius, alpha);
        break;
      case 'sentinel':
        AgentSymbolDrawersSecondary.drawSentinelEye(canvas, center, radius, alpha);
        break;
      default:
        AgentSymbolDrawersSecondary.drawDefaultSymbol(canvas, center, radius, alpha, color);
    }
  }

  @override
  bool shouldRepaint(AgentSymbolPainter oldDelegate) =>
      oldDelegate.pulse != pulse ||
      oldDelegate.hasVoted != hasVoted ||
      oldDelegate.agentId != agentId;
}
