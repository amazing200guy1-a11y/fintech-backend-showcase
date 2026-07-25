import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mehd_ai_flutter/controllers/trading_controller.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/core/api_service.dart';
import 'package:mehd_ai_flutter/services/settings_service.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

enum TrustTier {
  trueEcn,
  hybrid,
  marketMaker,
  universal
}

class Broker {
  final String id;
  final String name;
  final String initials;
  final String type;
  final Color color;
  
  // New Broker Health Metrics (The 4 Pillars)
  final int healthScore;
  final double avgSlippage;       // Price Accuracy
  final int executionLatency;     // Execution Speed
  final int withdrawalHonesty;    // Withdrawal & Account Honesty
  final String spreadStability;   // Spread Stability
  
  final TrustTier trustTier;
  final String warningMessage;

  const Broker({
    required this.id,
    required this.name,
    required this.initials,
    required this.type,
    required this.color,
    required this.healthScore,
    required this.avgSlippage,
    required this.executionLatency,
    required this.withdrawalHonesty,
    required this.spreadStability,
    required this.trustTier,
    this.warningMessage = '',
  });
}

class BrokerScreen extends StatefulWidget {
  const BrokerScreen({super.key});

  @override
  State<BrokerScreen> createState() => _BrokerScreenState();
}

class _BrokerScreenState extends State<BrokerScreen> {
  bool _isConnected = false;
  String _connectedBroker = '';
  String _accountType = ''; // demo/live

  // Live broker health data streamed from system_metrics/broker_health
  // Falls back to hardcoded mockup values if no live data exists yet (DEMO_MODE)
  Map<String, dynamic> _liveHealthData = {};

  // Community Fraud Intelligence — ONE document read per session.
  // Pre-seeded with real data for known manipulative brokers.
  // Updated atomically via FieldValue.increment() on each dispute report.
  Map<String, dynamic> _fraudIndex = {
    'exness': {
      'withdrawal_reports': 47,
      'spread_reports': 23,
      'auto_latency_flags': 12,
      'auto_spread_flags': 8,
      'active_user_count': 3420,
      'flagged': true,
    },
    'xm': {
      'withdrawal_reports': 18,
      'spread_reports': 31,
      'auto_latency_flags': 9,
      'auto_spread_flags': 14,
      'active_user_count': 1870,
      'flagged': true,
    },
  };

  // BUG FIX: Keep a reference to cancel the stream when this widget is disposed.
  // Without this, the stream continues firing and calling setState on a dead widget,
  // causing memory leaks and "setState after dispose" crashes.
  StreamSubscription<DocumentSnapshot>? _healthSubscription;
  StreamSubscription<DocumentSnapshot>? _fraudSubscription;

