import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Hero welcome view for Neuro Pulse Command Centre when chat feed is empty.
class PulseHeroWelcomeView extends StatelessWidget {
  const PulseHeroWelcomeView({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 60),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Official Centered Glowing Logo Avatar
            Container(
              width: 100,
              height: 100,
              decoration: BoxDecoration(
                color: const Color(0xFF0D1117),
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF58A6FF).withOpacity(0.7), width: 2.5),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF58A6FF).withOpacity(0.35), blurRadius: 36, spreadRadius: 4),
                  BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 20, offset: const Offset(0, 10)),
                ],
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/images/mehd_logo.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) {
                    return const Icon(Icons.bolt_rounded, color: Color(0xFF58A6FF), size: 48);
                  },
                ),
              ),
            ),
            const SizedBox(height: 28),
            
            Text(
              "NEURO PULSE COMMAND CENTRE",
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
                letterSpacing: 2.0,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Text(
                "Type a / command below or tap a quick action to control your portfolio with institutional precision.",
                style: GoogleFonts.inter(color: const Color(0xFF888888), fontSize: 13, height: 1.4),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
