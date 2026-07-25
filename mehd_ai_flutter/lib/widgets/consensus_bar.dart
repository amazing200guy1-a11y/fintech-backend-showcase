import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mehd_ai_flutter/services/settings_service.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/core/constants.dart';
import 'package:mehd_ai_flutter/models/consensus_result.dart';
import 'package:mehd_ai_flutter/widgets/swipe_to_execute.dart';

/// FILE 8 — consensus_bar.dart
///
/// Build Debrief:
/// This is the singular interaction point for placing a trade. 
/// In traditional apps, you have complex order tickets. Here, the AI has already
/// determined the direction, and the HardRiskKernel determines the lot size and 
/// stop loss behind the scenes. This button only unlocks when the mathematical threshold 
/// (70% consensus) is reached. It visually communicates "Wait" vs "Execute".

class ConsensusBar extends StatelessWidget {
  final ConsensusResult? consensus;
  final ButtonState buttonState;
  final VoidCallback onTradePressed;
  final double currentSpread;

  const ConsensusBar({
    super.key,
    this.consensus,
    required this.buttonState,
    required this.onTradePressed,
    this.currentSpread = 0.0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 74),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF000000).withOpacity(0.85),
            const Color(0xFF0A0A12).withOpacity(0.92),
          ],
        ),
        border: Border(
          top: BorderSide(
            color: const Color(0xFF58A6FF).withOpacity(0.12),
            width: 0.5,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 12.0),
      child: Row(
        children: [
          // Left: Consensus Score (Wrapped in Flexible to prevent push)
          Flexible(flex: 2, child: _buildScoreSection()),
          const SizedBox(width: 12),
          
          // Center: Risk Pill (Hide on very narrow screens or keep flexible)
          Flexible(flex: 2, child: LayoutBuilder(builder: (context, constraints) {
            if (constraints.maxWidth < 100) return const SizedBox.shrink();
            return _buildRiskPill(context);
          })),
          const SizedBox(width: 12),
          
          // Right: Action Button (Flexible)
          Expanded(flex: 5, child: _buildTradeButton()),
        ],
      ),
    );
  }

  Widget _buildScoreSection() {
    if (consensus == null) {
      return Column(
        key: const ValueKey('score_null'),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text('--%', style: MehdAiTheme.priceStyle.copyWith(color: MehdAiTheme.textSecondary, fontSize: 20)),
          Text('24/5 LIVE STREAM', style: MehdAiTheme.labelStyle.copyWith(fontSize: 10)),
        ],
      );
    }

    final isBuy = consensus!.finalDirection == 'BUY';
    final isSell = consensus!.finalDirection == 'SELL';
    final isSovereignWaiting = consensus!.tier == 'sovereign' && !consensus!.proceed;
    final isSovereignLock = consensus!.isSovereignLockAchieved || (consensus!.tier == 'sovereign' && consensus!.proceed);
    
    final color = isSovereignLock ? MehdAiTheme.white : (isSovereignWaiting ? MehdAiTheme.yellow : (isBuy ? MehdAiTheme.green : (isSell ? MehdAiTheme.red : MehdAiTheme.yellow)));
    final count = consensus!.votes.where((v) => v.direction == consensus!.finalDirection).length;
    final total = consensus!.votes.length;
    final scoreText = consensus!.consensusPercentage.toStringAsFixed(0);

    if (isSovereignLock) {
      // Build sovereign conditions summary
      final conditions = consensus!.sovereignConditions;
      final passed = conditions.values.where((v) => v).length;
      final conditionsText = conditions.isNotEmpty
          ? '$passed/${conditions.length} conditions passed'
          : 'All conditions passed';

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            '⚡ SOVEREIGN LOCK ACHIEVED',
            style: MehdAiTheme.priceStyle.copyWith(color: MehdAiTheme.white, fontSize: 13, fontWeight: FontWeight.bold, shadows: MehdAiTheme.textGlowWhite),
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            '11/11 Unanimous | THE DON: $scoreText/100\n$conditionsText | SENTINEL: Clear\nStrike with full force.',
            style: MehdAiTheme.labelStyle.copyWith(fontSize: 10, color: MehdAiTheme.white.withOpacity(0.9), height: 1.2),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    } else if (isSovereignWaiting) {
      String waitReason = consensus!.rejectionReason ?? 'Pending validation';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'SOVEREIGN LOCK: 95% required',
            style: MehdAiTheme.priceStyle.copyWith(color: MehdAiTheme.yellow, fontSize: 12, fontWeight: FontWeight.bold),
          ),
          Text(
            'Current: $scoreText% — Waiting: $waitReason\nSENTINEL: Monitoring...',
            style: MehdAiTheme.labelStyle.copyWith(fontSize: 9, color: MehdAiTheme.yellow.withOpacity(0.8), height: 1.2),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    }

    // Civilian or Operative Status
    Widget scoreWidget = Column(
      key: ValueKey('score_${scoreText}_${consensus!.proceed}'),
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          'Den Score: $scoreText% — ${consensus!.proceed ? 'PROCEED' : 'WAIT'}',
          style: MehdAiTheme.priceStyle.copyWith(
            color: color, 
            fontSize: 16, 
            fontWeight: FontWeight.bold,
            shadows: (isBuy && consensus!.proceed) ? MehdAiTheme.textGlowGreen : ((isSell && consensus!.proceed) ? MehdAiTheme.textGlowRed : []),
          ),
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          '$count/$total agents | ${consensus!.tier.toUpperCase()}',
          style: MehdAiTheme.labelStyle.copyWith(fontSize: 11),
        ),
      ],
    );

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, animation) => FadeTransition(opacity: animation, child: child),
      child: scoreWidget,
    );
  }

  Widget _buildRiskPill(BuildContext context) {
    final settings = Provider.of<SettingsService>(context, listen: true);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: MehdAiTheme.bgSecondary,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: MehdAiTheme.borderColor),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.shield, size: 14, color: MehdAiTheme.purple),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              'Risk Cap: ${settings.riskPerTrade.toStringAsFixed(1)}%', 
              overflow: TextOverflow.ellipsis,
              style: MehdAiTheme.labelStyle.copyWith(
                fontSize: 10,
                color: MehdAiTheme.textPrimary,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTradeButton() {
    Color bgColor;
    Color borderColor;
    String text;
    bool enabled = false;
    Widget? icon;
    bool isSovereignLock = false;

    // I6: Spread safety override — return early so the switch doesn't overwrite
    if (currentSpread > 3.0 && (buttonState == ButtonState.readyBuy || buttonState == ButtonState.readySell)) {
      bgColor = MehdAiTheme.red.withOpacity(0.05);
      borderColor = MehdAiTheme.red;
      text = '⚠ SPREAD TOO WIDE — ${currentSpread.toStringAsFixed(1)} pips';
      enabled = false;
      icon = const Icon(Icons.warning_amber_rounded, size: 16, color: MehdAiTheme.red);
    } else {
      switch (buttonState) {
        case ButtonState.locked:
          bgColor = MehdAiTheme.bgTertiary;
          borderColor = MehdAiTheme.borderColor;
          text = 'LOCKED — The Den is thinking';
          icon = const Icon(Icons.lock, size: 16, color: MehdAiTheme.textSecondary);
          break;
        case ButtonState.developing:
          bgColor = MehdAiTheme.yellow.withOpacity(0.1);
          borderColor = MehdAiTheme.yellow;
          text = '6/11 — Trend Forming. Monitoring...';
          enabled = false;
          icon = const Icon(Icons.sync, size: 16, color: MehdAiTheme.yellow);
          break;
        case ButtonState.vetoed:
          bgColor = MehdAiTheme.bgTertiary;
          borderColor = MehdAiTheme.borderColor;
          text = 'Math Layer Veto — Market unsafe';
          enabled = false;
          icon = const Icon(Icons.block, size: 16, color: MehdAiTheme.textSecondary);
          break;
        case ButtonState.readyBuy:
          bgColor = MehdAiTheme.green.withOpacity(0.1);
          borderColor = MehdAiTheme.green;
          text = 'PAPER TRADE ONLY — BUY';
          enabled = true;
          break;
        case ButtonState.readySell:
          bgColor = MehdAiTheme.red.withOpacity(0.1);
          borderColor = MehdAiTheme.red;
          text = 'PAPER TRADE ONLY — SELL';
          enabled = true;
          break;
        case ButtonState.executing:
          bgColor = MehdAiTheme.blue.withOpacity(0.1);
          borderColor = MehdAiTheme.blue;
          text = 'EXECUTING...';
          enabled = false;
          icon = SizedBox(
            width: 14, height: 14,
            child: Opacity(opacity: 0.5, child: Image.asset('assets/images/mehd_logo.png')),
          );
          break;
        case ButtonState.filled:
          bgColor = MehdAiTheme.green.withOpacity(0.2);
          borderColor = MehdAiTheme.green;
          text = 'ORDER FILLED';
          enabled = false;
          icon = const Icon(Icons.check, size: 16, color: MehdAiTheme.green);
          break;
      }

      isSovereignLock = consensus?.tier == 'sovereign' && consensus?.proceed == true;
      if (isSovereignLock && (buttonState == ButtonState.readyBuy || buttonState == ButtonState.readySell)) {
        bgColor = MehdAiTheme.white.withOpacity(0.15);
        borderColor = MehdAiTheme.white;
        text = 'SOVEREIGN EXECUTE — ${consensus!.finalDirection}';
        icon = const Icon(Icons.bolt, size: 16, color: MehdAiTheme.white);
      }
    }

    if ((buttonState == ButtonState.readyBuy || buttonState == ButtonState.readySell) && enabled) {
      return SwipeToExecuteBtn(
        onExecute: onTradePressed,
        text: text,
        baseColor: borderColor,
      );
    }

    return _BouncingTradeButton(
      onTap: enabled ? onTradePressed : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        height: 44,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: borderColor),
          boxShadow: enabled 
            ? [
                BoxShadow(
                  color: isSovereignLock 
                      ? MehdAiTheme.white.withOpacity(0.12) 
                      : (buttonState == ButtonState.readyBuy ? MehdAiTheme.green.withOpacity(0.12) : MehdAiTheme.red.withOpacity(0.12)),
                  blurRadius: 20,
                  offset: const Offset(0, 4)),
                BoxShadow(
                  color: Colors.black.withOpacity(0.4),
                  blurRadius: 8,
                  offset: const Offset(0, 2)),
              ] 
            : [],
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (icon != null) ...[icon, const SizedBox(width: 8)],
              Flexible(
                child: Text(
                  text,
                  overflow: TextOverflow.ellipsis,
                  style: MehdAiTheme.headingStyle.copyWith(
                    fontSize: 13,
                    color: enabled ? borderColor : MehdAiTheme.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BouncingTradeButton extends StatefulWidget {
  final VoidCallback? onTap;
  final Widget child;
  const _BouncingTradeButton({required this.onTap, required this.child});
  @override
  State<_BouncingTradeButton> createState() => _BouncingTradeButtonState();
}

class _BouncingTradeButtonState extends State<_BouncingTradeButton> {
  bool _isPressed = false;
  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: widget.onTap != null ? (_) => setState(() => _isPressed = true) : null,
      onTapUp: widget.onTap != null ? (_) { setState(() => _isPressed = false); widget.onTap!(); } : null,
      onTapCancel: () => setState(() => _isPressed = false),
      child: AnimatedScale(
        scale: _isPressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: widget.child,
      ),
    );
  }
}
