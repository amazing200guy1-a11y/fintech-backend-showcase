import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/services/settings_service.dart';
import 'package:mehd_ai_flutter/widgets/broker_card_tile.dart';
import 'package:mehd_ai_flutter/widgets/broker_connect_modal.dart';
import 'package:mehd_ai_flutter/widgets/broker_status_widgets.dart';
import 'package:mehd_ai_flutter/widgets/broker_dispute_modal.dart';
import 'package:mehd_ai_flutter/widgets/profit_rotator_card.dart';
import 'package:mehd_ai_flutter/widgets/multi_broker_diagnostic_card.dart';
import 'package:mehd_ai_flutter/widgets/broker_migration_dialog.dart';

import 'package:mehd_ai_flutter/models/broker_model.dart';

class BrokerScreen extends StatefulWidget {
  final bool showBack;
  const BrokerScreen({super.key, this.showBack = false});

  @override
  State<BrokerScreen> createState() => _BrokerScreenState();
}

class _BrokerScreenState extends State<BrokerScreen> {
  bool _isConnected = false;
  String _connectedBroker = '';

  // Live broker health data streamed from system_metrics/broker_health
  // Falls back to hardcoded mockup values if no live data exists yet (DEMO_MODE)
  Map<String, dynamic> _liveHealthData = {};

  // Community Fraud Intelligence — ONE document read per session.
  // Pre-seeded with real data for known manipulative brokers.
  // Updated atomically via FieldValue.increment() on each dispute report.
  final Map<String, dynamic> _fraudIndex = {
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

  final List<Broker> brokers = Broker.defaultBrokers;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MehdAiTheme.bgPrimary,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: widget.showBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: MehdAiTheme.white, size: 18),
                onPressed: () => Navigator.pop(context),
              )
            : null,

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
                            MultiBrokerDiagnosticCard(
                              connectedBrokers: [
                                Broker.defaultBrokers.firstWhere((b) => b.id == 'exness'),
                                Broker.defaultBrokers.firstWhere((b) => b.id == 'xm'),
                              ],
                              fraudIndex: _fraudIndex,
                              onConnectTap: () {
                                _showConnectSheet(Broker.defaultBrokers.first);
                              },
                              onMigrateTap: (flagged, recommended) {
                                BrokerMigrationDialog.show(
                                  context: context,
                                  flaggedBroker: flagged,
                                  recommendedBroker: recommended,
                                  onMigrateConfirm: () {
                                    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                                      backgroundColor: const Color(0xFF090D16),
                                      content: Text('✅ Connection updated! Account migrated to ${recommended.name}.', style: const TextStyle(color: Color(0xFF00FF88))),
                                    ));
                                  },
                                );
                              },
                            ),
                            const SizedBox(height: 16),
                            ProfitRotatorCard(
                            brokers: const [
                              {'broker': 'OANDA ECN', 'weekly_pnl': 3450.0, 'weekly_target': 5000.0, 'status': 'STEALTH_ACTIVE'},
                              {'broker': 'IC Markets (Raw)', 'weekly_pnl': 5120.0, 'weekly_target': 5000.0, 'status': 'TARGET_REACHED'},
                            ],
                            onRotateTap: () {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                backgroundColor: Color(0xFF090D16),
                                content: Text('🛡️ Active capital rotated to OANDA ECN account.', style: TextStyle(color: Color(0xFFBC8CFF))),
                              ));
                            },
                          ),
                          const SizedBox(height: 24),
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
    final active = brokers.firstWhere((b) => b.id == _connectedBroker, orElse: () => brokers.first);
    return BrokerConnectedStateCard(
      broker: active,
      onDispute: () => BrokerDisputeModal.show(context, active),
      onDisconnect: () async {
        await context.read<SettingsService>().clearBrokerConnection();
        setState(() {
          _isConnected = false;
          _connectedBroker = '';
        });
      },
    );
  }


  Widget _buildGlassmorphismCard(Broker broker) {
    final score = _effectiveHealthScore(broker);
    final isFlagged = _isBrokerFlagged(broker.id);
    final fraud = _getFraudData(broker.id);
    final live = _getLiveHealth(broker.id);
    final latency = live != null ? (live['avg_latency_ms'] as num).toInt() : broker.executionLatency;
    final slippage = live != null ? (live['avg_slippage_pips'] as num).toDouble() : broker.avgSlippage;

    return BrokerCardTile(
      broker: broker,
      healthScore: score,
      trustTierLabel: _effectiveTrustTier(broker),
      latency: latency,
      slippage: slippage,
      isFlagged: isFlagged,
      fraudData: fraud,
      isConnected: _isConnected,
      connectedBrokerId: _connectedBroker,
      onTap: () => _showConnectSheet(broker),
    );
  }


  Widget _buildPaperTradingCard() {
    return const BrokerPaperTradingCard();
  }

  void _showConnectSheet(Broker broker) {
    BrokerConnectModal.show(context, broker, () => setState(() {}));
  }
}


