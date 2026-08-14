import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mehd_ai_flutter/core/theme.dart';

/// FIX 3: Terms of Service screen — accessible from settings without login.

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MehdAiTheme.bgPrimary,
      appBar: AppBar(
        title: Text('Terms of Service', style: GoogleFonts.outfit(fontWeight: FontWeight.bold)),
        backgroundColor: MehdAiTheme.bgSecondary,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Text(
          '''MEHD AI — TERMS OF SERVICE
Last updated: March 2026

1. EDUCATIONAL USE ONLY
Mehd AI is an educational tool. It does not constitute financial advice, investment recommendations, or a solicitation to trade financial instruments. The information provided by the AI models is generated algorithmically and may contain errors.

2. NO LIABILITY
Mehd AI, its creators, contributors, and affiliates accept no liability whatsoever for trading losses, missed opportunities, or any financial decisions made using this platform. You trade entirely at your own risk.

3. AI LIMITATIONS
The 11-agent consensus system ("The Den") uses artificial intelligence models from third-party providers. These models can hallucinate, produce contradictory outputs, or fail to account for breaking events. A consensus vote does not guarantee a profitable trade.

4. DATA ACCURACY
Market data is provided by third-party APIs (OANDA, Polygon, TwelveData). Mehd AI makes no guarantee about the accuracy, timeliness, or completeness of this data. Stale data is flagged but may still be inaccurate.

5. PAPER TRADING REQUIREMENT
All new users must complete a minimum of 10 paper (simulated) trades and maintain an account for at least 7 days before live trading is unlocked. This is a mandatory safety measure.

6. ACCOUNT TERMINATION
Mehd AI reserves the right to terminate or suspend accounts that violate these terms, attempt to manipulate the consensus system, or use the API in ways that could harm other users.

7. DATA PRIVACY
See our Privacy Policy for details on how your data is collected, stored, and used.

8. GOVERNING LAW
These terms are governed by the laws of the jurisdiction in which the user operates. Users are responsible for ensuring compliance with local financial regulations.

9. CALCULATIONS & ALGORITHMIC ESTIMATIONS DISCLAIMER
All position sizing, pip value, margin, drawdown, technical indicator (RSI, ATR, SMA), and backtesting calculations provided by Mehd AI are algorithmic estimations for decision-support and educational purposes. Market conditions such as broker slippage, floating spreads, liquidity gaps, swap rates, and exchange rate fluctuations may cause actual broker execution values to differ from calculated estimations. Mehd AI is not responsible for execution discrepancies, broker-side slippage, or calculation variances resulting from dynamic market feeds.
''',
          style: MehdAiTheme.terminalStyle.copyWith(
            fontSize: 12,
            height: 1.6,
            color: MehdAiTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}
