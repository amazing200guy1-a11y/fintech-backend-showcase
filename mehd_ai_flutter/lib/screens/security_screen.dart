import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/services/biometric_security_service.dart';

class SecurityScreen extends StatelessWidget {
  final bool showBack;
  const SecurityScreen({super.key, this.showBack = false});

  void _showCodenameDialog(BuildContext context, BiometricSecurityService security) {
    final ctrl = TextEditingController(text: security.codename);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0D1117),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: MehdAiTheme.gold.withOpacity(0.3)),
        ),
        title: Text(
          'SET WAR ROOM CODENAME',
          style: GoogleFonts.outfit(
            color: MehdAiTheme.gold,
            fontSize: 13,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.5,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Your personal War Room identity. Only visible to you. Example: "Golden Falcon 2026"',
              style: GoogleFonts.outfit(color: Colors.white54, fontSize: 11, height: 1.5),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              autofocus: true,
              style: GoogleFonts.jetBrainsMono(color: Colors.white, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'Golden Falcon 2026',
                hintStyle: GoogleFonts.jetBrainsMono(color: Colors.white24, fontSize: 13),
                filled: true,
                fillColor: const Color(0xFF161B22),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: MehdAiTheme.gold.withOpacity(0.3)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: MehdAiTheme.gold.withOpacity(0.2)),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: MehdAiTheme.gold),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('CANCEL', style: GoogleFonts.outfit(color: Colors.white38, fontSize: 11)),
          ),
          if (security.codename.isNotEmpty)
            TextButton(
              onPressed: () {
                security.clearCodename();
                Navigator.pop(ctx);
              },
              child: Text('CLEAR', style: GoogleFonts.outfit(color: MehdAiTheme.red, fontSize: 11)),
            ),
          ElevatedButton(
            onPressed: () {
              if (ctrl.text.trim().isNotEmpty) {
                security.setCodename(ctrl.text);
              }
              Navigator.pop(ctx);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: MehdAiTheme.gold,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: Text('CONFIRM', style: GoogleFonts.outfit(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final security = context.watch<BiometricSecurityService>();
    final hasCodename = security.codename.isNotEmpty;

    return Scaffold(
      backgroundColor: MehdAiTheme.bgPrimary,
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: showBack
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
                onPressed: () => Navigator.pop(context),
              )
            : null,
        title: const Text('SECURITY PROMISE', style: TextStyle(letterSpacing: 2, fontSize: 16, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 20),

              // Glowing shield header
              Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF00FF88).withOpacity(0.05),
                  border: Border.all(color: const Color(0xFF00FF88).withOpacity(0.3), width: 1.5),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF00FF88).withOpacity(0.1),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Center(
                  child: Icon(Icons.security, color: Color(0xFF00FF88), size: 42),
                ),
              ),
              const SizedBox(height: 24),

              const Text(
                'THE SHIELD OF MEHD AI',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.5,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Built as a weapon against predatory broker cartels. Hardened to withstand any attempt to silence your edge.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Color(0xFF88A8D8), fontSize: 12, height: 1.5),
              ),

              const SizedBox(height: 32),

              // ── WAR ROOM CODENAME CARD ────────────────────────────────────────
              GestureDetector(
                onTap: () => _showCodenameDialog(context, security),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 22),
                  decoration: BoxDecoration(
                    color: MehdAiTheme.gold.withOpacity(0.07),
                    border: Border.all(
                      color: hasCodename
                          ? MehdAiTheme.gold.withOpacity(0.85)
                          : Colors.white.withOpacity(0.15),
                      width: 1.2,
                    ),
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: hasCodename
                        ? [
                            BoxShadow(
                              color: MehdAiTheme.gold.withOpacity(0.18),
                              blurRadius: 24,
                              spreadRadius: 2,
                            ),
                          ]
                        : [],
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: MehdAiTheme.gold.withOpacity(0.12),
                          border: Border.all(
                            color: hasCodename
                                ? MehdAiTheme.gold.withOpacity(0.7)
                                : Colors.white24,
                            width: 1.2,
                          ),
                        ),
                        child: Icon(
                          Icons.person_pin_rounded,
                          color: hasCodename ? MehdAiTheme.gold : Colors.white38,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'WAR ROOM CODENAME',
                              style: GoogleFonts.outfit(
                                color: MehdAiTheme.gold,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 2.0,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              hasCodename ? security.codename : 'TAP TO SET YOUR IDENTITY',
                              style: GoogleFonts.jetBrainsMono(
                                color: hasCodename ? Colors.white : Colors.white38,
                                fontSize: hasCodename ? 18 : 12,
                                fontWeight: hasCodename ? FontWeight.bold : FontWeight.w500,
                                letterSpacing: hasCodename ? 2.5 : 1.5,
                              ),
                            ),
                            if (!hasCodename) ...[
                              const SizedBox(height: 4),
                              Text(
                                'e.g. "Golden Falcon 2026" — stored encrypted on-device only',
                                style: GoogleFonts.outfit(color: Colors.white24, fontSize: 10, height: 1.4),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Icon(
                        Icons.edit_outlined,
                        color: hasCodename ? MehdAiTheme.gold.withOpacity(0.5) : Colors.white12,
                        size: 16,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 24),

              // Security guarantees
              _buildGuaranteeCard(
                icon: Icons.lock_outline,
                title: 'AES-256 KEY ENCRYPTION',
                description: 'Broker credentials are encrypted at-rest using hardware security keys (iOS Keychain / Android Keystore) and server-side master keys. Plain text keys are never stored.',
              ),
              const SizedBox(height: 16),
              _buildGuaranteeCard(
                icon: Icons.shield_outlined,
                title: 'ZERO-WITHDRAWAL POLICY',
                description: 'Mehd AI operates strictly in "Trade Only" mode. We never request, support, or require withdrawal or transfer capabilities. Your funds are physically untouchable by us.',
              ),
              const SizedBox(height: 16),
              _buildGuaranteeCard(
                icon: Icons.security_update_good_outlined,
                title: 'SSL CERTIFICATE PINNING',
                description: "Connections are pinned directly to our server's cryptographic certificate. Any attempt to intercept traffic, hijack DNS, or execute middleman attacks is instantly blocked.",
              ),
              const SizedBox(height: 16),
              _buildGuaranteeCard(
                icon: Icons.gavel_outlined,
                title: 'FORENSIC AUDIT TRAILS',
                description: 'Every backend credential access and trade authorization is permanently logged. Insider threats or server tampering attempts are instantly traceable.',
              ),
              const SizedBox(height: 16),
              _buildGuaranteeCard(
                icon: Icons.speed_outlined,
                title: 'BOT SHIELD RATE LIMITS',
                description: 'Automated request sweeps and billing-abuse attacks are blocked at the gateway level. Your subscription API quotas are fully isolated and secure.',
              ),

              const SizedBox(height: 40),

              // Closing manifesto
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0D14),
                  border: Border.all(color: Colors.white.withOpacity(0.05)),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text(
                  '"Mehd AI is not just software. It is a tool for retail traders to reclaim control. Our security design ensures this power remains entirely yours and can never be weaponized against you by brokers or market manipulators."',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF6688AA),
                    fontSize: 11,
                    fontStyle: FontStyle.italic,
                    height: 1.6,
                  ),
                ),
              ),

              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGuaranteeCard({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF020810).withOpacity(0.4),
        border: Border.all(color: Colors.white.withOpacity(0.05)),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: const Color(0xFF00FF88), size: 24),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF00FF88),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  description,
                  style: const TextStyle(
                    color: Color(0xFF999999),
                    fontSize: 11,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
