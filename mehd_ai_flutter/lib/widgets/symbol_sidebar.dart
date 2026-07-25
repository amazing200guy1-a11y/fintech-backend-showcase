import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mehd_ai_flutter/services/settings_service.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/core/constants.dart';
import 'package:mehd_ai_flutter/models/market_snapshot.dart';

/// FILE 5 — symbol_sidebar.dart
///
/// Build Debrief:
/// This is the left panel of our IDE-style layout. It purposefully mimics a code 
/// editor's file explorer. Instead of files, it lists trading pairs.
/// Grouping them by asset class (Forex, Commodities, Indices) makes it intuitive 
/// for a pro trader. The pulsing risk indicator at the bottom serves as a constant 
/// psychological reminder that the Hard Risk Kernel is active and guarding the account.

class SymbolSidebar extends StatefulWidget {
  final String activeSymbol;
  final Function(String) onSymbolSelected;
  final bool isExpanded;
  final VoidCallback onToggle;
  final MarketSnapshot? snapshot;

  const SymbolSidebar({
    super.key,
    required this.activeSymbol,
    required this.onSymbolSelected,
    required this.isExpanded,
    required this.onToggle,
    this.snapshot,
  });

  @override
  State<SymbolSidebar> createState() => _SymbolSidebarState();
}

class _SymbolSidebarState extends State<SymbolSidebar> {
  final Map<String, double?> _alerts = {};

  void _showAlertDialog(String symbol) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: MehdAiTheme.bgSecondary,
        title: Text('SET PRICE ALERT', style: MehdAiTheme.headingStyle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(symbol, style: MehdAiTheme.terminalStyle.copyWith(color: MehdAiTheme.blue, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: MehdAiTheme.terminalStyle,
              decoration: InputDecoration(
                labelText: 'Target Price',
                labelStyle: MehdAiTheme.labelStyle,
                enabledBorder: const OutlineInputBorder(borderSide: BorderSide(color: MehdAiTheme.borderColor)),
                focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: MehdAiTheme.blue)),
              ),
            ),
            if (_alerts[symbol] != null) ...[
              const SizedBox(height: 8),
              Text('Active alert: ${_alerts[symbol]!.toStringAsFixed(5)}', style: MehdAiTheme.labelStyle.copyWith(color: MehdAiTheme.yellow)),
            ],
          ],
        ),
        actions: [
          if (_alerts[symbol] != null)
            TextButton(
              onPressed: () {
                setState(() => _alerts.remove(symbol));
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(backgroundColor: MehdAiTheme.red, content: Text('Alert removed for $symbol', style: MehdAiTheme.terminalStyle)),
                );
              },
              child: Text('REMOVE', style: MehdAiTheme.terminalStyle.copyWith(color: MehdAiTheme.red)),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('CANCEL', style: MehdAiTheme.terminalStyle.copyWith(color: MehdAiTheme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              final price = double.tryParse(controller.text);
              if (price != null) {
                setState(() => _alerts[symbol] = price);
                Navigator.pop(ctx);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(backgroundColor: MehdAiTheme.green, content: Text('Alert set for $symbol at ${price.toStringAsFixed(5)}', style: MehdAiTheme.terminalStyle)),
                );
              }
            },
            child: Text('SET ALERT', style: MehdAiTheme.terminalStyle.copyWith(color: MehdAiTheme.green)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      width: widget.isExpanded ? 260 : 48,
      color: MehdAiTheme.bgSecondary,
      child: !widget.isExpanded
          ? GestureDetector(
              onTap: widget.onToggle,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 16.0),
                    child: Icon(Icons.view_sidebar_outlined, color: MehdAiTheme.textSecondary, size: 20),
                  ),
                ],
              ),
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header with toggle button
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'MARKETS EXPLORER',
                        style: MehdAiTheme.labelStyle.copyWith(
                          fontSize: 11,
                          letterSpacing: 1.2,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.view_sidebar_outlined, color: MehdAiTheme.textSecondary, size: 20),
                        onPressed: widget.onToggle,
                        tooltip: 'Collapse Markets Explorer',
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ],
                  ),
                ),

                // Symbol list
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      _buildSectionHeader('FOREX'),
                      ...AppConstants.symbols.sublist(0, 5).map((s) => _buildSymbolRow(s)),

                      const SizedBox(height: 12),
                      _buildSectionHeader('COMMODITIES'),
                      ...AppConstants.symbols.sublist(5, 6).map((s) => _buildSymbolRow(s)),

                      const SizedBox(height: 12),
                      _buildSectionHeader('CRYPTO'),
                      ...AppConstants.symbols.sublist(6, 8).map((s) => _buildSymbolRow(s)),

                      const SizedBox(height: 12),
                      _buildSectionHeader('INDICES'),
                      ...AppConstants.symbols.sublist(8).map((s) => _buildSymbolRow(s)),
                    ],
                  ),
                ),

                // Risk Kernel Status at bottom — live from SettingsService
                Consumer<SettingsService>(
                  builder: (context, settings, _) => Container(
                    padding: const EdgeInsets.all(16.0),
                    decoration: const BoxDecoration(
                      border: Border(top: BorderSide(color: MehdAiTheme.borderColor)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: MehdAiTheme.green,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('RISK KERNEL', style: MehdAiTheme.labelStyle.copyWith(fontSize: 10, color: MehdAiTheme.purple), overflow: TextOverflow.ellipsis),
                              Text('${settings.riskPerTrade.toStringAsFixed(1)}% per trade active', style: MehdAiTheme.labelStyle.copyWith(fontSize: 11, color: MehdAiTheme.textPrimary), overflow: TextOverflow.ellipsis),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          const Icon(Icons.keyboard_arrow_down, size: 14, color: MehdAiTheme.textSecondary),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              title,
              style: MehdAiTheme.labelStyle.copyWith(fontSize: 11, fontWeight: FontWeight.bold),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }



  Widget _buildSymbolRow(String symbol) {
    final isActive = symbol == widget.activeSymbol;
    final hasAlert = _alerts.containsKey(symbol);
    
    // Use live price if it's the active symbol, otherwise default
    String priceStr = '0.00000';
    if (isActive && widget.snapshot != null) {
      if (symbol.contains('BTC') || symbol.contains('ETH') || symbol.contains('XAU')) {
         priceStr = widget.snapshot!.close.toStringAsFixed(2);
      } else {
         priceStr = widget.snapshot!.close.toStringAsFixed(5);
      }
    }
    const changeStr = '0.00%';

    return Container(
      color: isActive ? MehdAiTheme.blue.withOpacity(0.1) : Colors.transparent,
      child: ListTile(
        onTap: () => widget.onSymbolSelected(symbol),
        dense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
        title: Row(
          children: [
            Flexible(
              child: Text(
                symbol,
                style: const TextStyle(
                  color: Color(0xFF888888),
                  fontSize: 13,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              priceStr,
              style: const TextStyle(
                color: Color(0xFFCCCCCC),
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(width: 8),
            const Text(
              changeStr,
              style: TextStyle(
                color: Color(0xFF888888), // Neutral gray for awaiting state
                fontSize: 10,
              ),
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(width: 8),
            Tooltip(
              message: hasAlert ? 'Edit Price Alert' : 'Set Price Alert',
              child: InkWell(
                onTap: () => _showAlertDialog(symbol),
                child: Icon(
                  hasAlert ? Icons.notifications_active : Icons.notifications_none,
                  size: 14,
                  color: hasAlert ? MehdAiTheme.yellow : (isActive ? MehdAiTheme.blue.withOpacity(0.5) : MehdAiTheme.textSecondary.withOpacity(0.3)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
