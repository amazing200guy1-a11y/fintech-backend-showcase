import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/widgets/blueprint_helpers.dart';

/// Shows node details modal sheet.
void showBlueprintNodeDetails(BuildContext context, BlueprintNode node) {
  HapticFeedback.lightImpact();
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withOpacity(0.6),
    isScrollControlled: true,
    builder: (context) {
      return Container(
        padding: EdgeInsets.only(
            left: 24,
            right: 24,
            top: 32,
            bottom: 24 + MediaQuery.of(context).padding.bottom),
        decoration: BoxDecoration(
            color: const Color(0xFF020306).withOpacity(0.95),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
            border: Border(top: BorderSide(color: node.color.withOpacity(0.3), width: 1.5)),
            boxShadow: [BoxShadow(color: node.color.withOpacity(0.1), blurRadius: 40, offset: const Offset(0, -10))]),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Container(
                width: 50, height: 50,
                decoration: BoxDecoration(
                  color: node.color.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: Border.all(color: node.color.withOpacity(0.3)),
                ),
                child: Icon(node.icon, color: node.color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(node.title.toUpperCase(), style: MehdAiTheme.headingStyle.copyWith(color: Colors.white, fontSize: 18, letterSpacing: 2)),
                const SizedBox(height: 4),
                Text(node.subtitle, style: MehdAiTheme.terminalStyle.copyWith(color: node.color.withOpacity(0.8), fontSize: 12)),
              ])),
            ]),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.02),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.05)),
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('> DECRYPTING NODE DATA...', style: MehdAiTheme.terminalStyle.copyWith(color: Colors.grey, fontSize: 10)),
                const SizedBox(height: 12),
                TypewriterText(
                  text: node.description,
                  style: MehdAiTheme.bodyStyle.copyWith(color: Colors.white.withOpacity(0.9), fontSize: 14, height: 1.6),
                  typingSpeed: const Duration(milliseconds: 15),
                ),
              ]),
            ),
            const SizedBox(height: 32),
            if (node.routeBuilder != null) ...[
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: node.color.withOpacity(0.2),
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 0,
                  ),
                  onPressed: () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: node.routeBuilder!));
                  },
                  child: Text('ENTER ${node.title.toUpperCase()}',
                      style: MehdAiTheme.terminalStyle.copyWith(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 2.0, fontSize: 14)),
                ),
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: node.routeBuilder != null ? Colors.transparent : node.color.withOpacity(0.1),
                  side: BorderSide(color: node.color.withOpacity(0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  elevation: 0,
                ),
                onPressed: () => Navigator.pop(context),
                child: Text('CLOSE DIAGNOSTICS',
                    style: MehdAiTheme.terminalStyle.copyWith(color: node.color, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              ),
            ),
          ],
        ),
      );
    },
  );
}
