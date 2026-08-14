import 'dart:async';
import 'package:flutter/material.dart';
import 'package:mehd_ai_flutter/services/live_data_service.dart';
import 'package:mehd_ai_flutter/models/consensus_result.dart';
import 'package:mehd_ai_flutter/models/market_snapshot.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mehd_ai_flutter/core/constants.dart';
// ignore_for_file: unused_import

class MarketDataController extends ChangeNotifier {
  String? activeSymbol = 'EUR/USD';
  String activeInterval = '1m';
  MarketSnapshot? latestSnapshot;
  ConsensusResult? consensus;
  bool isAnalyzing = false;
  bool isBackendOffline = false;
  bool isSentinelFrozen = false;
  ButtonState btnState = ButtonState.locked;
  bool feedbackShown = false;
  bool showFeedbackOption = false;

  // TradingView Bridge State
  String drawingMode = 'AUTO'; // 'AUTO' or 'MANUAL'
  String activeTool = 'none';
  List<Map<String, dynamic>> aiCommands = [];
  List<Map<String, dynamic>> _pendingDrawings = [];

  void executeDrawings() {
    if (_pendingDrawings.isNotEmpty) {
      aiCommands = _pendingDrawings;
      notifyListeners();
    }
  }

  final LiveDataService _liveDataService = LiveDataService();
  StreamSubscription<MarketSnapshot>? _priceSub;
  StreamSubscription<QuerySnapshot>? _firestoreSub;

  MarketDataController() {
    // Auto-select EUR/USD on startup so chart shows immediately
    activeSymbol = 'EUR/USD';
    _startPriceStream('EUR/USD');
    _fetchHistoricalData('EUR/USD');
    _triggerAnalysis('EUR/USD', (msg) {});
  }

  void _startPriceStream(String symbol) {
    _priceSub?.cancel();
    _priceSub = _liveDataService.streamPrices(symbol).listen((snapshot) {
      latestSnapshot = snapshot;
      notifyListeners();
    });
  }

  void selectSymbol(String rawSymbol, {required Function(String) onStatusMsg}) {
    final symbol = rawSymbol.replaceAll('/', '');
    activeSymbol = rawSymbol;
    consensus = null;
    btnState = ButtonState.locked;
    latestSnapshot = null;
    aiCommands = [];
    _pendingDrawings = [];
    notifyListeners();

    // ── LIVE STREAM CONNECTION ──
    _startPriceStream(symbol);
    _fetchHistoricalData(symbol);

    _listenToFirestore(symbol, onStatusMsg);
    _triggerAnalysis(symbol, onStatusMsg);
  }

  /// Triggers a live 11-Agent Swarm scan on demand for the specified symbol (or activeSymbol).
  void triggerSwarmAnalysis([String? symbol]) {
    final sym = symbol ?? activeSymbol ?? 'EUR/USD';
    _triggerAnalysis(sym, (_) {});
  }

  void updatePriceFromChart(double price) {
    if (latestSnapshot == null) {
      latestSnapshot = MarketSnapshot(
        id: activeSymbol ?? 'EUR/USD',
        symbol: activeSymbol ?? 'EUR/USD',
        bid: price - 0.0001,
        ask: price + 0.0001,
        spread: 0.0002,
        timestamp: DateTime.now(),
        open: price,
        high: price,
        low: price,
        close: price,
        volume: 0,
        dataSource: 'chart_sync',
        isLive: true,
      );
    } else {
      latestSnapshot = latestSnapshot!.copyWith(close: price, bid: price - 0.0001, ask: price + 0.0001);
    }
    notifyListeners();
  }

  Future<void> _fetchHistoricalData(String symbol) async {
    final candles = await _liveDataService.fetchHistoricalCandles(symbol);
    if (candles.isNotEmpty) {
      aiCommands = [
        {
          'action': 'history',
          'data': candles,
        }
      ];
      notifyListeners();
    }
  }

