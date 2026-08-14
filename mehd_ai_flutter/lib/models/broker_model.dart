import 'package:flutter/material.dart';

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
  
  // Broker Health Metrics (The 4 Pillars)
  final int healthScore;
  final double avgSlippage;       // Price Accuracy
  final int executionLatency;     // Execution Speed
  final int withdrawalHonesty;    // Withdrawal & Account Honesty
  final String spreadStability;   // Spread Stability
  
  final TrustTier trustTier;
  final String warningMessage;
  final List<String> fraudTags;

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
    this.fraudTags = const [],
  });

  bool get isHighRisk => trustTier == TrustTier.marketMaker || healthScore < 75;

  double estimatedMonthlySlippageCost([double standardLotsPerMonth = 10.0]) {
    // 1 pip on 1 standard lot = $10.00
    // Extra slippage cost beyond institutional 0.2 pip benchmark:
    final extraSlippagePips = (avgSlippage - 0.2).clamp(0.0, 10.0);
    return extraSlippagePips * 10.0 * standardLotsPerMonth;
  }

  static const List<Broker> defaultBrokers = [
    Broker(
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
    Broker(
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
    Broker(
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
    Broker(
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
    Broker(
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
    Broker(
      id: 'mt5', 
      name: 'Universal MT5', 
      initials: 'M5', 
      type: 'Any Broker', 
      color: Color(0xFF888888),
      healthScore: 90,
      avgSlippage: 0.5,
      executionLatency: 50,
      withdrawalHonesty: 95,
      spreadStability: '90%',
      trustTier: TrustTier.universal,
    ),
  ];
}
