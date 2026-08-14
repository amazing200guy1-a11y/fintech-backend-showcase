import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mehd_ai_flutter/models/broker_model.dart';
import 'package:mehd_ai_flutter/services/settings_service.dart';
import 'package:mehd_ai_flutter/controllers/trading_controller.dart';

class BrokerConnectedStateCard extends StatelessWidget {
  final Broker broker;
  final VoidCallback onDispute;
  final VoidCallback onDisconnect;

  const BrokerConnectedStateCard({
    super.key,
    required this.broker,
    required this.onDispute,
    required this.onDisconnect,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: broker.color.withOpacity(0.05),
            border: Border.all(color: broker.color.withOpacity(0.3)),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: broker.color.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.link, color: broker.color, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            broker.name.toUpperCase(),
                            style: TextStyle(color: broker.color, fontSize: 16, letterSpacing: 1, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'ACTIVE CONNECTOR • ENCRYPTED',
                            style: TextStyle(color: Color(0xFF2ED573), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 1),
                          ),
                        ],
                      ),
                    ],
                  ),
                  TextButton(
                    onPressed: onDisconnect,
                    style: TextButton.styleFrom(foregroundColor: const Color(0xFFFF4757)),
                    child: const Text('DISCONNECT', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: onDispute,
                icon: const Icon(Icons.gavel_rounded, color: Color(0xFFFFAB00), size: 14),
                label: const Text(
                  'DISPUTE SLIPPAGE / SPREAD SPIKE',
                  style: TextStyle(color: Color(0xFFFFAB00), fontSize: 10, fontWeight: FontWeight.bold, letterSpacing: 0.8),
                ),
                style: OutlinedButton.styleFrom(
                  backgroundColor: const Color(0xFFFFAB00).withOpacity(0.06),
                  side: BorderSide(color: const Color(0xFFFFAB00).withOpacity(0.3)),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class BrokerPaperTradingCard extends StatelessWidget {
  const BrokerPaperTradingCard({super.key});

  @override
  Widget build(BuildContext context) {
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
}

class BrokerFraudChip extends StatelessWidget {
  final String label;
  final bool aiVerified;

  const BrokerFraudChip({
    super.key,
    required this.label,
    required this.aiVerified,
  });

  @override
  Widget build(BuildContext context) {
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
}