  void _listenToFirestore(String symbol, Function(String) onStatusMsg) {
    _firestoreSub?.cancel();
    final userId = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
    _firestoreSub = FirebaseFirestore.instance
      .collection('users').doc(userId)
      .collection('analyses')
      .where('symbol', isEqualTo: symbol)
      .orderBy('timestamp', descending: true)
      .limit(1)
      .snapshots()
      .listen((snapshot) {
        if (snapshot.docs.isNotEmpty) {
           final data = snapshot.docs.first.data();
           final parsed = ConsensusResult.fromJson(data);
           _handleNewConsensus(parsed, onStatusMsg);
        }
      });
  }

  Future<void> _triggerAnalysis(String symbol, Function(String) onStatusMsg) async {
    isAnalyzing = true;
    notifyListeners();
    
    final startTime = DateTime.now();
    ConsensusResult? finalResult;

    try {
      final userId = FirebaseAuth.instance.currentUser?.uid ?? 'guest';
      final HttpsCallable callable = FirebaseFunctions.instance.httpsCallable('orchestrateConsensus');
      final result = await callable.call({
         'symbol': symbol,
         'userId': userId,
         'tier': 'sovereign',
      }).timeout(const Duration(seconds: 8)); // Fast timeout — don't hang
      
      if (result.data != null) {
        finalResult = ConsensusResult.fromJson(Map<String, dynamic>.from(result.data));
      }
    } catch (e) {
      debugPrint('Cloud Function failed: $e');
      finalResult = null;
    }

    // Minimum 3s "thinking" feel (was 8s — too slow)
    final elapsed = DateTime.now().difference(startTime);
    if (elapsed.inMilliseconds < 3000) {
      await Future.delayed(Duration(milliseconds: 3000 - elapsed.inMilliseconds));
    }

    if (finalResult != null) {
      _handleNewConsensus(finalResult, onStatusMsg);
    } else {
      final base = latestSnapshot?.close ?? 1.08500;
      final mockResult = ConsensusResult(
        votes: [
          AIVote(modelName: 'vanguard', snapshotId: 'mock', direction: 'BUY', confidence: 0.92, reasoning: 'Strong momentum on H4'),
          AIVote(modelName: 'guardian', snapshotId: 'mock', direction: 'BUY', confidence: 0.88, reasoning: 'Risk levels acceptable'),
          AIVote(modelName: 'phantom',  snapshotId: 'mock', direction: 'BUY', confidence: 0.85, reasoning: 'Hidden divergence detected'),
          AIVote(modelName: 'titan',    snapshotId: 'mock', direction: 'BUY', confidence: 0.90, reasoning: 'Institutional volume surge'),
          AIVote(modelName: 'oracle',   snapshotId: 'mock', direction: 'SELL', confidence: 0.60, reasoning: 'Minor resistance ahead'),
          AIVote(modelName: 'atlas',    snapshotId: 'mock', direction: 'BUY', confidence: 0.82, reasoning: 'Macro structure intact'),
          AIVote(modelName: 'forge',    snapshotId: 'mock', direction: 'BUY', confidence: 0.87, reasoning: 'Structural break confirmed'),
        ],
        finalDirection: 'BUY',
        consensusPercentage: 85.7,
        proceed: true,
        isSimulated: true,
        timestamp: DateTime.now().toUtc(),
        tier: 'sovereign',
        drawings: [
          { 'action': 'draw_line', 'price': base - (base * 0.0003), 'color': '#00FF88', 'label': 'Support' },
          { 'action': 'draw_line', 'price': base + (base * 0.0003), 'color': '#FF3B3B', 'label': 'Resistance' },
          { 'action': 'draw_line', 'price': base + (base * 0.0008), 'color': '#FF3B3B', 'label': 'R2' },
        ],
      );
      _handleNewConsensus(mockResult, onStatusMsg);
    }
  }


