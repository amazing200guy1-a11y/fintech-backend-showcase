import 'package:flutter/material.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/core/api_service.dart';
import 'package:mehd_ai_flutter/models/executive_brief.dart';
import 'package:mehd_ai_flutter/widgets/executive_brief_dialog.dart';

class CommunityFundScreen extends StatefulWidget {
  const CommunityFundScreen({super.key});

  @override
  State<CommunityFundScreen> createState() => _CommunityFundScreenState();
}

class _CommunityFundScreenState extends State<CommunityFundScreen> with SingleTickerProviderStateMixin {
  late AnimationController _animController;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..forward();
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MehdAiTheme.bgPrimary,
      appBar: AppBar(
        title: Text('COMMUNITY FUND PUBLIC LEDGER', style: MehdAiTheme.headingStyle.copyWith(letterSpacing: 2)),
        backgroundColor: MehdAiTheme.bgSecondary,
        iconTheme: const IconThemeData(color: MehdAiTheme.textPrimary),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded, color: MehdAiTheme.green),
            tooltip: 'Share Performance',
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('Copied: Mehd AI Community Fund: +184.2% vs S&P 500 +22%. Join at mehdai.com'),
                backgroundColor: MehdAiTheme.green,
              ));
            },
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: MehdAiTheme.borderColor, height: 1),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            _buildMetricsHeader(),
            const SizedBox(height: 32),
            _buildPerformanceChart(),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      backgroundColor: MehdAiTheme.bgSecondary,
                      title: Text('JOIN THE FUND', style: MehdAiTheme.headingStyle.copyWith(color: MehdAiTheme.gold)),
                      content: Text('The Community Fund automatically executes trades based on the highest consensus setups. Access requires an active Network Membership.', style: MehdAiTheme.labelStyle),
                      actions: [
                        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('CLOSE', style: TextStyle(color: MehdAiTheme.textSecondary))),
                        ElevatedButton(
                          style: ElevatedButton.styleFrom(backgroundColor: MehdAiTheme.gold),
                          onPressed: () => Navigator.pop(ctx),
                          child: const Text('UNDERSTOOD', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                  );
                },
                icon: const Icon(Icons.rocket_launch, color: Colors.black, size: 16),
                label: const Text('JOIN THE COMMUNITY FUND', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, letterSpacing: 1)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: MehdAiTheme.green,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
            const SizedBox(height: 32),
            _buildLedgerList(),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricsHeader() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isMobile = constraints.maxWidth < 600;
        if (isMobile) {
          return Column(
            children: [
              Row(
                children: [
                  Expanded(child: _buildMetricCard('AUM', '\$14.2M')),
                  const SizedBox(width: 16),
                  Expanded(child: _buildMetricCard('Return', '+184.2%', color: MehdAiTheme.green)),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(child: _buildMetricCard('Win Rate', '81.4%')),
                  const SizedBox(width: 16),
                  Expanded(child: _buildMetricCard('Active Den', '24')),
                ],
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: _buildMetricCard('AUM (Paper)', '\$14.2M')),
            const SizedBox(width: 16),
            Expanded(child: _buildMetricCard('All-Time Return', '+184.2%', color: MehdAiTheme.green)),
            const SizedBox(width: 16),
            Expanded(child: _buildMetricCard('Win Rate', '81.4%')),
            const SizedBox(width: 16),
            Expanded(child: _buildMetricCard('Active Den Configs', '24')),
          ],
        );
      },
    );
  }

  Widget _buildMetricCard(String title, String value, {Color? color}) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: MehdAiTheme.bgSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MehdAiTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.verified_user, size: 14, color: MehdAiTheme.textSecondary),
              const SizedBox(width: 6),
              Text(title, style: MehdAiTheme.labelStyle),
            ],
          ),
          const SizedBox(height: 12),
          Text(value, style: MehdAiTheme.terminalStyle.copyWith(fontSize: 28, fontWeight: FontWeight.bold, color: color ?? MehdAiTheme.textPrimary)),
        ],
      ),
    );
  }

  Widget _buildPerformanceChart() {
    return Container(
      height: 400,
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: MehdAiTheme.bgSecondary,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: MehdAiTheme.borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 16,
            runSpacing: 8,
            children: [
              Text('PERFORMANCE VS BENCHMARKS', style: MehdAiTheme.headingStyle),
              _buildLegend('Mehd AI', MehdAiTheme.green),
              _buildLegend('S&P 500', MehdAiTheme.blue),
              _buildLegend('Gold', MehdAiTheme.yellow),
            ],
          ),
          const SizedBox(height: 32),
          Expanded(
            child: AnimatedBuilder(
              animation: _animController,
              builder: (context, child) {
                return Stack(
                  children: [
                    _buildGridLines(),
                    _buildPerformanceLine(MehdAiTheme.yellow, [100, 98, 105, 104, 112, 109, 118], 2.0, false, _animController.value),
                    _buildPerformanceLine(MehdAiTheme.blue, [100, 105, 102, 110, 108, 115, 122], 2.0, false, _animController.value),
                    _buildPerformanceLine(MehdAiTheme.green, [100, 120, 115, 140, 160, 200, 284], 4.0, true, _animController.value),
                  ],
                );
              }
            ),
          )
        ],
      ),
    );
  }

  Widget _buildGridLines() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(5, (_) => const Divider(color: MehdAiTheme.borderColor, thickness: 1)),
    );
  }

  Widget _buildLegend(String label, Color color) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
        const SizedBox(width: 6),
        Text(label, style: MehdAiTheme.labelStyle),
      ],
    );
  }

  Widget _buildPerformanceLine(Color color, List<double> points, double stroke, bool withGradient, double drawPercentage) {
    return CustomPaint(
      size: const Size(double.infinity, double.infinity),
      painter: _SparklinePainter(color: color, points: points, strokeWidth: stroke, withGradient: withGradient, drawPercentage: drawPercentage),
    );
  }


  Widget _buildLedgerList() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('RECENT PUBLIC EXECUTIONS', style: MehdAiTheme.headingStyle),
        const SizedBox(height: 16),
        Builder(builder: (context) => Column(children: [
          _buildLedgerRow(context, 'EUR/USD', 'BUY', '+42 pips', '2 mins ago', MehdAiTheme.green, 'cf-eurusd-001'),
          _buildLedgerRow(context, 'GBP/JPY', 'SELL', '+114 pips', '1 hour ago', MehdAiTheme.green, 'cf-gbpjpy-002'),
          _buildLedgerRow(context, 'XAU/USD', 'BUY', '-12 pips', '3 hours ago', MehdAiTheme.red, 'cf-xauusd-003'),
          _buildLedgerRow(context, 'BTC/USD', 'SELL', '+850 pips', '5 hours ago', MehdAiTheme.green, 'cf-btcusd-004'),
        ])),
      ],
    );
  }

  Widget _buildLedgerRow(BuildContext context, String pair, String dir, String result, String time, Color color, String tradeId) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        color: MehdAiTheme.bgSecondary,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: MehdAiTheme.borderColor),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            SizedBox(width: 70, child: Text(pair, style: MehdAiTheme.terminalStyle.copyWith(fontWeight: FontWeight.bold))),
            SizedBox(width: 50, child: Text(dir, style: MehdAiTheme.labelStyle)),
            SizedBox(width: 90, child: Text(result, style: MehdAiTheme.terminalStyle.copyWith(color: color, fontWeight: FontWeight.bold, fontSize: 16))),
            SizedBox(width: 80, child: Text(time, style: MehdAiTheme.labelStyle.copyWith(fontSize: 10))),
            TextButton(
               onPressed: () async {
                 final brief = await ApiService().getExecutiveBrief(tradeId) ?? ExecutiveBrief(
                   tradeId: tradeId,
                   symbol: pair,
                   timestamp: DateTime.now().subtract(const Duration(hours: 4)),
                   finalVerdict: dir,
                   consensusScore: '89.4%',
                   sentimentLayer: {'DON': 'Bullish orderflow imbalance', 'PHANTOM': 'Liquidity sweep confirmed'},
                   strategyLayer: {'CAESAR': 'Institutional orderblock retest', 'SAGE': 'Fair value gap fill'},
                   mathLayer: {'TITAN': 'Standard deviation within bounds', 'ATLAS': 'Monte Carlo EV > 2.4R'},
                   riskVerification: {'Max Risk': '1.00%', 'Stop Loss': 'Enforced'},
                   decisionBasis: 'High-conviction consensus across all 3 agent tiers. Target reached: $result.',
                 );
                 if (context.mounted) {
                   showDialog(context: context, builder: (_) => ExecutiveBriefDialog(brief: brief));
                 }
               },
               child: Text('VIEW BRIEF', style: MehdAiTheme.terminalStyle.copyWith(color: MehdAiTheme.blue, fontSize: 11)),
            )
          ],
        ),
      ),
    );
  }
}

