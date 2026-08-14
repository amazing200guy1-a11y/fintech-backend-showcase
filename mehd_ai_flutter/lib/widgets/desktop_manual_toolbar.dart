import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mehd_ai_flutter/core/theme.dart';

class DesktopManualToolbar extends StatelessWidget {
  final String activeTool;
  final String chartMode;
  final Function(String) onToolSelected;
  final Function(String) onModeSelected;

  const DesktopManualToolbar({
    super.key,
    required this.activeTool,
    required this.chartMode,
    required this.onToolSelected,
    required this.onModeSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: const Color(0xFF090D16),
      child: Row(
        children: [
          _buildToolBtn('Support', 'support'),
          const SizedBox(width: 8),
          _buildToolBtn('Resistance', 'resistance'),
          const SizedBox(width: 8),
          _buildToolBtn('Trendline', 'trendline'),
          const Spacer(),
          _buildToggleBtn('CANDLES'),
          const SizedBox(width: 4),
          _buildToggleBtn('LINE'),
        ],
      ),
    );
  }

  Widget _buildToolBtn(String label, String tool) {
    final isSelected = activeTool == tool;
    return GestureDetector(
      onTap: () => onToolSelected(tool),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? MehdAiTheme.blue.withOpacity(0.2) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: isSelected ? MehdAiTheme.blue : Colors.white24),
        ),
        child: Text(label, style: GoogleFonts.inter(color: isSelected ? Colors.white : Colors.white60, fontSize: 11)),
      ),
    );
  }

  Widget _buildToggleBtn(String mode) {
    final isSelected = chartMode.toUpperCase() == mode;
    return GestureDetector(
      onTap: () => onModeSelected(mode.toLowerCase()),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white12 : Colors.transparent,
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(mode, style: TextStyle(color: isSelected ? Colors.white : Colors.white38, fontSize: 10, fontWeight: FontWeight.bold)),
      ),
    );
  }
}
