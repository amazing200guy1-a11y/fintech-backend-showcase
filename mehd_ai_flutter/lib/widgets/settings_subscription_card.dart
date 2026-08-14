import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/services/payment_service.dart';

class SettingsSubscriptionCard extends StatelessWidget {
  final Color Function(String) getTierColor;
  final String Function(String) getTierName;
  final String Function(String) getTierPrice;
  final Widget Function(BuildContext, String, String, IconData, List<Color>, Color, VoidCallback) build3DCard;
  final VoidCallback onManageTap;

  const SettingsSubscriptionCard({
    super.key,
    required this.getTierColor,
    required this.getTierName,
    required this.getTierPrice,
    required this.build3DCard,
    required this.onManageTap,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<PaymentService>(
      builder: (ctx, payment, _) {
        final tier = payment.currentTier;
        final tierColor = getTierColor(tier);
        final tierName = getTierName(tier);
        final isObserver = tier == 'observer' && !payment.isOnTrial;

        return Column(
          children: [
            if (payment.isOnTrial) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: MehdAiTheme.gold.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: MehdAiTheme.gold.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.star_rounded, color: MehdAiTheme.gold, size: 18),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('FREE TRIAL ACTIVE',
                              style: TextStyle(color: MehdAiTheme.gold, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                          Text('${payment.trialDaysRemaining} day${payment.trialDaysRemaining == 1 ? '' : 's'} remaining — Institutional access',
                              style: const TextStyle(color: Color(0xFF888888), fontSize: 10)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: tierColor.withOpacity(0.05),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: tierColor.withOpacity(0.2)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('CURRENT PLAN', style: TextStyle(color: tierColor.withOpacity(0.6), fontSize: 9, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 4),
                      Text(tierName, style: TextStyle(color: tierColor, fontSize: 14, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  Text(
                    isObserver ? 'FREE' : '\$${getTierPrice(tier)}/mo',
                    style: TextStyle(color: tierColor, fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Builder(
              builder: (ctx) {
                final bool isMobileApp = !kIsWeb && (defaultTargetPlatform == TargetPlatform.iOS || defaultTargetPlatform == TargetPlatform.android);
                return build3DCard(
                  context,
                  isObserver ? 'Upgrade Account' : 'Manage Billing',
                  isMobileApp
                      ? 'Manage billing through your desktop browser'
                      : (isObserver ? 'View plans on the Mehd AI website' : 'Update payment method or cancel'),
                  isObserver ? Icons.rocket_launch_rounded : Icons.credit_card_rounded,
                  isObserver
                      ? const [Color(0xFF0A2040), Color(0xFF051020)]
                      : const [Color(0xFF1A2030), Color(0xFF0F1520)],
                  isObserver ? MehdAiTheme.blue : tierColor,
                  onManageTap,
                );
              },
            ),
          ],
        );
      },
    );
  }
}
