import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mehd_ai_flutter/core/theme.dart';

class WarRoomCommunityScreen extends StatefulWidget {
  final bool showBack;
  const WarRoomCommunityScreen({super.key, this.showBack = false});

  @override
  State<WarRoomCommunityScreen> createState() => _WarRoomCommunityScreenState();
}

class _WarRoomCommunityScreenState extends State<WarRoomCommunityScreen> {
  final ScrollController _chatScroll = ScrollController();
  final List<Map<String, dynamic>> _chatFeed = [];
  Timer? _feedTimer;
  StreamSubscription<QuerySnapshot>? _firestoreSub;
  final Random _rand = Random();

  @override
  void initState() {
    super.initState();
    // 1. Pre-populate initial feed history
    for (int i = 0; i < 15; i++) {
      _addFeedItem();
    }

    // 2. Stream live Firestore community signals if available
    try {
      _firestoreSub = FirebaseFirestore.instance
          .collection('community_feed')
          .orderBy('timestamp', descending: true)
          .limit(30)
          .snapshots()
          .listen((snapshot) {
        if (!mounted || snapshot.docs.isEmpty) return;
        setState(() {
          for (var doc in snapshot.docs.reversed) {
            final data = doc.data();
            final user = data['user'] ?? data['trader'] ?? 'QuantNode';
            final pair = data['pair'] ?? data['symbol'] ?? 'EUR/USD';
            final direction = data['direction'] ?? 'BUY';
            final alignment = (data['alignment'] ?? 92).toInt();
            final ts = data['time'] ?? '${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}';
            
            _chatFeed.add({
              'time': ts,
              'user': user,
              'pair': pair,
              'direction': direction,
              'alignment': alignment,
            });
          }
          if (_chatFeed.length > 60) {
            _chatFeed.removeRange(0, _chatFeed.length - 60);
          }
        });
      }, onError: (e) {
        debugPrint("CommunityScreen: Firestore error (using seed fallback): $e");
      });
    } catch (e) {
      debugPrint("CommunityScreen: Firestore init error: $e");
    }

    // 3. Fallback simulation timer when offline/before live events
    _feedTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted) return;
      setState(() {
        _addFeedItem();
        if (_chatFeed.length > 50) _chatFeed.removeAt(0);
      });
      Future.delayed(const Duration(milliseconds: 100), () {
        if (_chatScroll.hasClients) {
          _chatScroll.animateTo(
            _chatScroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  void _addFeedItem() {
    final names = ['Don77', 'AlphaHunt', 'QuantNode', 'Zeta99', 'MacroKing', 'SniperX'];
    final pairs = ['EUR/USD', 'XAU/USD', 'GBP/JPY', 'BTC/USD', 'AAPL'];
    final dirs = ['BUY', 'SELL'];
    
    _chatFeed.add({
      'time': '${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}:${DateTime.now().second.toString().padLeft(2, '0')}',
      'user': names[_rand.nextInt(names.length)],
      'pair': pairs[_rand.nextInt(pairs.length)],
      'direction': dirs[_rand.nextInt(dirs.length)],
      'alignment': 85 + _rand.nextInt(15), // 85-99%
    });
  }

  @override
  void dispose() {
    _feedTimer?.cancel();
    _firestoreSub?.cancel();
    _chatScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MehdAiTheme.bgPrimary,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: widget.showBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: MehdAiTheme.textPrimary, size: 18),
                onPressed: () => Navigator.of(context).pop(),
              )
            : null,

        title: Text('SOVEREIGN COMMUNITY', style: MehdAiTheme.headingStyle.copyWith(letterSpacing: 2)),
        backgroundColor: MehdAiTheme.bgSecondary,
        iconTheme: const IconThemeData(color: MehdAiTheme.textPrimary),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: MehdAiTheme.borderColor, height: 1),
        ),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < 800;
          if (isMobile) {
            // MOBILE: Single scrollable column
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSentimentHeatmap(),
                  const SizedBox(height: 24),
                  Text('CONSENSUS FEED (LIVE)', style: MehdAiTheme.headingStyle.copyWith(color: MehdAiTheme.gold)),
                  const SizedBox(height: 12),
                  _buildConsensusChat(),
                  const SizedBox(height: 24),
                  _buildLeaderboard(),
                  const SizedBox(height: 24),
                  _buildWoundHealingHospital(),
                ],
              ),
            );
          }
          // DESKTOP: Side-by-side layout
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 6,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSentimentHeatmap(),
                      const SizedBox(height: 32),
                      Text('CONSENSUS FEED (LIVE)', style: MehdAiTheme.headingStyle.copyWith(color: MehdAiTheme.gold)),
                      const SizedBox(height: 16),
                      _buildConsensusChat(),
                    ],
                  ),
                ),
              ),
              Container(width: 1, color: MehdAiTheme.borderColor),
              Expanded(
                flex: 4,
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildLeaderboard(),
                      const SizedBox(height: 32),
                      _buildWoundHealingHospital(),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSentimentHeatmap() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MehdAiTheme.bgSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MehdAiTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Flexible(
                child: Text('SENTIMENT HEATMAP (CROWD LOGIC)', style: MehdAiTheme.headingStyle, overflow: TextOverflow.ellipsis),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: MehdAiTheme.green.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                child: Text('82% EDGE', style: MehdAiTheme.labelStyle.copyWith(color: MehdAiTheme.green, fontWeight: FontWeight.bold, fontSize: 10)),
              ),
            ],
          ),
          const SizedBox(height: 24),
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < 500) {
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    SizedBox(width: (constraints.maxWidth - 10) / 2, child: _buildHeatmapBlock('XAU/USD', 88, MehdAiTheme.green)),
                    SizedBox(width: (constraints.maxWidth - 10) / 2, child: _buildHeatmapBlock('EUR/USD', 74, MehdAiTheme.green)),
                    SizedBox(width: (constraints.maxWidth - 10) / 2, child: _buildHeatmapBlock('GBP/JPY', 42, MehdAiTheme.red)),
                    SizedBox(width: (constraints.maxWidth - 10) / 2, child: _buildHeatmapBlock('BTC/USD', 95, MehdAiTheme.green)),
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(child: _buildHeatmapBlock('XAU/USD', 88, MehdAiTheme.green)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildHeatmapBlock('EUR/USD', 74, MehdAiTheme.green)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildHeatmapBlock('GBP/JPY', 42, MehdAiTheme.red)),
                  const SizedBox(width: 12),
                  Expanded(child: _buildHeatmapBlock('BTC/USD', 95, MehdAiTheme.green)),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHeatmapBlock(String symbol, int profitPercent, Color baseColor) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: baseColor.withOpacity(0.1 + (profitPercent / 200)), // dynamic opacity
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: baseColor.withOpacity(0.5)),
      ),
      child: Column(
        children: [
          FittedBox(fit: BoxFit.scaleDown, child: Text(symbol, style: MehdAiTheme.terminalStyle.copyWith(fontWeight: FontWeight.bold, fontSize: 16))),
          const SizedBox(height: 8),
          FittedBox(fit: BoxFit.scaleDown, child: Text('$profitPercent% IN PROFIT', style: MehdAiTheme.labelStyle.copyWith(color: baseColor, fontWeight: FontWeight.bold))),
        ],
      ),
    );
  }

  Widget _buildConsensusChat() {
    return Container(
      height: 480,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MehdAiTheme.borderColor),
      ),
      child: ListView.builder(
        controller: _chatScroll,
        itemCount: _chatFeed.length,
        itemBuilder: (context, index) {
          final item = _chatFeed[index];
          final dirColor = item['direction'] == 'BUY' ? MehdAiTheme.green : MehdAiTheme.red;
          return Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Wrap(
              spacing: 4,
              runSpacing: 2,
              children: [
                Text('[${item['time']}] ', style: MehdAiTheme.terminalStyle.copyWith(color: MehdAiTheme.textSecondary, fontSize: 13)),
                Text('${item['user']} ', style: MehdAiTheme.terminalStyle.copyWith(color: MehdAiTheme.blue, fontWeight: FontWeight.bold, fontSize: 13)),
                Text('executed ', style: MehdAiTheme.terminalStyle.copyWith(color: MehdAiTheme.textPrimary, fontSize: 13)),
                Text('${item['direction']} ', style: MehdAiTheme.terminalStyle.copyWith(color: dirColor, fontWeight: FontWeight.bold, fontSize: 13)),
                Text('on ${item['pair']} ', style: MehdAiTheme.terminalStyle.copyWith(color: MehdAiTheme.white, fontSize: 13)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(color: MehdAiTheme.gold.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                  child: Text('Den Alignment: ${item['alignment']}%', style: MehdAiTheme.terminalStyle.copyWith(color: MehdAiTheme.gold, fontSize: 11)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLeaderboard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MehdAiTheme.bgSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MehdAiTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium, color: MehdAiTheme.gold, size: 20),
              const SizedBox(width: 8),
              Text('ELITE TRAINERS (TOP 5)', style: MehdAiTheme.headingStyle.copyWith(color: MehdAiTheme.gold)),
            ],
          ),
          const SizedBox(height: 16),
          _buildLeaderboardRow(1, 'AlphaQuant', '99.8% Alignment', '+1,240 pips'),
          _buildLeaderboardRow(2, 'TradeSovereign', '99.1% Alignment', '+980 pips'),
          _buildLeaderboardRow(3, 'GhostProtocol', '98.5% Alignment', '+850 pips'),
          _buildLeaderboardRow(4, 'ZenMaster', '97.2% Alignment', '+710 pips'),
          _buildLeaderboardRow(5, 'RiskNucleus_01', '96.9% Alignment', '+620 pips'),
        ],
      ),
    );
  }

  Widget _buildLeaderboardRow(int rank, String name, String alignment, String pnl) {
    Color rankColor = rank == 1 ? MehdAiTheme.gold : rank <= 3 ? MehdAiTheme.blue : MehdAiTheme.textSecondary;
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Row(
        children: [
          Text('#$rank', style: MehdAiTheme.terminalStyle.copyWith(color: rankColor, fontWeight: FontWeight.bold, fontSize: 18)),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: MehdAiTheme.terminalStyle.copyWith(color: MehdAiTheme.white, fontWeight: FontWeight.bold, fontSize: 14)),
                const SizedBox(height: 4),
                Text(alignment, style: MehdAiTheme.labelStyle.copyWith(fontSize: 12)),
              ],
            ),
          ),
          Text(pnl, style: MehdAiTheme.terminalStyle.copyWith(color: MehdAiTheme.green, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildWoundHealingHospital() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MehdAiTheme.bgSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MehdAiTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_hospital, color: MehdAiTheme.blue, size: 20),
              const SizedBox(width: 8),
              Text('WOUND HEALING HOSPITAL', style: MehdAiTheme.headingStyle.copyWith(color: MehdAiTheme.blue)),
            ],
          ),
          const SizedBox(height: 8),
          Text('Don\'t revenge trade. Process your losses with the Network.', style: MehdAiTheme.labelStyle),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Wound Post-Mortems', style: MehdAiTheme.labelStyle.copyWith(color: MehdAiTheme.textSecondary)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: MehdAiTheme.textSecondary.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                child: const Text('EXAMPLES', style: TextStyle(color: MehdAiTheme.textSecondary, fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildWoundPost(
            'BeginnerTrader99', 
            'XAU/USD blew past my Stop Loss. I lost 4% today and I feel sick. The AI said HOLD and I ignored it.', 
            'Don77', 
            'Capital is a seed, not a sacrifice. The Network saw the volume drying up. Take 24 hours off. You survived, that\'s what matters. Stick to the system tomorrow.',
            '-42 pips (FOMO DNA)'
          ),
          const Divider(color: MehdAiTheme.borderColor, height: 32),
          _buildWoundPost(
            'LoneWolf', 
            'Panic closed my EUR/USD BUY when it dipped 5 pips. It immediately shot up 30 pips. I am so tired of this.', 
            'AlphaQuant', 
            'It’s called the Spread Trap. ATLAS agent protects against that. You closed manually against consensus. Let the HardRiskKernel do its job next time. You got this.',
            'Missed +30 pips (Impatience DNA)'
          ),
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: MehdAiTheme.blue.withOpacity(0.1),
                side: const BorderSide(color: MehdAiTheme.blue),
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    backgroundColor: MehdAiTheme.bgSecondary,
                    title: Row(
                      children: [
                        const Icon(Icons.local_hospital, color: MehdAiTheme.blue),
                        const SizedBox(width: 8),
                        Text('TRIAGE REPORT', style: MehdAiTheme.headingStyle.copyWith(color: MehdAiTheme.blue)),
                      ],
                    ),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Admit your mistake to the Network. Truth is the only way to heal your Mistake DNA.', style: MehdAiTheme.labelStyle),
                        const SizedBox(height: 16),
                        TextField(
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            labelText: 'Asset Pair (e.g. XAU/USD)',
                            labelStyle: const TextStyle(color: MehdAiTheme.textSecondary),
                            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: MehdAiTheme.borderColor)),
                            focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: MehdAiTheme.blue)),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          style: const TextStyle(color: Colors.white),
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: 'What did you do wrong?',
                            labelStyle: const TextStyle(color: MehdAiTheme.textSecondary),
                            enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: MehdAiTheme.borderColor)),
                            focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: MehdAiTheme.blue)),
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('CANCEL', style: TextStyle(color: MehdAiTheme.textSecondary)),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: MehdAiTheme.blue),
                        onPressed: () {
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                            content: Text('Your Post-Mortem has been submitted to the Network for review.'),
                            backgroundColor: MehdAiTheme.blue,
                          ));
                        },
                        child: const Text('SUBMIT FOR REVIEW', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                );
              },
              child: Text('REQUEST POST-MORTEM TRIAGE', style: MehdAiTheme.terminalStyle.copyWith(color: MehdAiTheme.blue, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWoundPost(String opName, String opText, String replyName, String replyText, String mistakeTag) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            Text('@$opName reported a casualty:', style: MehdAiTheme.labelStyle.copyWith(color: MehdAiTheme.red)),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: MehdAiTheme.red.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
              child: Text(mistakeTag, style: MehdAiTheme.labelStyle.copyWith(color: MehdAiTheme.red, fontSize: 10)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text('"$opText"', style: MehdAiTheme.terminalStyle.copyWith(color: MehdAiTheme.textPrimary, fontStyle: FontStyle.italic)),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(color: Colors.black.withOpacity(0.2), borderRadius: BorderRadius.circular(8), border: const Border(left: BorderSide(color: MehdAiTheme.blue, width: 3))),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Elite Response from @$replyName:', style: MehdAiTheme.labelStyle.copyWith(color: MehdAiTheme.blue)),
              const SizedBox(height: 4),
              Text(replyText, style: MehdAiTheme.terminalStyle.copyWith(color: MehdAiTheme.white)),
            ],
          ),
        ),
      ],
    );
  }
}
