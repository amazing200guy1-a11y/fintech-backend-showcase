import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:intl/intl.dart';
import 'dart:ui';
import 'package:mehd_ai_flutter/widgets/mehd_mascot.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mehd_ai_flutter/services/settings_service.dart';

/// FILE — rejection_feed_screen.dart
/// UPGRADE 4: Live Rejection Feed (Connected to Firestore)
/// A high-impact screen showing exactly what The Den protected the user from.

class RejectionFeedScreen extends StatefulWidget {
  const RejectionFeedScreen({super.key});

  @override
  State<RejectionFeedScreen> createState() => _RejectionFeedScreenState();
}

class _RejectionFeedScreenState extends State<RejectionFeedScreen> with SingleTickerProviderStateMixin {
  late AnimationController _shieldPulse;
  late String _uid;

  @override
  void initState() {
    super.initState();
    _uid = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    _shieldPulse = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _shieldPulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_uid == 'guest') {
      return const Scaffold(
        backgroundColor: MehdAiTheme.bgPrimary,
        body: Center(child: Text("Please sign in to view your rejection feed", style: TextStyle(color: Colors.white))),
      );
    }

    return Scaffold(
      backgroundColor: MehdAiTheme.bgPrimary,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('REJECTION & PROTECT FEED', style: MehdAiTheme.headingStyle.copyWith(letterSpacing: 2)),
        backgroundColor: MehdAiTheme.bgSecondary,
        iconTheme: const IconThemeData(color: MehdAiTheme.textPrimary),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: MehdAiTheme.borderColor, height: 1),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('user_profiles')
            .doc(_uid)
            .collection('rejection_feed')
            .orderBy('timestamp', descending: true)
            .limit(50) // Cost cap: max 50 reads per open — not unbounded
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: MehdAiTheme.shieldColor));
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.cloud_off_rounded, color: MehdAiTheme.shieldColor, size: 48),
                  const SizedBox(height: 16),
                  Text('Could not load rejection feed.', style: MehdAiTheme.headingStyle.copyWith(color: MehdAiTheme.shieldColor)),
                  const SizedBox(height: 8),
                  Text('Offline or permissions error.', style: MehdAiTheme.labelStyle.copyWith(color: MehdAiTheme.textSecondary)),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: () => setState(() {}),
                    child: Text('RETRY', style: MehdAiTheme.terminalStyle),
                  ),
                ],
              ),
            );
          }

          final docs = snapshot.data?.docs ?? [];
          
          double totalSaved = 0.0;
          final List<Map<String, dynamic>> rejections = [];
          
          for (var doc in docs) {
            final data = doc.data() as Map<String, dynamic>;
            final saved = (data['saved_amount'] ?? 0.0).toDouble();
            totalSaved += saved;
            
            DateTime parsedTime;
            try {
              final rawTs = data['timestamp'];
              if (rawTs is String) {
                parsedTime = DateTime.parse(rawTs);
              } else if (rawTs != null) {
                // Firestore Timestamp object — convert to DateTime
                parsedTime = (rawTs as dynamic).toDate() as DateTime;
              } else {
                parsedTime = DateTime.now();
              }
            } catch (e) {
              parsedTime = DateTime.now();
            }

            rejections.add({
              'symbol': data['symbol'] ?? 'UNKNOWN',
              'direction': data['direction'] ?? 'UNKNOWN',
              'reason': data['reason'] ?? 'Vetoed by Risk Engine',
              'details': 'The Den intercepted this trade. Risk parameters exceeded institutional thresholds.',
              'time': parsedTime,
              'agents_vetoed': data['vetoing_agents'] ?? ['KERNEL'],
              'saved_amount': saved,
            });
          }

          return Stack(
            children: [
              // Background ambient pulse
              Positioned(
                top: -100,
                left: -100,
                child: Center(
                  child: AnimatedBuilder(
                    animation: _shieldPulse,
                    builder: (_, __) => Container(
                      width: 250 + (_shieldPulse.value * 30),
                      height: 250 + (_shieldPulse.value * 30),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: RadialGradient(
                          colors: [MehdAiTheme.shieldColor.withOpacity(0.08), Colors.transparent],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Column(
                children: [
                  _buildStatsHeader(totalSaved, rejections.length),
                  const Divider(height: 1, color: MehdAiTheme.borderColor),
                  Expanded(
                    child: rejections.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.shield_rounded, size: 64, color: MehdAiTheme.shieldColor),
                                const SizedBox(height: 16),
                                Text("No trades blocked yet.", style: MehdAiTheme.headingStyle.copyWith(color: MehdAiTheme.shieldColor)),
                                const SizedBox(height: 8),
                                Text("The Den is actively monitoring.", style: MehdAiTheme.labelStyle.copyWith(color: MehdAiTheme.textSecondary)),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                            itemCount: rejections.length,
                            itemBuilder: (context, index) {
                              return _buildRejectionCard(context, rejections[index]);
                            },
                          ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildStatsHeader(double totalSaved, int rejectedCount) {
    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [MehdAiTheme.bgSecondary, MehdAiTheme.bgPrimary],
            ),
          ),
          child: Column(
            children: [
              // MehdMascot active Alert/Protection pose!
              MehdMascot(
                isWorking: false,
                size: 120,
              ),
              const SizedBox(height: 16),
              Text(
                'CAPITAL PRESERVED',
                style: GoogleFonts.jetBrainsMono(
                  color: MehdAiTheme.shieldColor,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  '\$${totalSaved.toStringAsFixed(2)}+',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 42,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Glassmorphic counters row
              LayoutBuilder(
                builder: (context, constraints) {
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildCounter('Trades Blocked', rejectedCount, MehdAiTheme.red),
                    ],
                  );
                },
              ),
              const SizedBox(height: 12),
              Text(
                'The Den actively prevented ruin across $rejectedCount trades.',
                textAlign: TextAlign.center,
                style: MehdAiTheme.labelStyle.copyWith(color: MehdAiTheme.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCounter(String label, int value, Color color) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 32),
          decoration: BoxDecoration(
            color: color.withOpacity(0.06),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withOpacity(0.15)),
          ),
          child: Column(
            children: [
              Text(
                value?.toString() ?? '0',
                style: GoogleFonts.outfit(
                  color: color,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: MehdAiTheme.labelStyle.copyWith(
                  fontSize: 10,
                  color: MehdAiTheme.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRejectionCard(BuildContext context, Map<String, dynamic> rejection) {
    final showAgentNames = context.watch<SettingsService>().showAgentNames;

    final symbol = rejection['symbol'] as String;
    final reason = rejection['reason'] as String;
    final details = rejection['details'] as String;
    final direction = rejection['direction'] as String;
    final time = rejection['time'] as DateTime;
    final agents = List<String>.from(rejection['agents_vetoed'] as List);
    final saved = rejection['saved_amount'];

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: MehdAiTheme.red.withOpacity(0.04),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: MehdAiTheme.red.withOpacity(0.2)),
            boxShadow: [
              BoxShadow(color: MehdAiTheme.red.withOpacity(0.03), blurRadius: 15),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header Bar
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: MehdAiTheme.red.withOpacity(0.04),
                  border: const Border(bottom: BorderSide(color: MehdAiTheme.borderColor)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: MehdAiTheme.red.withOpacity(0.15),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.block, color: MehdAiTheme.red, size: 14),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              '$direction $symbol BLOCKED',
                              style: MehdAiTheme.terminalStyle.copyWith(color: MehdAiTheme.red, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      DateFormat('MMM d, HH:mm').format(time),
                      style: MehdAiTheme.labelStyle.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              // Body
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(reason, style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    Text(details, style: MehdAiTheme.labelStyle.copyWith(height: 1.5)),
                    if (saved != null && saved > 0) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: MehdAiTheme.green.withOpacity(0.08),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: MehdAiTheme.green.withOpacity(0.2)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.savings_outlined, color: MehdAiTheme.green, size: 14),
                            const SizedBox(width: 6),
                            Text('\$${(saved as num).toDouble().toStringAsFixed(2)} preserved', style: MehdAiTheme.terminalStyle.copyWith(color: MehdAiTheme.green, fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: agents.map((agent) {
                        // Mask agent name if showAgentNames is false
                        final displayName = showAgentNames 
                            ? (agent?.toString() ?? 'AGENT')
                            : 'AGENT #${(agent?.toString() ?? 'AGENT').hashCode.abs().toString().padLeft(4, '0').substring(0, 4)}';
                        return Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: MehdAiTheme.red.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: MehdAiTheme.red.withOpacity(0.2)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.close, size: 12, color: MehdAiTheme.red),
                              const SizedBox(width: 4),
                              Text(displayName, style: MehdAiTheme.terminalStyle.copyWith(fontSize: 10, color: MehdAiTheme.red, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