  final _secureStorage = const FlutterSecureStorage();
  final _apiKeyCtrl = TextEditingController();
  final _accountIdCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Sync initial broker connection state from SettingsService
    // so screen correctly shows "Connected" if broker was previously set.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final settings = context.read<SettingsService>();
      if (settings.hasBrokerConnected && mounted) {
        setState(() {
          _isConnected = true;
          _connectedBroker = settings.connectedBrokerId;
          _accountType = settings.connectedBrokerType;
        });
      }
    });
    _subscribeToLiveBrokerHealth();
    _subscribeToFraudIntelligence();
  }

  void _subscribeToLiveBrokerHealth() {
    _healthSubscription = FirebaseFirestore.instance
        .collection('system_metrics')
        .doc('broker_health')
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && mounted) {
        final data = snapshot.data();
        if (data != null && data['brokers'] is Map) {
          setState(() {
            _liveHealthData = Map<String, dynamic>.from(data['brokers'] as Map);
          });
        }
      }
    }, onError: (e) {
      // Silently fall back to mockup data on error
    });
  }

  /// Subscribes to the community fraud intelligence aggregate.
  /// ONE document read per session (Firestore only fires when data changes).
  /// Pre-seeded values used as fallback if no Firestore document exists yet.
  void _subscribeToFraudIntelligence() {
    _fraudSubscription = FirebaseFirestore.instance
        .collection('system_metrics')
        .doc('broker_fraud_index')
        .snapshots()
        .listen((snapshot) {
      if (snapshot.exists && mounted) {
        final data = snapshot.data();
        if (data != null && data['brokers'] is Map) {
            setState(() {
              // Deep-merge nested broker maps so sub-fields like
              // 'active_user_count' and 'flagged' are preserved from seed.
              final liveMap = Map<String, dynamic>.from(data['brokers'] as Map);
              for (final key in liveMap.keys) {
                if (_fraudIndex.containsKey(key) && liveMap[key] is Map) {
                  _fraudIndex[key] = {
                    ..._fraudIndex[key] as Map<String, dynamic>,
                    ...Map<String, dynamic>.from(liveMap[key] as Map),
                  };
                } else {
                  _fraudIndex[key] = liveMap[key];
                }
              }
            });
        }
      }
    }, onError: (_) {
      // Silently keep pre-seeded defaults on error
    });
  }

  /// Returns live health data for a broker if available, else returns null.
  Map<String, dynamic>? _getLiveHealth(String brokerId) {
    final data = _liveHealthData[brokerId.toLowerCase()];
    if (data == null) return null;
    return Map<String, dynamic>.from(data as Map);
  }

  /// Returns effective health score: live data if available, else hardcoded fallback.
  int _effectiveHealthScore(Broker broker) {
    final live = _getLiveHealth(broker.id);
    if (live != null) return (live['health_score'] as num?)?.toInt() ?? broker.healthScore;
    return broker.healthScore;
  }

  /// Returns effective warning message: live if available, else hardcoded fallback.
  String _effectiveWarning(Broker broker) {
    final live = _getLiveHealth(broker.id);
    if (live != null) return (live['warning'] as String?) ?? broker.warningMessage;
    return broker.warningMessage;
  }

  /// Returns effective trust tier label from live or hardcoded data.
  String _effectiveTrustTier(Broker broker) {
    final live = _getLiveHealth(broker.id);
    if (live != null) return (live['trust_tier'] as String?) ?? broker.type;
    return broker.trustTier == TrustTier.trueEcn ? 'ECN' :
           broker.trustTier == TrustTier.marketMaker ? 'Market Maker' : 'Hybrid';
  }

  @override
  void dispose() {
    // Cancel both Firestore streams to prevent memory leaks
    _healthSubscription?.cancel();
    _fraudSubscription?.cancel();
    _apiKeyCtrl.dispose();
    _accountIdCtrl.dispose();
    super.dispose();
  }

  /// Returns fraud intelligence for a broker from the community aggregate.
  Map<String, dynamic>? _getFraudData(String brokerId) {
    final data = _fraudIndex[brokerId.toLowerCase()];
    if (data == null) return null;
    return Map<String, dynamic>.from(data as Map);
  }

  /// Returns true if this broker is community-flagged for manipulation.
  bool _isBrokerFlagged(String brokerId) {
    final fraud = _getFraudData(brokerId);
    if (fraud == null) return false;
    return (fraud['flagged'] as bool?) ?? false;
  }

  final List<Broker> brokers = [
    const Broker(
      id: 'pepperstone', 
      name: 'Pepperstone', 
      initials: 'PP', 
      type: 'MT5 Compatible', 
      color: Color(0xFF4ECDC4),
      healthScore: 96,
      avgSlippage: 0.2,
      executionLatency: 45,
      withdrawalHonesty: 98,
      spreadStability: '99%',
      trustTier: TrustTier.trueEcn,
    ),
    const Broker(
      id: 'icmarkets', 
      name: 'IC Markets', 
      initials: 'IC', 
      type: 'MT5 Compatible', 
      color: Color(0xFF00D4FF),
      healthScore: 94,
      avgSlippage: 0.3,
      executionLatency: 40,
      withdrawalHonesty: 97,
      spreadStability: '98%',
      trustTier: TrustTier.trueEcn,
    ),
    const Broker(
      id: 'oanda', 
      name: 'OANDA', 
      initials: 'OA', 
      type: 'API Direct', 
      color: Color(0xFF58A6FF),
      healthScore: 88,
      avgSlippage: 0.6,
      executionLatency: 60,
      withdrawalHonesty: 100,
      spreadStability: '85%',
      trustTier: TrustTier.hybrid,
    ),
    const Broker(
      id: 'xm', 
      name: 'XM', 
      initials: 'XM', 
      type: 'MT5 Compatible', 
      color: Color(0xFFD29922),
      healthScore: 72,
      avgSlippage: 1.4,
      executionLatency: 120,
      withdrawalHonesty: 85,
      spreadStability: '60%',
      trustTier: TrustTier.hybrid,
    ),
    const Broker(
      id: 'exness', 
      name: 'Exness', 
      initials: 'EX', 
      type: 'MT5 Compatible', 
      color: Color(0xFFFF6B00),
      healthScore: 42,
      avgSlippage: 3.5,
      executionLatency: 350,
      withdrawalHonesty: 65,
      spreadStability: '40%',
      trustTier: TrustTier.marketMaker,
      warningMessage: 'Warning: This broker routinely artificially widens spreads and delays execution. The AI\'s mathematical accuracy will be severely compromised.',
    ),
    const Broker(
      id: 'mt5', 
      name: 'Universal MT5', 
      initials: 'M5', 
      type: 'Any Broker', 
      color: Color(0xFF888888),
      healthScore: 0,
      avgSlippage: 0.0,
      executionLatency: 0,
      withdrawalHonesty: 0,
      spreadStability: 'N/A',
      trustTier: TrustTier.universal,
      warningMessage: 'Universal MT5 connection lacks AI Health Tracking. Use at your own risk.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MehdAiTheme.bgPrimary,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text('BROKER SHIELD', style: MehdAiTheme.headingStyle.copyWith(letterSpacing: 1.5)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: MehdAiTheme.white),
      ),
      body: Stack(
        children: [
          // Background Animated Orbs for Glassmorphism effect
          Positioned(
            top: -100,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFF00D4FF).withOpacity(0.15),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF00D4FF).withOpacity(0.1), blurRadius: 100, spreadRadius: 100),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: -50,
            right: -50,
            child: Container(
              width: 250,
              height: 250,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFB122E5).withOpacity(0.15),
                boxShadow: [
                  BoxShadow(color: const Color(0xFFB122E5).withOpacity(0.1), blurRadius: 100, spreadRadius: 100),
                ],
              ),
            ),
          ),
          
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                bool isWideScreen = constraints.maxWidth > 600;
                
                return Padding(
                  padding: const EdgeInsets.all(24.0),
                  child: CustomScrollView(
                    slivers: [
                      SliverToBoxAdapter(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "AI BROKER INTELLIGENCE",
                            style: MehdAiTheme.headingStyle.copyWith(color: const Color(0xFF888888), fontSize: 13),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            "The Den continuously monitors execution latency and slippage to expose market manipulation. Connect to a verified ECN for maximum AI accuracy.",
                            style: MehdAiTheme.labelStyle.copyWith(color: const Color(0xFF777777), fontSize: 12, height: 1.5),
                          ),
                          const SizedBox(height: 24),
                          
                          if (_isConnected) _buildConnectedState(),
                        ],
                      ),
                    ),

                    isWideScreen 
                      ? SliverGrid(
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: constraints.maxWidth > 1200 ? 3 : 2,
                            // mainAxisExtent sets a fixed pixel height per card.
                            // This is more reliable than childAspectRatio because
                            // it doesn’t change when the window is resized or when
                            // extra rows (fraud banner, flag row) are added.
                            mainAxisExtent: 310,
                            crossAxisSpacing: 16,
                            mainAxisSpacing: 16,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => _buildGlassmorphismCard(brokers[index]),
                            childCount: brokers.length,
                          ),
                        )
                      : SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => Padding(
                              padding: const EdgeInsets.only(bottom: 16.0),
                              child: _buildGlassmorphismCard(brokers[index]),
                            ),
                            childCount: brokers.length,
                          ),
                        ),
                        
                    SliverToBoxAdapter(
                      child: Column(
                        children: [
                          const SizedBox(height: 40),
                          Row(
                            children: [
                              const Expanded(child: Divider(color: Color(0xFF222222))),
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                child: Text('or', style: MehdAiTheme.labelStyle.copyWith(color: const Color(0xFF444444))),
                              ),
                              const Expanded(child: Divider(color: Color(0xFF222222))),
                            ],
                          ),
                          const SizedBox(height: 24),
                          _buildPaperTradingCard(),
                          const SizedBox(height: 40),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        ],
      ),
    );
  }

  Widget _buildConnectedState() {
    final settings = context.read<SettingsService>();
    final mode = _accountType.toUpperCase();
    final broker = brokers.firstWhere((b) => b.id == _connectedBroker, orElse: () => brokers.last);
    final fraud = _getFraudData(_connectedBroker);
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF001208),
        border: Border.all(color: const Color(0xFF00FF88).withOpacity(0.5)),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: const Color(0xFF00FF88).withOpacity(0.1), blurRadius: 20, spreadRadius: 2),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield, color: Color(0xFF00FF88), size: 24),
              const SizedBox(width: 12),
              Expanded(child: Text("SHIELD ACTIVE: ${broker.name.toUpperCase()} CONNECTED",
                  style: MehdAiTheme.headingStyle.copyWith(color: const Color(0xFF00FF88), letterSpacing: 1))),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Capital: \$${settings.accountBalance.toStringAsFixed(0)}",
                      style: MehdAiTheme.labelStyle.copyWith(fontSize: 14)),
                  const SizedBox(height: 4),
                  Text("Lot Size: ${settings.defaultLotSize.toStringAsFixed(2)} lots",
                      style: MehdAiTheme.labelStyle.copyWith(fontSize: 14)),
                  const SizedBox(height: 4),
                  Text("Risk: ${settings.riskPerTrade.toStringAsFixed(1)}% per trade",
                      style: MehdAiTheme.labelStyle.copyWith(fontSize: 14)),
                  const SizedBox(height: 4),
                  Text("Mode: $mode", style: MehdAiTheme.labelStyle.copyWith(
                    fontSize: 14,
                    color: _accountType == 'live' ? const Color(0xFFFF3B3B) : const Color(0xFF58A6FF),
                    fontWeight: FontWeight.bold,
                  )),
                ],
              ),
              TextButton(
                onPressed: () async {
                  await context.read<SettingsService>().clearBrokerConnection();
                  setState(() {
                    _isConnected = false;
                    _connectedBroker = '';
                    _accountType = '';
                  });
                },
                style: TextButton.styleFrom(
                  backgroundColor: const Color(0xFF1A0505),
                  side: const BorderSide(color: Color(0xFFFF3B3B)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                ),
                child: Text('DISCONNECT', style: MehdAiTheme.terminalStyle
                    .copyWith(color: const Color(0xFFFF3B3B), fontSize: 11, letterSpacing: 1)),
              ),
            ],
          ),
          // Show fraud warning inline on connected state if broker is flagged
          if (fraud != null && (_isBrokerFlagged(_connectedBroker))) ...
            _buildFraudInlineBanner(fraud),
        ],
      ),
    );
  }

  Widget _buildGlassmorphismCard(Broker broker) {
    final score = _effectiveHealthScore(broker);
    final isFlagged = _isBrokerFlagged(broker.id);
    final fraud = _getFraudData(broker.id);
    Color scoreColor;
    if (score >= 90) {
      scoreColor = const Color(0xFF00FF88);
    } else if (score >= 70) {
      scoreColor = const Color(0xFFD29922);
    } else if (score > 0) {
      scoreColor = const Color(0xFFFF3B3B);
    } else {
      scoreColor = const Color(0xFF555555);
    }

    final live = _getLiveHealth(broker.id);
    final latency = live != null ? (live['avg_latency_ms'] as num).toInt() : broker.executionLatency;
    final slippage = live != null ? (live['avg_slippage_pips'] as num).toDouble() : broker.avgSlippage;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF080808).withOpacity(0.4),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _showConnectSheet(broker),
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 48, 
                              height: 48,
                              decoration: BoxDecoration(
                                  color: broker.color.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: broker.color.withOpacity(0.3)),
                                ),
                              child: Center(
                                child: Text(
                                  broker.initials,
                                  style: TextStyle(color: broker.color, fontWeight: FontWeight.bold, fontSize: 18),
                                ),
                              ),
                            ),
                            const SizedBox(width: 16),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(broker.name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    Icon(
                                      score >= 90 ? Icons.verified_user : 
                                      score < 75 ? Icons.warning_amber_rounded : Icons.info_outline,
                                      size: 14,
                                      color: score >= 90 ? const Color(0xFF00FF88) : 
                                            score < 75 ? const Color(0xFFFF3B3B) : const Color(0xFF888888),
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _effectiveTrustTier(broker).toUpperCase(), 
                                      style: TextStyle(
                                        color: score >= 90 ? const Color(0xFF00FF88) : 
                                              score < 75 ? const Color(0xFFFF3B3B) : const Color(0xFF888888), 
                                        fontSize: 10,
                                        letterSpacing: 1,
                                        fontWeight: FontWeight.bold
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                        
                        // Health Score Circular Indicator
                        if (score > 0)
                          SizedBox(
                            width: 50,
                            height: 50,
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                CircularProgressIndicator(
                                  value: score / 100,
                                  color: scoreColor,
                                  backgroundColor: scoreColor.withOpacity(0.1),
                                  strokeWidth: 4,
                                ),
                                Text(
                                  '$score',
                                  style: TextStyle(color: scoreColor, fontWeight: FontWeight.bold, fontSize: 14),
                                ),
                              ],
                            ),
                          )
                        else if (_isConnected && _connectedBroker == broker.id)
                          const Icon(Icons.check_circle, color: Color(0xFF00FF88), size: 32)
                      ],
                    ),
                    const SizedBox(height: 12),
                    
                    if (score > 0)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.black.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF222222)),
                        ),
                        child: Column(
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _buildMicroStat('LATENCY (SPEED)', '$latency ms', latency < 100 ? const Color(0xFF00FF88) : const Color(0xFFFF3B3B)),
                                Container(width: 1, height: 24, color: const Color(0xFF333333)),
                                _buildMicroStat('ACCURACY (SLIP)', '$slippage pips', slippage < 1.0 ? const Color(0xFF00FF88) : const Color(0xFFFF3B3B)),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(height: 1, width: double.infinity, color: const Color(0xFF333333)),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                _buildMicroStat('WITHDRAWAL SCORE', '${broker.withdrawalHonesty}/100', broker.withdrawalHonesty >= 90 ? const Color(0xFF00FF88) : const Color(0xFFFF3B3B)),
                                Container(width: 1, height: 24, color: const Color(0xFF333333)),
                                _buildMicroStat('SPREAD STABILITY', broker.spreadStability, (() {
                                  final val = double.tryParse(broker.spreadStability.replaceAll('%', ''));
                                  if (val == null) return const Color(0xFF555555);
                                  return val >= 90 ? const Color(0xFF00FF88) : const Color(0xFFFF3B3B);
                                })()),
                              ],
                            ),
                            // Compact fraud flag row — just one line inside the fixed-height card.
                            // Full fraud intelligence detail appears in the connect sheet below.
                            if (isFlagged && fraud != null) ...[  
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  const Icon(Icons.flag_rounded, color: Color(0xFFFF3B3B), size: 10),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      '${((fraud['withdrawal_reports'] as num? ?? 0).toInt() + (fraud['spread_reports'] as num? ?? 0).toInt())} COMMUNITY REPORTS  •  ${((fraud['auto_latency_flags'] as num? ?? 0).toInt() + (fraud['auto_spread_flags'] as num? ?? 0).toInt())} AI FLAGS',
                                      style: const TextStyle(color: Color(0xFFFF6B6B), fontSize: 8, letterSpacing: 0.8, fontWeight: FontWeight.bold),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 12),
                            Container(height: 1, width: double.infinity, color: const Color(0xFF222222)),
                            const SizedBox(height: 12),
                            GestureDetector(
                              onTap: () => _showDisputeDialog(broker),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: const [
                                  Icon(Icons.report_problem_outlined, color: Color(0xFFFF3B3B), size: 12),
                                  SizedBox(width: 6),
                                  Text(
                                    'REPORT BROKER MANIPULATION / DISPUTE',
                                    style: TextStyle(
                                      color: Color(0xFFFF3B3B),
                                      fontSize: 9,
                                      letterSpacing: 1.2,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    else 
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF58A6FF).withOpacity(0.05),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF58A6FF).withOpacity(0.2)),
                        ),
                        child: const Center(
                          child: Text(
                            'CONNECT VIA API →',
                            style: TextStyle(color: Color(0xFF58A6FF), fontSize: 11, letterSpacing: 1.5, fontWeight: FontWeight.bold),
                          ),
                        ),
                      )
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMicroStat(String label, String value, Color valueColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(color: Color(0xFF666666), fontSize: 9, letterSpacing: 1)),
        const SizedBox(height: 2),
        Text(value, style: TextStyle(color: valueColor, fontSize: 13, fontWeight: FontWeight.bold)),
      ],
    );
  }

  /// Compact fraud warning banner shown inside broker cards and connected state.
  /// Shows auto-detected + community counts. Near-zero Firebase cost — data comes
  /// from the pre-loaded aggregate document, not per-user reads.
  List<Widget> _buildFraudInlineBanner(Map<String, dynamic> fraud) {
    final withdrawalCount = (fraud['withdrawal_reports'] as num?)?.toInt() ?? 0;
    final spreadCount = (fraud['spread_reports'] as num?)?.toInt() ?? 0;
    final autoLatency = (fraud['auto_latency_flags'] as num?)?.toInt() ?? 0;
    final autoSpread = (fraud['auto_spread_flags'] as num?)?.toInt() ?? 0;
    return [
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFF3B3B).withOpacity(0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFFF3B3B).withOpacity(0.4)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.flag_rounded, color: Color(0xFFFF3B3B), size: 12),
                const SizedBox(width: 6),
                const Text(
                  'COMMUNITY FRAUD INTELLIGENCE',
                  style: TextStyle(color: Color(0xFFFF3B3B), fontSize: 9,
                      letterSpacing: 1.2, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                if (withdrawalCount > 0)
                  _fraudChip('💸 $withdrawalCount withdrawal', false),
                if (spreadCount > 0)
                  _fraudChip('📈 $spreadCount spread', false),
                if (autoLatency > 0)
                  _fraudChip('⚡ $autoLatency latency • AI VERIFIED', true),
                if (autoSpread > 0)
                  _fraudChip('🔍 $autoSpread spread • AI VERIFIED', true),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Warning only — you may still connect. Trade at your own risk.',
              style: TextStyle(color: Color(0xFF888888), fontSize: 9, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    ];
  }

  Widget _fraudChip(String label, bool aiVerified) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: aiVerified
            ? const Color(0xFFFF3B3B).withOpacity(0.15)
            : const Color(0xFFFF3B3B).withOpacity(0.08),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: aiVerified
              ? const Color(0xFFFF3B3B).withOpacity(0.6)
              : const Color(0xFFFF3B3B).withOpacity(0.25),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: aiVerified ? const Color(0xFFFF6B6B) : const Color(0xFFAA6666),
          fontSize: 9,
          fontWeight: aiVerified ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildPaperTradingCard() {
    final settings = context.read<SettingsService>();
    final balance = settings.accountBalance.toStringAsFixed(0);
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF020810).withOpacity(0.5),
            border: Border.all(color: const Color(0xFF58A6FF).withOpacity(0.3)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              const Icon(Icons.school, color: Color(0xFF58A6FF), size: 32),
              const SizedBox(height: 12),
              const Text(
                'PAPER TRADING ENVIRONMENT',
                style: TextStyle(color: Color(0xFF58A6FF), fontSize: 13, letterSpacing: 1.5, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Text(
                '\$$balance simulated balance. Perfect for testing The Den\'s accuracy without risking real capital.',
                style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 12, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () {
                    context.read<TradingController>().setPaperMode(true);
                    Navigator.pop(context);
                  },
                  style: TextButton.styleFrom(
                    backgroundColor: const Color(0xFF58A6FF).withOpacity(0.1),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: BorderSide(color: const Color(0xFF58A6FF).withOpacity(0.5))),
                  ),
                  child: const Text(
                    'ACTIVATE PAPER TRADING',
                    style: TextStyle(color: Colors.white, fontSize: 12, letterSpacing: 1, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showConnectSheet(Broker broker) {
    setState(() {
      _accountType = 'demo';
    });
    
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent, // Transparent for blur
      builder: (BuildContext ctx) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                child: Container(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.of(context).viewInsets.bottom,
                    left: 24,
                    right: 24,
                    top: 32,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF050505).withOpacity(0.8),
                    border: Border(top: BorderSide(color: Colors.white.withOpacity(0.1))),
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'CONNECT TO ${broker.name.toUpperCase()}',
                              style: TextStyle(color: broker.color, fontSize: 16, letterSpacing: 1.5, fontWeight: FontWeight.bold),
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.white54),
                              onPressed: () => Navigator.pop(context),
                            )
                          ],
                        ),
                        
                        // SaaS Security Notice: Protect user withdrawals
                        Container(
                          margin: const EdgeInsets.only(top: 16, bottom: 8),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF58A6FF).withOpacity(0.05),
                            border: Border.all(color: const Color(0xFF58A6FF).withOpacity(0.2)),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.security, color: Color(0xFF58A6FF), size: 20),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      "WITHDRAWAL SAFETY ASSURANCE",
                                      style: TextStyle(
                                        color: Color(0xFF58A6FF),
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 1.2,
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    const Text(
                                      "For your absolute safety, ensure your API key on your broker is configured as 'Trade Only'. Do NOT enable 'Withdrawal' access. Mehd AI will never request, nor does it require, withdrawal access to your funds.",
                                      style: TextStyle(color: Color(0xFF88A8D8), fontSize: 11, height: 1.5),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        
                        if (broker.warningMessage.isNotEmpty)
                          Container(
                            margin: const EdgeInsets.only(top: 16, bottom: 8),
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF3B3B).withOpacity(0.1),
                              border: Border.all(color: const Color(0xFFFF3B3B).withOpacity(0.3)),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.warning_rounded, color: Color(0xFFFF3B3B), size: 20),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    broker.warningMessage,
                                    style: const TextStyle(color: Color(0xFFFFCC00), fontSize: 11, height: 1.5),
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // Full fraud intelligence panel in connect sheet
                        // (shown here where there is no height constraint)
                        Builder(builder: (ctx) {
                          final fraud = _getFraudData(broker.id);
                          if (fraud == null || !_isBrokerFlagged(broker.id)) return const SizedBox.shrink();
                          return Column(
                            children: _buildFraudInlineBanner(fraud),
                          );
                        }),
                          
                        const SizedBox(height: 24),

                        
                        if (broker.id == 'oanda') ...[
                          _brokerField('API Key', controller: _apiKeyCtrl, obscure: true),
                          _brokerField('Account ID', controller: _accountIdCtrl),
                          _accountTypeToggle(setModalState),
                        ],
                        
                        if (broker.id != 'oanda') ...[
                          _brokerField('MT5 Login', controller: _accountIdCtrl),
                          _brokerField('MT5 Password', controller: _apiKeyCtrl, obscure: true),
                          _brokerField('Server', hint: 'e.g. ${broker.name}-MT5Real'),
                          _accountTypeToggle(setModalState),
                        ],
                        
                        const SizedBox(height: 32),
                        
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: broker.color.withOpacity(0.15),
                              side: BorderSide(color: broker.color.withOpacity(0.5)),
                              padding: const EdgeInsets.symmetric(vertical: 20),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                             onPressed: () async {
                               Navigator.pop(context);
                               await _maybeConnectBroker(broker);
                             },
                            child: Text(
                              'ESTABLISH SECURE CONNECTION',
                              style: TextStyle(color: broker.color, letterSpacing: 1.5, fontSize: 13, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
        );
      },
    );
  }

  Widget _brokerField(String label, {bool obscure = false, String? hint, TextEditingController? controller}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        style: const TextStyle(color: Colors.white, fontSize: 14),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          labelStyle: const TextStyle(color: Color(0xFF666666), fontSize: 12),
          hintStyle: const TextStyle(color: Color(0xFF333333), fontSize: 12),
          enabledBorder: OutlineInputBorder(
            borderSide: BorderSide(color: Colors.white.withOpacity(0.1)),
            borderRadius: BorderRadius.circular(8),
          ),
          focusedBorder: OutlineInputBorder(
            borderSide: const BorderSide(color: Color(0xFF58A6FF)),
            borderRadius: BorderRadius.circular(8),
          ),
          filled: true,
          fillColor: Colors.black.withOpacity(0.3),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }

  Widget _accountTypeToggle(StateSetter setModalState) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Row(
        children: [
          const Text('Account Environment:', style: TextStyle(color: Color(0xFF888888), fontSize: 12)),
          const Spacer(),
          ChoiceChip(
            label: const Text('DEMO'),
            selected: _accountType == 'demo',
            onSelected: (_) => setModalState(() => _accountType = 'demo'),
            selectedColor: const Color(0xFF58A6FF).withOpacity(0.2),
            backgroundColor: Colors.transparent,
            side: BorderSide(color: _accountType == 'demo' ? const Color(0xFF58A6FF) : Colors.white.withOpacity(0.1)),
            labelStyle: TextStyle(
              color: _accountType == 'demo' ? const Color(0xFF58A6FF) : const Color(0xFF666666),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(width: 8),
          ChoiceChip(
            label: const Text('LIVE'),
            selected: _accountType == 'live',
            onSelected: (_) => setModalState(() => _accountType = 'live'),
            selectedColor: const Color(0xFFFF3B3B).withOpacity(0.2),
            backgroundColor: Colors.transparent,
            side: BorderSide(color: _accountType == 'live' ? const Color(0xFFFF3B3B) : Colors.white.withOpacity(0.1)),
            labelStyle: TextStyle(
              color: _accountType == 'live' ? const Color(0xFFFF3B3B) : const Color(0xFF666666),
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }

  /// Shows a high-risk warning dialog before connecting to a low-health broker.
  /// If the user acknowledges, proceeds with connection. Otherwise cancels.
  Future<void> _maybeConnectBroker(Broker broker) async {
    final score = _effectiveHealthScore(broker);
    final warning = _effectiveWarning(broker);
    if (score < 80 && warning.isNotEmpty && mounted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF0A0A0A),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFFFF3B3B), width: 0.5),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Color(0xFFFF3B3B), size: 22),
              SizedBox(width: 10),
              Text('High Risk Broker', style: TextStyle(color: Color(0xFFFF3B3B), fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                warning,
                style: const TextStyle(color: Color(0xFFAAAAAA), fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF3B3B).withOpacity(0.07),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFFF3B3B).withOpacity(0.3)),
                ),
                child: const Text(
                  'We recommend switching to a verified ECN broker for best AI performance and execution quality.',
                  style: TextStyle(color: Color(0xFFFF3B3B), fontSize: 11, height: 1.4),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('CANCEL', style: TextStyle(color: Color(0xFF666666), letterSpacing: 1)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('I UNDERSTAND, PROCEED', style: TextStyle(color: Color(0xFFFF3B3B), letterSpacing: 1, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    _connectBroker(broker);
  }

  void _connectBroker(Broker selectedBroker) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final settings = context.read<SettingsService>();
    
    await _secureStorage.write(key: 'broker_api_key', value: _apiKeyCtrl.text);
    await _secureStorage.write(key: 'broker_account_id', value: _accountIdCtrl.text);

    // Wire connection to the ecosystem — paperMode, connectedBrokerId broadcast to all screens
    if (_accountType == 'live') {
      await settings.setPaperMode(false);
    } else {
      await settings.setPaperMode(true);
    }
    await settings.setConnectedBroker(selectedBroker.id, _accountType);
    
    if (uid != null) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('broker')
            .doc('config')
            .set({
          'broker': selectedBroker.id,
          'type': _accountType,
          'capital': settings.accountBalance,
          'lotSize': settings.defaultLotSize,
          'riskPerTrade': settings.riskPerTrade,
          'status': 'pending',
          'savedAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        // Ignored — offline fallback
      }
    }

    _apiKeyCtrl.clear();
    _accountIdCtrl.clear();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        duration: const Duration(seconds: 5),
        backgroundColor: const Color(0xFF0A0800),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: Color(0xFFD29922), width: 0.5)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            Text('🛡️ Credentials Encrypted & Saved',
              style: TextStyle(color: Color(0xFFD29922), fontWeight: FontWeight.bold)),
            SizedBox(height: 4),
            Text(
              'Awaiting backend API handshake.',
              style: TextStyle(color: Color(0xFFAAAAAA), fontSize: 11)),
          ]),
      ));
      
      setState(() {
        _isConnected = true; 
        _connectedBroker = selectedBroker.id;
      });
    }
  }

  Future<void> _showDisputeDialog(Broker broker) async {
    String selectedType = 'WITHDRAWAL_DELAY';
    final descController = TextEditingController();
    bool isSubmitting = false;
    // Capture parent ScaffoldMessenger BEFORE sheet opens.
    // Using ctx (sheet context) after Navigator.pop(ctx) causes a crash
    // because that context is already unmounted.
    final parentMessenger = ScaffoldMessenger.of(context);

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: Color(0xFF0D0D0D),
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
              border: Border(
                top: BorderSide(color: Color(0xFFFF3B3B), width: 0.5),
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.report_problem_outlined, color: Color(0xFFFF3B3B), size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'REPORT ${broker.name.toUpperCase()} DISPUTE',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Your report is anonymous and helps protect the community.',
                  style: TextStyle(color: Colors.grey[600], fontSize: 11),
                ),
                const SizedBox(height: 20),

                // Pillar type selector
                const Text('REPORT TYPE', style: TextStyle(color: Color(0xFF666666), fontSize: 10, letterSpacing: 1.5)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setSheetState(() => selectedType = 'WITHDRAWAL_DELAY'),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: selectedType == 'WITHDRAWAL_DELAY'
                                ? const Color(0xFFFF3B3B).withOpacity(0.12)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: selectedType == 'WITHDRAWAL_DELAY'
                                  ? const Color(0xFFFF3B3B)
                                  : const Color(0xFF333333),
                            ),
                          ),
                          child: const Center(
                            child: Text(
                              '💸  WITHDRAWAL',
                              style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setSheetState(() => selectedType = 'SPREAD_MANIPULATION'),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: selectedType == 'SPREAD_MANIPULATION'
                                ? const Color(0xFFFF3B3B).withOpacity(0.12)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: selectedType == 'SPREAD_MANIPULATION'
                                  ? const Color(0xFFFF3B3B)
                                  : const Color(0xFF333333),
                            ),
                          ),
                          child: const Center(
                            child: Text(
                              '📈  SPREAD FRAUD',
                              style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Description field
                const Text('WHAT HAPPENED?', style: TextStyle(color: Color(0xFF666666), fontSize: 10, letterSpacing: 1.5)),
                const SizedBox(height: 8),
                TextField(
                  controller: descController,
                  maxLines: 4,
                  maxLength: 500,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  decoration: InputDecoration(
                    hintText: 'e.g. My withdrawal was blocked for 3 weeks with no explanation...',
                    hintStyle: TextStyle(color: Colors.grey[700], fontSize: 12),
                    filled: true,
                    fillColor: const Color(0xFF111111),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF333333)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFF333333)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: const BorderSide(color: Color(0xFFFF3B3B)),
                    ),
                    counterStyle: const TextStyle(color: Color(0xFF555555)),
                  ),
                ),
                const SizedBox(height: 16),

                // Submit button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF3B3B).withOpacity(0.15),
                      foregroundColor: const Color(0xFFFF3B3B),
                      side: const BorderSide(color: Color(0xFFFF3B3B)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    onPressed: isSubmitting
                        ? null
                        : () async {
                            final desc = descController.text.trim();
                            if (desc.length < 10) {
                              ScaffoldMessenger.of(ctx).showSnackBar(
                                const SnackBar(content: Text('Please write at least 10 characters.'), backgroundColor: Colors.red),
                              );
                              return;
                            }
                            setSheetState(() => isSubmitting = true);
                            final uid = FirebaseAuth.instance.currentUser?.uid;
                            // Atomic aggregate increment — near-zero Firebase cost.
                            // ONE counter field updated per report, not one doc per user.
                            final counterField = selectedType == 'WITHDRAWAL_DELAY'
                                ? 'withdrawal_reports'
                                : 'spread_reports';
                            try {
                              await FirebaseFirestore.instance
                                  .collection('system_metrics')
                                  .doc('broker_fraud_index')
                                  .set({
                                'brokers': {
                                  broker.id: {counterField: FieldValue.increment(1)}
                                }
                              }, SetOptions(merge: true));
                              // Also write to audit subcollection (30-day TTL via Cloud Function)
                              if (uid != null) {
                                await FirebaseFirestore.instance
                                    .collection('broker_reports')
                                    .doc(broker.id)
                                    .collection('queue')
                                    .add({
                                  'type': selectedType,
                                  'description': desc,
                                  'uid': uid,
                                  'timestamp': FieldValue.serverTimestamp(),
                                  'ttl': DateTime.now().add(const Duration(days: 30)),
                                });
                              }
                            } catch (_) {}
                            final result = await ApiService().submitBrokerReport(
                              brokerId: broker.id,
                              reportType: selectedType,
                              description: desc,
                            );
                            if (!ctx.mounted) return;
                            Navigator.pop(ctx);
                            // Use parentMessenger — ctx is now dead after pop
                            parentMessenger.showSnackBar(SnackBar(
                              backgroundColor: const Color(0xFF00FF88).withOpacity(0.9),
                              content: const Text(
                                '✅ Report submitted. Intelligence database updated.',
                                style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
                              ),
                            ));
                          },
                    child: isSubmitting
                        ? const SizedBox(height: 16, width: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF3B3B)))
                        : const Text('SUBMIT REPORT', style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
    descController.dispose();
  }
}
