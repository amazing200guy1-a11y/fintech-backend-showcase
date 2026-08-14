import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Rich execution brief card shown after a /long or /short command.
/// Core tier: displays entry/SL/TP + EXECUTE confirm button.
/// Precision/Institutional: shows auto-executed confirmation badge.
class CommandExecutionResult extends StatelessWidget {
  final Map<String, dynamic> brief;
  final VoidCallback? onExecute;   // null for Precision/Institutional (auto-executed)
  final VoidCallback? onDismiss;

  const CommandExecutionResult({
    super.key,
    required this.brief,
    this.onExecute,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final String symbol    = brief['symbol']    ?? '—';
    final String direction = brief['direction'] ?? '—';
    final double entry     = (brief['entry']    as num?)?.toDouble() ?? 0.0;
    final double sl        = (brief['sl']       as num?)?.toDouble() ?? 0.0;
    final double tp        = (brief['tp']       as num?)?.toDouble() ?? 0.0;
    final double lot       = (brief['suggested_lot'] as num?)?.toDouble() ?? 0.01;
    final String rr        = brief['risk_reward'] ?? '1:2.4';
    final String tier      = brief['tier']      ?? 'core';
    final bool autoExec    = brief['auto_execute'] == true;
    final bool donAlert    = brief['don_alert']    == true;
    final String mode      = brief['execution_mode'] ?? 'sandbox';

    final isBuy = direction == 'BUY';
    final dirColor  = isBuy ? const Color(0xFF00E5A0) : const Color(0xFFFF4C4C);
    final dirIcon   = isBuy ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded;
    final tierLabel = _tierLabel(tier);
    final tierColor = _tierColor(tier);

    // Decimal precision
    final bool isGold   = symbol.contains('XAU');
    final bool isCrypto = symbol.contains('BTC') || symbol.contains('ETH');
    final int decimals  = isCrypto ? 2 : (isGold ? 2 : 5);
    String fmt(double v) => v.toStringAsFixed(decimals);

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: dirColor.withOpacity(0.35), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: dirColor.withOpacity(0.08),
            blurRadius: 24,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header bar ──────────────────────────────────────────
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: dirColor.withOpacity(0.08),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              children: [
                Icon(dirIcon, color: dirColor, size: 18),
                const SizedBox(width: 8),
                Text(
                  '$symbol  $direction',
                  style: GoogleFonts.orbitron(
                    color: dirColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                  ),
                ),
                const Spacer(),
                // Tier badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: tierColor.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: tierColor.withOpacity(0.4), width: 0.8),
                  ),
                  child: Text(
                    tierLabel,
                    style: GoogleFonts.jetBrainsMono(
                      color: tierColor,
                      fontSize: 9,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2,
                    ),
                  ),
                ),
                if (autoExec) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFF00E5FF).withOpacity(0.1),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'AUTO-EXECUTED',
                      style: GoogleFonts.jetBrainsMono(
                        color: const Color(0xFF00E5FF),
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 1.0,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),

          // ── Level grid ──────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(child: _LevelCell(label: 'ENTRY', value: fmt(entry), color: Colors.white)),
                const SizedBox(width: 8),
                Expanded(child: _LevelCell(label: 'STOP LOSS', value: fmt(sl), color: const Color(0xFFFF4C4C))),
                const SizedBox(width: 8),
                Expanded(child: _LevelCell(label: 'TAKE PROFIT', value: fmt(tp), color: const Color(0xFF00E5A0))),
              ],
            ),
          ),

          // ── Details row ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(left: 14, right: 14, bottom: 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _DetailChip(label: 'LOT', value: lot.toStringAsFixed(2)),
                _DetailChip(label: 'RR', value: rr),
                _DetailChip(
                  label: 'EXEC',
                  value: (brief['automation_mode'] ?? (autoExec ? (donAlert ? 'fully-automated' : 'semi-automated') : 'manual')).toString().toUpperCase(),
                  valueColor: autoExec ? (donAlert ? const Color(0xFFFFD700) : const Color(0xFF00E5FF)) : const Color(0xFF00E5A0),
                ),
                _DetailChip(
                  label: 'ENV',
                  value: mode.toUpperCase(),
                  valueColor: mode == 'live' ? const Color(0xFF00E5A0) : const Color(0xFFFFA500),
                ),
                if (donAlert)
                  const _DetailChip(
                    label: 'DON',
                    value: 'DISPATCHED',
                    valueColor: Color(0xFFFFD700),
                  ),
              ],
            ),
          ),


          // ── Action row (Core only) ───────────────────────────────
          if (!autoExec && onExecute != null)
            Padding(
              padding: const EdgeInsets.only(left: 14, right: 14, bottom: 14),
              child: Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: onExecute,
                      child: Container(
                        height: 42,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [dirColor.withOpacity(0.8), dirColor],
                          ),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Center(
                          child: Text(
                            '⚡  EXECUTE TRADE',
                            style: GoogleFonts.orbitron(
                              color: Colors.black,
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: onDismiss,
                    child: Container(
                      height: 42,
                      width: 80,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white.withOpacity(0.1)),
                      ),
                      child: Center(
                        child: Text(
                          'CANCEL',
                          style: GoogleFonts.jetBrainsMono(
                            color: Colors.white38,
                            fontSize: 10,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _tierLabel(String tier) {
    switch (tier) {
      case 'precision':     return 'PRECISION · \$149';
      case 'institutional': return 'SOVEREIGN · \$299';
      default:              return 'CORE · \$79';
    }
  }

  Color _tierColor(String tier) {
    switch (tier) {
      case 'precision':     return const Color(0xFF58A6FF);
      case 'institutional': return const Color(0xFFFFD700);
      default:              return const Color(0xFF00E5A0);
    }
  }
}

class _LevelCell extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  const _LevelCell({required this.label, required this.value, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2), width: 0.8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: GoogleFonts.jetBrainsMono(color: Colors.white38, fontSize: 8, letterSpacing: 1.1)),
          const SizedBox(height: 4),
          Text(value, style: GoogleFonts.jetBrainsMono(color: color, fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

class _DetailChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  const _DetailChip({required this.label, required this.value, this.valueColor});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label  ', style: GoogleFonts.jetBrainsMono(color: Colors.white38, fontSize: 9)),
          Text(value, style: GoogleFonts.jetBrainsMono(
            color: valueColor ?? Colors.white70,
            fontSize: 9,
            fontWeight: FontWeight.w700,
          )),
        ],
      ),
    );
  }
}
