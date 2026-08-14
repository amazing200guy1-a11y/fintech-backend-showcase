import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class ScoreboardAccountability extends StatelessWidget {
  final Map<String, dynamic> data;

  const ScoreboardAccountability({super.key, required this.data});

  @override
  Widget build(BuildContext context) {
    final layers = (data['layers'] as Map<String, dynamic>?) ?? {};
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("AGENT ACCOUNTABILITY MATRIX", style: GoogleFonts.orbitron(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold, letterSpacing: 1.5)),
        const SizedBox(height: 12),
        ...layers.entries.map((e) => _buildAgentRow(e.key, e.value)),
      ],
    );
  }

  Widget _buildAgentRow(String name, dynamic data, [Color accent = const Color(0xFF00FF88)]) {
    final winRate = data is Map ? (data['winRate'] ?? '85.0%') : '85.0%';
    final trades = data is Map ? (data['trades'] ?? 42) : 42;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF161B22),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white10),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.security, color: accent, size: 16),
              const SizedBox(width: 8),
              Text(name.toUpperCase(), style: GoogleFonts.outfit(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
            ],
          ),
          Row(
            children: [
              Text('$trades trades', style: const TextStyle(color: Colors.white54, fontSize: 11)),
              const SizedBox(width: 12),
              Text('$winRate WR', style: GoogleFonts.jetBrainsMono(color: accent, fontSize: 12, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    );
  }
}
