import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mehd_ai_flutter/core/theme.dart';

class HistoryDecisionsTab extends StatelessWidget {
  final String? uid;
  final List<Map<String, dynamic>> seedDecisions;
  final Widget Function(String title, String subtitle) emptyStateBuilder;

  const HistoryDecisionsTab({
    super.key,
    required this.uid,
    required this.seedDecisions,
    required this.emptyStateBuilder,
  });

  @override
  Widget build(BuildContext context) {
    if (uid == null) {
      return _buildList(seedDecisions);
    }

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('consensus_history')
          .orderBy('timestamp', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        List<Map<String, dynamic>> decisions = seedDecisions;
        if (snapshot.hasData && snapshot.data!.docs.isNotEmpty) {
          decisions = snapshot.data!.docs
              .map((doc) => doc.data() as Map<String, dynamic>)
              .toList();
        }
        return _buildList(decisions);
      },
    );
  }

  Widget _buildList(List<Map<String, dynamic>> decisions) {
    if (decisions.isEmpty) {
      return emptyStateBuilder(
          'NO DECISIONS LOGGED', 'Consensus telemetry reports will render here');
    }

    return ListView.builder(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      itemCount: decisions.length,
      itemBuilder: (ctx, i) {
        final d = decisions[i];
        final consensus = (d['consensus_percentage'] as num?)?.toDouble() ?? 0;
        final proceed = d['proceed'] as bool? ?? false;
        final themeColor = proceed ? MehdAiTheme.green : MehdAiTheme.red;

        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: themeColor.withOpacity(0.02),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: themeColor.withOpacity(0.12)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: themeColor.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: themeColor.withOpacity(0.2)),
                    ),
                    child: Icon(
                      proceed
                          ? Icons.verified_user_outlined
                          : Icons.gpp_bad_outlined,
                      color: themeColor,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              d['symbol'] ?? 'N/A',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: themeColor.withOpacity(0.08),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                    color: themeColor.withOpacity(0.2)),
                              ),
                              child: Text(
                                proceed ? 'PASSED' : 'BLOCKED',
                                style: GoogleFonts.jetBrainsMono(
                                  color: themeColor,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          d['reason'] ?? d['date'] ?? 'Consensus evaluated',
                          style: MehdAiTheme.labelStyle.copyWith(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'CONSENSUS',
                        style: MehdAiTheme.labelStyle
                            .copyWith(fontSize: 9, letterSpacing: 0.5),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${consensus.toStringAsFixed(0)}%',
                        style: GoogleFonts.jetBrainsMono(
                          color: proceed
                              ? MehdAiTheme.green
                              : MehdAiTheme.yellow,
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
