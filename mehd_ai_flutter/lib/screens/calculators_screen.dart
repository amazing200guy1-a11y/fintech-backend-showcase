import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/services/settings_service.dart';

class CalculatorsScreen extends StatefulWidget {
  const CalculatorsScreen({super.key});

  @override
  State<CalculatorsScreen> createState() => _CalculatorsScreenState();
}

class _CalculatorsScreenState extends State<CalculatorsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Position Size State
  final _balanceController = TextEditingController(text: '10000');
  final _riskController = TextEditingController(text: '1.0');
  final _stopLossController = TextEditingController(text: '20');

  // Pip Value State
  final _pipLotController = TextEditingController(text: '1.0');

  // Margin State
  final _marginLotController = TextEditingController(text: '1.0');
  final _leverageController = TextEditingController(text: '100');

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    
    // Defer reading from Provider to after build context is fully ready
    Future.microtask(() {
      if (!mounted) return; // Guard: widget may have been disposed before microtask fires
      final settings = context.read<SettingsService>();
      _balanceController.text = '${settings.accountBalance}';
      _riskController.text = '${settings.riskPerTrade}';
      _stopLossController.text = '${settings.defaultStopLoss}';
      _leverageController.text = '${settings.defaultLeverage}';
      _pipLotController.text = '${settings.defaultLotSize}';
      _marginLotController.text = '${settings.defaultLotSize}';
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _balanceController.dispose();
    _riskController.dispose();
    _stopLossController.dispose();
    _pipLotController.dispose();
    _marginLotController.dispose();
    _leverageController.dispose();
    super.dispose();
  }

  void _syncSettings() {
    final settings = context.read<SettingsService>();
    final bal = double.tryParse(_balanceController.text);
    if (bal != null) settings.setAccountBalance(bal);
    final risk = double.tryParse(_riskController.text);
    if (risk != null) settings.setRiskPerTrade(risk);
    final sl = double.tryParse(_stopLossController.text);
    if (sl != null) settings.setDefaultStopLoss(sl);
    final lev = double.tryParse(_leverageController.text);
    if (lev != null) settings.setDefaultLeverage(lev);
    final pipLot = double.tryParse(_pipLotController.text);
    if (pipLot != null) settings.setDefaultLotSize(pipLot);
  }

  double _calculatePositionSize() {
    final balance = double.tryParse(_balanceController.text) ?? 0.0;
    final risk = double.tryParse(_riskController.text) ?? 0.0;
    final sl = double.tryParse(_stopLossController.text) ?? 0.0;

    if (balance <= 0 || risk <= 0 || sl <= 0) return 0.0;

    final riskAmount = balance * (risk / 100);
    // Assuming $10 per pip for 1 standard lot (e.g., EUR/USD)
    final lotSize = riskAmount / (sl * 10);
    return lotSize;
  }

  double _calculatePipValue() {
    final lots = double.tryParse(_pipLotController.text) ?? 0.0;
    // Standard $10 per pip per lot
    return lots * 10.0;
  }

  double _calculateMargin() {
    final lots = double.tryParse(_marginLotController.text) ?? 0.0;
    final leverage = double.tryParse(_leverageController.text) ?? 1.0;
    if (leverage <= 0) return 0.0;

    // 1 Standard Lot = 100,000 units
    final positionValue = lots * 100000.0;
    return positionValue / leverage;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MehdAiTheme.background(context),
      appBar: AppBar(
        backgroundColor: MehdAiTheme.surface(context),
        elevation: 0,
        title: Row(
          children: [
            const Icon(Icons.calculate, color: MehdAiTheme.blue, size: 20),
            const SizedBox(width: 8),
            Text('TERMINAL CALCULATORS', style: MehdAiTheme.labelStyle),
          ],
        ),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          indicatorColor: MehdAiTheme.blue,
          labelColor: MehdAiTheme.blue,
          unselectedLabelColor: MehdAiTheme.textSecondary,
          labelStyle: MehdAiTheme.labelStyle.copyWith(fontSize: 10),
          tabs: const [
            Tab(text: 'POSITION'),
            Tab(text: 'PIP VALUE'),
            Tab(text: 'MARGIN'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildPositionSizeTab(),
          _buildPipValueTab(),
          _buildMarginTab(),
        ],
      ),
    );
  }

  Widget _buildPositionSizeTab() {
    final lots = _calculatePositionSize();
    final balance = double.tryParse(_balanceController.text) ?? 0.0;
    final risk = double.tryParse(_riskController.text) ?? 0.0;
    final riskAmount = balance * (risk / 100);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('POSITION SIZE ENGINE',
              style: MehdAiTheme.headingStyle
                  .copyWith(fontSize: 14, color: MehdAiTheme.textSecondary)),
          const SizedBox(height: 24),
          _buildInputField('Account Balance (\$)', _balanceController),
          _buildInputField('Risk Percentage (%)', _riskController),
          _buildInputField('Stop Loss (Pips)', _stopLossController),
          const SizedBox(height: 32),
          _buildResultDisplay('APPROVED LOT SIZE',
              '\u{25B2} ${lots.toStringAsFixed(2)} LOTS', MehdAiTheme.green),
          const SizedBox(height: 16),
          _buildSecondaryResult(
              'Capital at Risk', '\$${riskAmount.toStringAsFixed(2)}'),
        ],
      ),
    );
  }

  Widget _buildPipValueTab() {
    final pipValue = _calculatePipValue();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PIP VALUE CALCULATOR',
              style: MehdAiTheme.headingStyle
                  .copyWith(fontSize: 14, color: MehdAiTheme.textSecondary)),
          const SizedBox(height: 8),
          Text('Assuming USD Quote Currency (e.g. EUR/USD, GBP/USD)',
              style:
                  TextStyle(color: MehdAiTheme.textDim(context), fontSize: 12)),
          const SizedBox(height: 24),
          _buildInputField('Trade Size (Lots)', _pipLotController),
          const SizedBox(height: 32),
          _buildResultDisplay('VALUE PER PIP',
              '\$${pipValue.toStringAsFixed(2)}', MehdAiTheme.blue),
        ],
      ),
    );
  }

  Widget _buildMarginTab() {
    final margin = _calculateMargin();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('REQUIRED MARGIN ESTIMATOR',
              style: MehdAiTheme.headingStyle
                  .copyWith(fontSize: 14, color: MehdAiTheme.textSecondary)),
          const SizedBox(height: 24),
          _buildInputField('Trade Size (Lots)', _marginLotController),
          _buildInputField('Leverage (1:X)', _leverageController),
          const SizedBox(height: 32),
          _buildResultDisplay('REQUIRED MARGIN',
              '\$${margin.toStringAsFixed(2)}', MehdAiTheme.purple),
          const SizedBox(height: 16),
          _buildSecondaryResult('Notional Value',
              '\$${((double.tryParse(_marginLotController.text) ?? 0.0) * 100000).toStringAsFixed(0)}'),
        ],
      ),
    );
  }

  Widget _buildInputField(String label, TextEditingController controller) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: MehdAiTheme.labelStyle
                  .copyWith(color: MehdAiTheme.textSecondary)),
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.03),
              border: Border.all(color: Colors.white.withOpacity(0.1)),
              borderRadius: BorderRadius.circular(8),
            ),
            child: TextField(
              controller: controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'JetBrains Mono',
                  fontSize: 16),
              onChanged: (_) {
                setState(() {});
                _syncSettings();
              },
              decoration: const InputDecoration(
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultDisplay(String label, String value, Color accentColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: accentColor.withOpacity(0.05),
        border: Border.all(color: accentColor.withOpacity(0.3)),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: accentColor.withOpacity(0.1), blurRadius: 20),
        ],
      ),
      child: Column(
        children: [
          Text(label,
              style: MehdAiTheme.labelStyle
                  .copyWith(color: accentColor, letterSpacing: 2.0)),
          const SizedBox(height: 12),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                color: accentColor,
                fontFamily: 'JetBrains Mono',
                fontSize: 32,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecondaryResult(String label, String value) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.02),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(color: MehdAiTheme.textSecondary, fontSize: 13)),
          Text(value,
              style: const TextStyle(
                  color: Colors.white,
                  fontFamily: 'JetBrains Mono',
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
