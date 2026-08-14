import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/widgets/techno_card.dart';
import 'package:mehd_ai_flutter/screens/terms_screen.dart';
import 'package:mehd_ai_flutter/screens/privacy_screen.dart';

class AboutScreen extends StatelessWidget {
  final bool showBack;
  const AboutScreen({super.key, this.showBack = true});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MehdAiTheme.bgPrimary,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: showBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 18),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: Text('HOW TO USE MEHD AI', style: GoogleFonts.outfit(fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        backgroundColor: MehdAiTheme.bgSecondary,
        elevation: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(color: MehdAiTheme.borderColor, height: 1),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 800),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header Logo Banner
                Row(
                  children: [
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: const Color(0xFF0D1117),
                        shape: BoxShape.circle,
                        border: Border.all(color: const Color(0xFF58A6FF).withOpacity(0.5), width: 1.5),
                      ),
                      child: ClipOval(
                        child: Image.asset('assets/images/mehd_logo.png', fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('MEHD AI OPERATING SYSTEM', style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
                        const SizedBox(height: 4),
                        Text('Instant Cockpit & Execution Field Guide', style: GoogleFonts.inter(color: const Color(0xFF888888), fontSize: 12)),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 28),

                // Guide Card 1: Reading Consensus & Signals
                _buildGuideSection(
                  title: '1. READING AI CONSENSUS SIGNALS',
                  icon: Icons.psychology_rounded,
                  color: const Color(0xFF58A6FF),
                  content: [
                    '• Conviction Score: Evaluates agreement across all 11 AI models.',
                    '• ≥92% Conviction: High-confidence institutional setup with Alpha Predator 1.5x lot boost capability.',
                    '• Freshness: Signals are FRESH for 0-5 mins. Do not trade expired or stale signals.',
                  ],
                ),
                const SizedBox(height: 16),

                // Guide Card 2: 1-Tap Cockpit Slash Commands
                _buildGuideSection(
                  title: '2. 1-TAP COCKPIT SLASH COMMANDS',
                  icon: Icons.bolt_rounded,
                  color: const Color(0xFF00FF88),
                  content: [
                    '• /nuke — Emergency Panic Switch: Liquidates all open positions instantly in <15ms.',
                    '• /bank50 — Lock 50% Profit: Banks half your position into cash with institutional micro-lot rounding.',
                    '• /be — Move SL to Breakeven: Shifts stop loss to entry price for zero risk.',
                    '• /risk [percent] — Auto Risk Sizer: Calculates exact safe lot size with 50% margin safety cap.',
                    '• /trail [pips] — Smart Trailing SL: Moves stop loss behind price structure automatically 24/7.',
                    '• /shield — 24h Loss Guard: Arms an unbypassable 24-hour lock to freeze trading and stop revenge trading.',
                  ],
                ),
                const SizedBox(height: 16),

                // Guide Card 3: Invisible Virtual Vault & Risk Protection
                _buildGuideSection(
                  title: '3. INVISIBLE VIRTUAL VAULT & PROTECTION',
                  icon: Icons.shield_rounded,
                  color: const Color(0xFFE8C44A),
                  content: [
                    '• Hidden Stop-Loss: Your Stop-Loss is stored in our Server Vault — NOT on the broker MT4/MT5 server. Brokers cannot see or hunt your SL.',
                    '• Pre-News Blackout: Sentinel automatically pauses trades 30-60m before Tier-1 news (NFP, CPI, FOMC).',
                    '• Micro-Lot Rounding: Positions round cleanly to 0.01 micro-lots so broker APIs never reject orders.',
                  ],
                ),
                const SizedBox(height: 32),

                // Footer Links
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    InkWell(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const TermsScreen())),
                      child: Text('[Terms of Service]', style: GoogleFonts.jetBrainsMono(color: const Color(0xFF888888), fontSize: 12)),
                    ),
                    const SizedBox(width: 24),
                    InkWell(
                      onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const PrivacyScreen())),
                      child: Text('[Privacy Policy]', style: GoogleFonts.jetBrainsMono(color: const Color(0xFF888888), fontSize: 12)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Center(
                  child: Text('© 2026 MEHD AI. All rights reserved.', style: GoogleFonts.inter(color: const Color(0xFF555555), fontSize: 11)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGuideSection({
    required String title,
    required IconData icon,
    required Color color,
    required List<String> content,
  }) {
    return TechnoCard(
      borderColor: color.withOpacity(0.4),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 10),
              Text(title, style: GoogleFonts.outfit(color: color, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            ],
          ),
          const SizedBox(height: 12),
          ...content.map((item) => Padding(
            padding: const EdgeInsets.only(bottom: 6.0),
            child: Text(item, style: GoogleFonts.inter(color: const Color(0xFFD4D4D8), fontSize: 13, height: 1.4)),
          )),
        ],
      ),
    );
  }
}