class _SparklinePainter extends CustomPainter {
  final Color color;
  final List<double> points;
  final double strokeWidth;
  final bool withGradient;
  final double drawPercentage;

  _SparklinePainter({required this.color, required this.points, required this.strokeWidth, this.withGradient = false, this.drawPercentage = 1.0});

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;
    
    // Calculate how many points to draw based on percentage
    final double totalLength = (points.length - 1).toDouble();
    final double currentLength = totalLength * drawPercentage;
    final int completePoints = currentLength.floor();
    final double remainder = currentLength - completePoints;
    
    if (completePoints == 0 && remainder == 0) return;

    final paint = Paint()..color = color..strokeWidth = strokeWidth..style = PaintingStyle.stroke..strokeCap = StrokeCap.round;
    final path = Path();
    
    final double maxVal = points.reduce((a, b) => a > b ? a : b) * 1.1;
    final double minVal = points.reduce((a, b) => a < b ? a : b) * 0.9;
    final double stepX = size.width / (points.length - 1);
    
    double lastX = 0;
    double lastY = size.height - ((points[0] - minVal) / (maxVal - minVal) * size.height);
    path.moveTo(lastX, lastY);
    
    for (int i = 1; i <= completePoints; i++) {
      lastX = i * stepX;
      lastY = size.height - ((points[i] - minVal) / (maxVal - minVal) * size.height);
      path.lineTo(lastX, lastY);
    }
    
    // Draw the partial segment if there is a remainder and we haven't reached the end
    if (remainder > 0 && completePoints < points.length - 1) {
      final double nextX = (completePoints + 1) * stepX;
      final double nextY = size.height - ((points[completePoints + 1] - minVal) / (maxVal - minVal) * size.height);
      
      final double interpX = lastX + (nextX - lastX) * remainder;
      final double interpY = lastY + (nextY - lastY) * remainder;
      path.lineTo(interpX, interpY);
      lastX = interpX;
      lastY = interpY;
    }
    
    if (withGradient) {
      final gradientPath = Path.from(path)
        ..lineTo(lastX, size.height)
        ..lineTo(0, size.height)
        ..close();

      final paintGradient = Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withOpacity(0.3), color.withOpacity(0.0)],
        ).createShader(Rect.fromLTRB(0, 0, size.width, size.height))
        ..style = PaintingStyle.fill;
        
      canvas.drawPath(gradientPath, paintGradient);
    }
    
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true; // Always repaint when animating
}
