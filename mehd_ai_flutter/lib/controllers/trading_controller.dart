import 'dart:ui';
import 'dart:math' as math;
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mehd_ai_flutter/core/api_service.dart';
import 'package:mehd_ai_flutter/core/constants.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/models/account_health.dart';
import 'package:mehd_ai_flutter/models/consensus_result.dart';
import 'package:mehd_ai_flutter/models/market_snapshot.dart';
import 'package:mehd_ai_flutter/models/trade.dart';
import 'package:mehd_ai_flutter/core/input_validator.dart';
import 'package:mehd_ai_flutter/core/performance_tracker.dart';
import 'package:mehd_ai_flutter/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TradingController extends ChangeNotifier {
  bool _paperMode = true;
  bool get isPaperMode => _paperMode;
  
  void setPaperMode(bool paper) {
    _paperMode = paper;
    notifyListeners();
  }

  bool legalAccepted = false;
  int paperTradesCompleted = 0;
  ButtonState btnState = ButtonState.locked;
  bool isTradeProcessing = false;
  
  final ApiService _apiService = ApiService();
  final PerformanceTracker _perf = PerformanceTracker();
  final List<Trade> recentTrades = [];
  
  // LIVE POSITIONS STATE (Billion Dollar Phase)
  final List<Map<String, dynamic>> activePositions = [];
  Timer? _volatilityTimer;

  TradingController() {
    _loadLegalStatus();
  }

  // == SANDBOX EXECUTION ENGINE ==
  void executeSandboxTrade(String symbol, String direction, double entryPrice, {double lotSize = 1.0}) {
    final ticketId = "TRD-${math.Random().nextInt(9999).toString().padLeft(4, '0')}";
    activePositions.add({
      "id": ticketId,
      "symbol": symbol,
      "type": direction,
      "entry": entryPrice,
      "current": entryPrice, // Starts at entry
      "lotSize": lotSize,
      "pnl": 0.0,            // Starts at $0
    });
    
    notifyListeners();
    _startVolatilitySimulation();
  }

  void closeAllPositions() {
    activePositions.clear();
    _volatilityTimer?.cancel();
    _volatilityTimer = null;
    notifyListeners();
  }
  
  void closePosition(String id) {
    activePositions.removeWhere((pos) => pos['id'] == id);
    if (activePositions.isEmpty) {
      _volatilityTimer?.cancel();
      _volatilityTimer = null;
    }
    notifyListeners();
  }

  void closePartialPosition(String id, double ratio) {
    final idx = activePositions.indexWhere((pos) => pos['id'] == id);
    if (idx != -1) {
      final pos = activePositions[idx];
      final currentLot = (pos['lotSize'] as num).toDouble();
      final currentPnl = (pos['pnl'] as num).toDouble();
      
      final newLot = currentLot * (1 - ratio);
      if (newLot <= 0.01) {
        closePosition(id);
      } else {
        pos['lotSize'] = newLot;
        pos['pnl'] = currentPnl * (1 - ratio);
        pos['partialBanked'] = true;
        notifyListeners();
      }
    }
  }

  void setBreakevenSL(String id) {
    final idx = activePositions.indexWhere((pos) => pos['id'] == id);
    if (idx != -1) {
      activePositions[idx]['sl'] = activePositions[idx]['entry'];
      activePositions[idx]['isBreakevenArmed'] = true;
      notifyListeners();
    }
  }

  void _startVolatilitySimulation() {
    if (_volatilityTimer != null && _volatilityTimer!.isActive) return;
    
    // Updates every 1.5 seconds to simulate market ticking
    _volatilityTimer = Timer.periodic(const Duration(milliseconds: 1500), (timer) {
      bool changed = false;
      for (var pos in activePositions) {
        // Randomly swing PnL between -$50 and +$150 to simulate a volatile, winning bot
        final swing = (math.Random().nextDouble() * 200) - 50; 
        pos['pnl'] = (pos['pnl'] as double) + swing;
        
        // Slightly shift the current price as well just for aesthetics
        final priceShift = (math.Random().nextDouble() * 0.0005) - 0.00025;
        pos['current'] = (pos['current'] as double) + priceShift;
        changed = true;
      }
      if (changed) notifyListeners();
    });
  }
  // ==============================

  Future<void> init() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _paperMode = prefs.getBool('paper') ?? true;
      notifyListeners();
    } catch (e) {
      debugPrint("TradingController: Failed to init SharedPreferences: $e");
    }
  }

  Future<void> _loadLegalStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      legalAccepted = prefs.getBool('legal_accepted') ?? false;
      _paperMode = prefs.getBool('paper') ?? true;
      notifyListeners();
    } catch (e) {
      debugPrint("TradingController: Failed to load legal accepted status: $e");
    }
  }

  Future<void> acceptLegal() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('legal_accepted', true);
      legalAccepted = true;
      notifyListeners();
    } catch (e) {
      debugPrint("TradingController: Failed to save accepted legal status: $e");
      legalAccepted = true;
      notifyListeners();
    }
  }

  void togglePaperMode() {
    setPaperMode(!_paperMode);
  }
  
  void validateTrade(AccountHealth? health) {
    // move existing validation here
  }

  Future<void> executeTrade({
    required BuildContext context,
    required ConsensusResult? consensus,
    required MarketSnapshot? latestSnapshot,
    required Function(String) showError,
    required VoidCallback onSuccess,
    required Function(dynamic) onShowBrief,
    required Function(dynamic) onShowAudit,
  }) async {
    if (consensus == null || latestSnapshot == null) return;

    if (isTradeProcessing) return;

    if (_perf.isPriceStale) {
      showError('Price data is stale (>5s old). Trading locked for your safety.');
      return;
    }

    if (DuplicateTradeGuard.isDuplicate(latestSnapshot.symbol, consensus.finalDirection)) {
      showError('Duplicate trade blocked. Wait 5 seconds between identical trades.');
      return;
    }

    if (!legalAccepted) {
      showError('You must accept the Terms of Service before trading.');
      return;
    }

    if (paperTradesCompleted < 10) {
      showDialog(
        context: context,
        builder: (ctx) => BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: AlertDialog(
            backgroundColor: const Color(0xCC000000), // rgba(0,0,0,0.8) equivalent approx
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: const Color(0xFF58A6FF).withOpacity(0.15), width: 0.5),
            ),
            title: Text('Paper Trading Required', style: MehdAiTheme.headingStyle),
            content: Text(
              'You have completed $paperTradesCompleted/10 paper trades.\n\n'
              'Complete at least 10 paper trades before live trading. '
              'This protects you from mistakes while you learn.',
              style: MehdAiTheme.labelStyle,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text('Understood', style: MehdAiTheme.terminalStyle.copyWith(color: MehdAiTheme.blue)),
              ),
            ],
          ),
        ),
      );
      return;
    }

    // FIX C1: AccountHealth is not registered in the Provider tree.
    // Use SettingsService.accountBalance instead — it's the same source of truth.
    final double equity = context.read<SettingsService>().accountBalance;
    
    // Read risk % from the global settings (the manual calculator state)
    final double riskPercent = context.read<SettingsService>().riskPerTrade;
    
    // Default stop loss if not provided
    final double stopLoss = (consensus.finalDirection == 'BUY' ? latestSnapshot.bid - 0.0050 : latestSnapshot.ask + 0.0050);
    
    final double slDistance = (latestSnapshot.bid - stopLoss).abs();
    final double slPips = slDistance * (latestSnapshot.symbol.contains('JPY') ? 100 : 10000);
    
    // Calculate lot size to risk exactly the user's set percentage of equity
    // RiskAmount = Equity * (riskPercent / 100)
    // LotSize = RiskAmount / (slPips * 10) [assuming $10/pip for 1.0 lot]
    double calculatedLot = (equity * (riskPercent / 100)) / (math.max(slPips, 5.0) * 10);
    final lotSize = calculatedLot.clamp(0.01, 100.0);

    final validationError = InputValidator.validateTradeOrder(
      symbol: latestSnapshot.symbol,
      direction: consensus.finalDirection,
      lotSize: lotSize,
      entryPrice: latestSnapshot.bid,
      stopLoss: stopLoss,
    );
    
    if (validationError != null) {
      showError(validationError);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: AlertDialog(
          backgroundColor: const Color(0xCC000000), // rgba(0,0,0,0.8) approx
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: const Color(0xFF58A6FF).withOpacity(0.15), width: 0.5),
          ),
          title: Row(
            children: [
              Icon(consensus.finalDirection == 'BUY' ? Icons.trending_up : Icons.trending_down,
                color: consensus.finalDirection == 'BUY' ? MehdAiTheme.green : MehdAiTheme.red),
              const SizedBox(width: 12),
              Text('Confirm Trade Execution', style: MehdAiTheme.headingStyle),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${consensus.finalDirection} ${latestSnapshot.symbol}', style: MehdAiTheme.terminalStyle.copyWith(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Text('Entry: ${latestSnapshot.bid.toStringAsFixed(5)}', style: MehdAiTheme.labelStyle),
              Text('SL: ${stopLoss.toStringAsFixed(5)}', style: MehdAiTheme.labelStyle),
              Text('Lot Size: ${lotSize.toStringAsFixed(2)}', style: MehdAiTheme.labelStyle),
              Text('Consensus: ${consensus.consensusPercentage.toStringAsFixed(1)}%', style: MehdAiTheme.labelStyle),
              const SizedBox(height: 16),
              Text('Risk: ${riskPercent.toStringAsFixed(1)}% of \$${equity.toStringAsFixed(0)} equity — enforced by SentinelKernel.', style: MehdAiTheme.labelStyle.copyWith(color: MehdAiTheme.gold)),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel', style: MehdAiTheme.terminalStyle.copyWith(color: MehdAiTheme.textSecondary)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: consensus.finalDirection == 'BUY' ? MehdAiTheme.green : MehdAiTheme.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('EXECUTE ${consensus.finalDirection}', style: MehdAiTheme.terminalStyle.copyWith(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    btnState = ButtonState.executing;
    isTradeProcessing = true;
    notifyListeners();
    
    final order = TradeOrder(
      symbol: latestSnapshot.symbol,
      direction: consensus.finalDirection,
      lotSize: lotSize, 
      stopLoss: stopLoss,
      votes: consensus.votes,
    );
    
    final decision = await _apiService.executeTrade(order);

    isTradeProcessing = false;
    btnState = decision.approved ? ButtonState.filled : ButtonState.locked;
    notifyListeners();
    
    if (!decision.approved) {
      showError('Trade Rejected: ${decision.rejectionReason}');
    } else {
      // Increment counter ONLY on successful execution
      paperTradesCompleted++;
      
      // Improved Win/Loss Logic: Based on Consensus Strength
      // Higher consensus = higher probability of "simulated" win
      final rand = math.Random().nextDouble() * 100;
      final bool isWin = rand < consensus.consensusPercentage; 
      
      final double entry = latestSnapshot.bid;
      final double exit = isWin 
          ? (consensus.finalDirection == 'BUY' ? entry + 0.0050 : entry - 0.0050)
          : (consensus.finalDirection == 'BUY' ? entry - 0.0020 : entry + 0.0020);

      recentTrades.add(Trade(
        symbol: latestSnapshot.symbol,
        direction: consensus.finalDirection,
        entryPrice: entry,
        latestPrice: exit,
        timestamp: DateTime.now(),
        consensusScore: consensus.consensusPercentage,
      ));
      
      if (isWin && consensus.consensusPercentage >= 75.0) {
        Future.delayed(const Duration(seconds: 1), () async {
          final brief = await _apiService.getExecutiveBrief(decision.id);
          if (brief != null) onShowBrief(brief);
        });
      } else if (!isWin) {
        Future.delayed(const Duration(milliseconds: 500), () async {
          try {
            final auditData = {
              "trade_id": decision.id,
              "symbol": latestSnapshot.symbol,
              "direction": consensus.finalDirection,
              "entry_price": entry,
              "exit_price": exit,
              "pnl": -50.0,
              "user_notes": "Trade went against consensus momentum."
            };
            
            final response = await _apiService.performAudit(auditData);
            if (response != null) onShowAudit(response);
          } catch (e) {
            debugPrint("Audit failed: $e");
          }
        });
      }
      
      Future.delayed(const Duration(seconds: 2), () {
        btnState = ButtonState.locked;
        notifyListeners();
      });
      
      onSuccess();
    }
  }
}
