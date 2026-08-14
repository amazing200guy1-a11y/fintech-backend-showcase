import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mehd_ai_flutter/core/theme.dart';

class SecurityStatusCard extends StatelessWidget {
  final String vaultStatus;
  final String auditStatus;
  final String appCheckStatus;
  final VoidCallback? onLockdownTap;

  const SecurityStatusCard({
    super.key,
    this.vaultStatus = 'GCP_SECRET_MANAGER_ARMED',
    this.auditStatus = 'HASH_CHAINED_IMMUTABLE',
    this.appCheckStatus = 'VERIFIED_ACTIVE',
    this.onLockdownTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF090D16),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: MehdAiTheme.green.withOpacity(0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.shield_rounded, color: MehdAiTheme.green, size: 20),
              const SizedBox(width: 8),
              Text('INSTITUTIONAL SECURITY SHIELD',
                  style: GoogleFonts.orbitron(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
            ],
          ),
          const SizedBox(height: 16),
          _buildSecRow('Secrets Vault', vaultStatus, MehdAiTheme.blue),
          const SizedBox(height: 8),
          _buildSecRow('Audit Ledger', auditStatus, MehdAiTheme.gold),
          const SizedBox(height: 8),
          _buildSecRow('App Check Shield', appCheckStatus, MehdAiTheme.green),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFF3B3B).withOpacity(0.15),
                side: const BorderSide(color: Color(0xFFFF3B3B)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: onLockdownTap,
              icon: const Icon(Icons.lock_reset_rounded, color: Color(0xFFFF3B3B), size: 18),
              label: Text(
                'EMERGENCY LOCKDOWN',
                style: GoogleFonts.orbitron(color: const Color(0xFFFF3B3B), fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecRow(String title, String value, Color accent) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: GoogleFonts.inter(color: Colors.white70, fontSize: 11)),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: accent.withOpacity(0.12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: accent.withOpacity(0.3)),
          ),
          child: Text(value, style: TextStyle(color: accent, fontSize: 9, fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }
}
