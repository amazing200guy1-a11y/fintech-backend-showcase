import 'package:flutter/material.dart';
import 'package:mehd_ai_flutter/core/theme.dart';

class PendingOrdersList extends StatelessWidget {
  final List<Map<String, dynamic>> pendingOrders;
  final Function(String) onCancelOrder;

  const PendingOrdersList({
    super.key,
    required this.pendingOrders,
    required this.onCancelOrder,
  });

  @override
  Widget build(BuildContext context) {
    if (pendingOrders.isEmpty) {
      return _buildEmptyState(
        Icons.pending_actions_rounded,
        'No Pending Orders',
        'Limit and stop orders will appear here',
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: pendingOrders.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final order = pendingOrders[index];
        final isBuy = order['side'] == 'BUY';
        final color = isBuy ? MehdAiTheme.green : MehdAiTheme.red;

        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: MehdAiTheme.bgSecondary,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: MehdAiTheme.borderColor),
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 40,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          order['symbol'] ?? 'EURUSD',
                          style: MehdAiTheme.headingStyle.copyWith(fontSize: 14),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: color.withOpacity(0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${order['type'] ?? 'LIMIT'} ${order['side'] ?? 'BUY'}',
                            style: TextStyle(
                              color: color,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Target Price: ${order['targetPrice'] ?? '1.0850'} | Size: ${order['lotSize'] ?? '0.1'} Lots',
                      style: MehdAiTheme.labelStyle.copyWith(fontSize: 11),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.cancel_outlined, color: MehdAiTheme.red, size: 20),
                onPressed: () => onCancelOrder(order['id'] ?? ''),
                tooltip: 'Cancel Order',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(IconData icon, String title, String subtitle) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 48, color: MehdAiTheme.textSecondary.withOpacity(0.4)),
          const SizedBox(height: 12),
          Text(title, style: MehdAiTheme.headingStyle.copyWith(fontSize: 15)),
          const SizedBox(height: 4),
          Text(subtitle, style: MehdAiTheme.labelStyle.copyWith(color: MehdAiTheme.textSecondary)),
        ],
      ),
    );
  }
}
