import 'package:flutter/material.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:url_launcher/url_launcher.dart';

/// Modal bottom sheet allowing users to view and select subscription tiers.
class SubscriptionTierModal extends StatelessWidget {
  const SubscriptionTierModal({super.key});

  static void show(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SubscriptionTierModal(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
      decoration: const BoxDecoration(
        color: Color(0xFF0D1117),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        border: Border(top: BorderSide(color: Color(0xFF21262D), width: 1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 20),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFF30363D),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'CHOOSE YOUR PLAN',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    '3-Day Free Trial on all plans. Cancel anytime.',
                    style: TextStyle(color: Color(0xFF888888), fontSize: 12),
                  ),
                  const SizedBox(height: 20),

                  // Core Trader Card ($79/mo)
                  _buildTierCard(
                    context: context,
                    name: 'CORE TRADER',
                    price: '\$79',
                    color: MehdAiTheme.blue,
                    features: [
                      '24/5 Autonomous 11-Agent Swarm',
                      '1 Broker Connection',
                      'Guided Strike Sandbox Execution',
                      'Broker Shield Safeguard',
                      'Terminal Intelligence & Calculators',
                    ],
                    ctaLabel: 'Start 3-Day Free Trial',
                    url: 'https://mehdai.com/#pricing',
                  ),
                  const SizedBox(height: 12),

                  // Precision Trader Card ($149/mo)
                  _buildTierCard(
                    context: context,
                    name: 'PRECISION TRADER',
                    price: '\$149',
                    color: const Color(0xFFBB00FF),
                    features: [
                      '24/5 Autonomous 11-Agent Swarm',
                      'Multi-Broker (2 Brokers + 1 Prop Firm)',
                      'Instant Smart Auto-Execution',
                      'ECN Spread Verification & Anti-Slippage',
                      'Advanced Signal Filtering & Sizing',
                    ],
                    ctaLabel: 'Start 3-Day Free Trial',
                    url: 'https://mehdai.com/#pricing',
                  ),
                  const SizedBox(height: 12),

                  // Institutional Card ($299/mo)
                  _buildTierCard(
                    context: context,
                    name: 'INSTITUTIONAL',
                    price: '\$299',
                    color: MehdAiTheme.gold,
                    features: [
                      '24/5 Autonomous 11-Agent Swarm',
                      'Unlimited Brokers & Prop Firm Sync',
                      'Hands-Free Sovereign Execution',
                      'DON Push Alerts & MAM Account Sync',
                      'Full Institutional Forensic Audit Access',
                    ],
                    ctaLabel: 'Start 3-Day Free Trial',
                    url: 'https://mehdai.com/#pricing',
                    isFeatured: true,
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTierCard({
    required BuildContext context,
    required String name,
    required String price,
    required Color color,
    required List<String> features,
    required String ctaLabel,
    required String url,
    bool isFeatured = false,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(isFeatured ? 0.08 : 0.04),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(isFeatured ? 0.5 : 0.2), width: isFeatured ? 1.5 : 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(name, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(price, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold)),
                  const Text('/mo', style: TextStyle(color: Color(0xFF888888), fontSize: 11)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...features.map((f) => Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              children: [
                Icon(Icons.check_circle_rounded, color: color, size: 14),
                const SizedBox(width: 8),
                Text(f, style: const TextStyle(color: Color(0xFFCCCCCC), fontSize: 12)),
              ],
            ),
          )),
          const SizedBox(height: 14),
          GestureDetector(
            onTap: () async {
              final uri = Uri.parse(url);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: color.withOpacity(isFeatured ? 0.2 : 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: color.withOpacity(0.4)),
              ),
              child: Text(
                ctaLabel,
                textAlign: TextAlign.center,
                style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.bold, letterSpacing: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
