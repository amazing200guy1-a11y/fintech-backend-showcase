import 'package:flutter/material.dart';
import 'package:mehd_ai_flutter/models/consensus_result.dart';

class ChatMessage {
  String text;
  final bool isUser;
  final DateTime timestamp;
  bool isStreaming;
  ConsensusResult? consensusWidget;
  Map<String, dynamic>? executionBrief;
  VoidCallback? onExecute;
  VoidCallback? onDismissExecution;

  ChatMessage({
    required this.text,
    required this.isUser,
    DateTime? timestamp,
    this.isStreaming = false,
    this.consensusWidget,
    this.executionBrief,
    this.onExecute,
    this.onDismissExecution,
  }) : timestamp = timestamp ?? DateTime.now();
}

class PulseTypingIndicator extends StatelessWidget {
  const PulseTypingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFF161B22),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF30363D)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF58A6FF)),
                ),
                SizedBox(width: 10),
                Text('Thinking...', style: TextStyle(color: Color(0xFF8B949E), fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SyntaxHighlightController extends TextEditingController {
  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final text = this.text;
    final spans = <TextSpan>[];

    final words = text.split(' ');
    for (int i = 0; i < words.length; i++) {
      final word = words[i];
      final upper = word.toUpperCase();
      Color? wordColor;

      if (['BUY', 'LONG', 'BULLISH', 'CALL'].contains(upper)) {
        wordColor = const Color(0xFF00FF88);
      } else if (['SELL', 'SHORT', 'BEARISH', 'PUT'].contains(upper)) {
        wordColor = const Color(0xFFFF3B3B);
      } else if (['EURUSD', 'GBPUSD', 'USDJPY', 'XAUUSD', 'BTCUSD'].contains(upper)) {
        wordColor = const Color(0xFF58A6FF);
      } else if (word.startsWith('\$') || word.startsWith('%')) {
        wordColor = const Color(0xFFFFD700);
      }

      spans.add(TextSpan(
        text: word + (i < words.length - 1 ? ' ' : ''),
        style: wordColor != null ? style?.copyWith(color: wordColor, fontWeight: FontWeight.bold) : style,
      ));
    }

    return TextSpan(style: style, children: spans);
  }
}
