import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mehd_ai_flutter/core/theme.dart';

/// The bottom input bar for Pulse Trading Screen.
/// Contains: quick-prompt chips, command suggestions overlay, text field, send button.
class PulseInputArea extends StatelessWidget {
  final TextEditingController inputController;
  final List<Map<String, dynamic>> quickPrompts;
  final bool showCommandSuggestions;
  final VoidCallback onSubmit;
  final ValueChanged<String> onOverrideSubmit;
  final VoidCallback onHideSuggestions;
  final VoidCallback onToggleSuggestions;

  const PulseInputArea({
    super.key,
    required this.inputController,
    required this.quickPrompts,
    required this.showCommandSuggestions,
    required this.onSubmit,
    required this.onOverrideSubmit,
    required this.onHideSuggestions,
    required this.onToggleSuggestions,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: MehdAiTheme.bgPrimary,
        border: Border(top: BorderSide(color: MehdAiTheme.borderColor)),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // ── COMMAND SUGGESTIONS — floats ABOVE the input bar ──────────────
          if (showCommandSuggestions)
            Positioned(
              bottom: 90, // clears the chips + text field height
              left: 0,
              right: 0,
              child: _PulseCommandSuggestions(
                onHide: onHideSuggestions,
                onAutoSubmit: (cmd) {
                  onHideSuggestions();
                  onOverrideSubmit(cmd);
                },
                onFillInput: (cmd) {
                  inputController.text = '$cmd ';
                  inputController.selection = TextSelection.fromPosition(
                      TextPosition(offset: inputController.text.length));
                  onHideSuggestions();
                },
              ),
            ),

          // ── BOTTOM INPUT BAR ───────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Quick prompt chips
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: quickPrompts.map((item) {
                      final String label = item['text'] as String;
                      final String cmd = item['command'] as String;
                      final IconData icon = item['icon'] as IconData;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: InkWell(
                          onTap: () => onOverrideSubmit(cmd),
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              color: const Color(0xFF161B22),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                  color: const Color(0xFF21262D)),
                              boxShadow: [
                                BoxShadow(
                                    color: Colors.black.withOpacity(0.3),
                                    blurRadius: 6,
                                    offset: const Offset(0, 2)),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(icon,
                                    color: const Color(0xFF58A6FF),
                                    size: 13),
                                const SizedBox(width: 6),
                                Text(
                                  label,
                                  style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),

                // Text field + send button
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: inputController,
                        onSubmitted: (_) => onSubmit(),
                        style: MehdAiTheme.terminalStyle,
                        decoration: InputDecoration(
                          hintText:
                              'Enter command (e.g. /long EURUSD) or tap cockpit controls above...',
                          hintStyle: MehdAiTheme.terminalStyle.copyWith(
                            color:
                                MehdAiTheme.textSecondary.withOpacity(0.4),
                          ),
                          filled: true,
                          fillColor: MehdAiTheme.bgSecondary,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 16),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: MehdAiTheme.blue, width: 1),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: MehdAiTheme.blue.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: MehdAiTheme.blue.withOpacity(0.4)),
                      ),
                      child: IconButton(
                        icon: const Icon(Icons.send_rounded,
                            color: MehdAiTheme.blue),
                        onPressed: onSubmit,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ─── Command Suggestions Overlay ───────────────────────────────────────────
class _PulseCommandSuggestions extends StatelessWidget {
  final VoidCallback onHide;
  final ValueChanged<String> onAutoSubmit;
  final ValueChanged<String> onFillInput;

  const _PulseCommandSuggestions({
    required this.onHide,
    required this.onAutoSubmit,
    required this.onFillInput,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      constraints: const BoxConstraints(maxHeight: 280),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: const Color(0xFF58A6FF).withOpacity(0.4)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.5),
              blurRadius: 20,
              offset: const Offset(0, -4)),
          BoxShadow(
              color: const Color(0xFF58A6FF).withOpacity(0.1),
              blurRadius: 10),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              border:
                  Border(bottom: BorderSide(color: Color(0xFF21262D))),
            ),
            child: Row(
              children: [
                const Icon(Icons.terminal_rounded,
                    color: Color(0xFF58A6FF), size: 14),
                const SizedBox(width: 8),
                Text('COMMANDS',
                    style: GoogleFonts.outfit(
                        color: const Color(0xFF58A6FF),
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1)),
                const Spacer(),
                GestureDetector(
                  onTap: onHide,
                  child: const Icon(Icons.close,
                      color: Color(0xFF52525B), size: 16),
                ),
              ],
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _item('/nuke', 'Emergency Panic Switch', 'Close all open trades immediately', Icons.power_settings_new_rounded, const Color(0xFFFF3B3B), autoSubmit: true),
                  _item('/bank50', 'Lock 50% Profit', 'Bank half your profit in cash right now', Icons.pie_chart_outline_rounded, const Color(0xFF00FF88), autoSubmit: true),
                  _item('/be', 'Risk-Free Mode', 'Move stop loss to entry price so you cannot lose', Icons.shield_outlined, const Color(0xFF58A6FF), autoSubmit: true),
                  _item('/risk', '+ % e.g. /risk 2', 'Auto-calculate exact lot size & stop loss', Icons.tune_rounded, const Color(0xFFE8C44A), autoSubmit: false),
                  _item('/trail', '+ pips e.g. /trail 20', 'Auto-Follow Profit: Move SL up as price climbs', Icons.trending_up_rounded, const Color(0xFF00FF88), autoSubmit: false),
                  _item('/shield', 'Loss Guard (3% Max)', 'Stop revenge trading with 24h lockout', Icons.shield_rounded, const Color(0xFF58A6FF), autoSubmit: true),
                  _item('/long', '+ SYMBOL e.g. /long XAUUSD', 'Open a buy position', Icons.trending_up, const Color(0xFF00FF88), autoSubmit: false),
                  _item('/short', '+ SYMBOL e.g. /short EURUSD', 'Open a sell position', Icons.trending_down, const Color(0xFFFF3B3B), autoSubmit: false),
                  _item('/close', '+ SYMBOL e.g. /close EURUSD', 'Close a specific trade', Icons.close_fullscreen, const Color(0xFFE8C44A), autoSubmit: false),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _item(String cmd, String params, String desc, IconData icon, Color color, {required bool autoSubmit}) {
    return InkWell(
      onTap: () => autoSubmit ? onAutoSubmit(cmd) : onFillInput(cmd),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: Color(0xFF21262D), width: 0.5)),
        ),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Icon(icon, color: color, size: 14),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(cmd, style: GoogleFonts.jetBrainsMono(color: color, fontSize: 13, fontWeight: FontWeight.bold)),
                      if (autoSubmit) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(3)),
                          child: Text('1-TAP', style: GoogleFonts.outfit(color: color, fontSize: 8, fontWeight: FontWeight.bold, letterSpacing: 0.8)),
                        ),
                      ] else ...[
                        const SizedBox(width: 6),
                        Text(params, style: GoogleFonts.inter(color: const Color(0xFF71717A), fontSize: 10)),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(desc, style: GoogleFonts.inter(color: const Color(0xFF71717A), fontSize: 10)),
                ],
              ),
            ),
            Icon(autoSubmit ? Icons.bolt_rounded : Icons.keyboard_rounded, color: const Color(0xFF52525B), size: 14),
          ],
        ),
      ),
    );
  }
}
