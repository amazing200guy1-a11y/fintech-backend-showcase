import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/models/consensus_result.dart';
import 'package:mehd_ai_flutter/widgets/den_verdict_card.dart';
import 'package:mehd_ai_flutter/widgets/command_execution_result.dart';

/// A single chat message model for Pulse Trading Screen.
class PulseChatMessage {
  final String text;
  final bool isUser;
  final bool isStreaming;
  final ConsensusResult? consensusWidget;
  /// Execution brief from /long or /short command (shows CommandExecutionResult card).
  final Map<String, dynamic>? executionBrief;
  /// Called when Core tier user taps EXECUTE on the command result card.
  final VoidCallback? onExecute;
  final VoidCallback? onDismissExecution;

  PulseChatMessage({
    required this.text,
    required this.isUser,
    this.isStreaming = false,
    this.consensusWidget,
    this.executionBrief,
    this.onExecute,
    this.onDismissExecution,
  });
}

/// Renders a single message bubble in the Pulse chat feed.
/// Handles both user messages (right-aligned, blue-tinted) and
/// AI messages (left-aligned, dark background).
class PulseMessageBubble extends StatelessWidget {
  final PulseChatMessage msg;

  const PulseMessageBubble({super.key, required this.msg});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            msg.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!msg.isUser) ...[
            _buildAvatar(false),
            const SizedBox(width: 14),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: msg.isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: msg.isUser
                        ? MehdAiTheme.blue.withOpacity(0.12)
                        : const Color(0xFF0D1117),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: msg.isUser
                          ? MehdAiTheme.blue.withOpacity(0.4)
                          : MehdAiTheme.borderColor,
                    ),
                    boxShadow: [
                      if (msg.isUser)
                        BoxShadow(
                            color: MehdAiTheme.blue.withOpacity(0.08),
                            blurRadius: 10),
                    ],
                  ),
                  child: Text(
                    msg.text + (msg.isStreaming ? ' ▋' : ''),
                    style: GoogleFonts.inter(
                      color: msg.isUser
                          ? Colors.white
                          : MehdAiTheme.textSecondary,
                      fontSize: 13,
                      height: 1.6,
                    ),
                  ),
                ),
                if (msg.consensusWidget != null) ...[
                  const SizedBox(height: 14),
                  DenVerdictCard(consensus: msg.consensusWidget!),
                ],
                if (msg.executionBrief != null) ...[
                  const SizedBox(height: 10),
                  CommandExecutionResult(
                    brief: msg.executionBrief!,
                    onExecute: msg.onExecute,
                    onDismiss: msg.onDismissExecution,
                  ),
                ]
              ],
            ),
          ),
          if (msg.isUser) ...[
            const SizedBox(width: 14),
            _buildAvatar(true),
          ],
        ],
      ),
    );
  }

  Widget _buildAvatar(bool isUser) {
    if (isUser) {
      return Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: MehdAiTheme.blue.withOpacity(0.15),
          shape: BoxShape.circle,
          border: Border.all(color: MehdAiTheme.blue.withOpacity(0.4)),
        ),
        child: const Icon(Icons.person, size: 16, color: MehdAiTheme.blue),
      );
    }
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        shape: BoxShape.circle,
        border: Border.all(color: MehdAiTheme.blue.withOpacity(0.6)),
        boxShadow: [
          BoxShadow(
              color: MehdAiTheme.blue.withOpacity(0.25), blurRadius: 8),
        ],
      ),
      child: ClipOval(
        child: Image.asset(
          'assets/images/mehd_logo.png',
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) =>
              const Icon(Icons.bolt_rounded, color: MehdAiTheme.blue, size: 18),
        ),
      ),
    );
  }
}