  void _handleNewConsensus(ConsensusResult result, Function(String) onStatusMsg) {
    int maxVotes = 0;
    for (var dir in ['BUY', 'SELL', 'HOLD']) {
      int count = result.votes.where((v) => v.direction == dir).length;
      if (count > maxVotes) maxVotes = count;
    }
    
    bool isDeveloping = maxVotes == 7 && !result.proceed;
    bool isVetoed = !result.proceed && result.rejectionReason != null && result.rejectionReason!.contains("Math Layer Veto");
    bool isFrozen = !result.proceed && result.rejectionReason != null && result.rejectionReason!.contains("SENTINEL_HARD_FREEZE");

    bool justFlipped = btnState == ButtonState.developing && result.proceed;

    consensus = result;
    // Don't set aiCommands yet, store them so UI can trigger animation
    _pendingDrawings = result.drawings;
    isAnalyzing = false;
    isSentinelFrozen = isFrozen;
    
    if (isFrozen) {
      btnState = ButtonState.locked;
    } else if (isVetoed) {
      btnState = ButtonState.vetoed;
    } else if (isDeveloping) {
      btnState = ButtonState.developing;
    } else if (result.proceed) {
      btnState = result.finalDirection == 'BUY' 
          ? ButtonState.readyBuy 
          : ButtonState.readySell;
      
      if (justFlipped) {
        onStatusMsg(result.tier == 'sovereign' 
            ? "Unanimous. All 11 layers aligned.\nThis is the rarest signal in The Den.\nStrike with full force."
            : "The Den agrees. Strike now.");
      }
    } else {
      btnState = ButtonState.locked;
    }
    
    if (!feedbackShown) {
      Future.delayed(const Duration(seconds: 5), () {
        showFeedbackOption = true;
        notifyListeners();
        Future.delayed(const Duration(seconds: 8), () {
          if (showFeedbackOption) {
            showFeedbackOption = false;
            feedbackShown = true;
            notifyListeners();
          }
        });
      });
    }
    notifyListeners();
  }

  void hideFeedbackOption() {
    showFeedbackOption = false;
    feedbackShown = true;
    notifyListeners();
  }

  void overrideActiveSymbol(String sym) {
    activeSymbol = sym;
    notifyListeners();
  }
  
  void setActiveInterval(String interval) {
    activeInterval = interval;
    notifyListeners();
  }
  
  void overrideSentinelFrozen(bool frozen) {
    isSentinelFrozen = frozen;
    notifyListeners();
  }
  
  void clearConsensus() {
    consensus = null;
    aiCommands = [];
    notifyListeners();
  }

  void toggleDrawingMode(String mode) {
    drawingMode = mode;
    activeTool = 'none';
    notifyListeners();
  }

  void setActiveTool(String tool) {
    activeTool = activeTool == tool ? 'none' : tool;
    if (activeTool != 'none' && latestSnapshot != null) {
      final base = latestSnapshot!.close;
      double targetPrice = base;
      String label = 'Support';
      String color = '#00FF88';
      
      if (tool == 'support') {
        targetPrice = base - (base * 0.0012);
        label = 'MANUAL SUPPORT';
        color = '#00FF88';
      } else if (tool == 'resistance') {
        targetPrice = base + (base * 0.0012);
        label = 'MANUAL RESISTANCE';
        color = '#FF3B3B';
      } else if (tool == 'trendline') {
        targetPrice = base;
        label = 'MANUAL TRENDLINE';
        color = '#58A6FF';
      }

      aiCommands.add({
        'action': 'draw_line',
        'price': targetPrice,
        'color': color,
        'label': label,
      });
    }
    notifyListeners();
  }

  Future<void> validateManualLevel(double price) async {
    if (activeSymbol == null || latestSnapshot == null) return;
    
    // Simplistic local validation mimicking AI checking levels
    final double base = latestSnapshot!.close;
    // Assume previous AI command has some sort of support/resistance, but for demo, let's just make it randomly agree based on price action
    final bool aiAgrees = (price - base).abs() > (base * 0.001);

    aiCommands.add({
      'action': 'validate',
      'price': price,
      'agree': aiAgrees,
    });
    
    notifyListeners();
  }

  Map<String, dynamic>? _lastValidationResult;
  Map<String, dynamic>? get lastValidationResult => _lastValidationResult;

  @override
  void dispose() {
    _priceSub?.cancel();
    _firestoreSub?.cancel();
    super.dispose();
  }
}
