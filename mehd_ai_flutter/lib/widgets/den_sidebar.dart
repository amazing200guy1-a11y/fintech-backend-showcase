import 'package:flutter/material.dart';
import 'dart:ui';

class DenSidebar extends StatelessWidget {
  final int selectedIndex;
  final Function(int) onSelect;
  final VoidCallback? onLogoTap;

  const DenSidebar({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
    this.onLogoTap,
  });

  @override
  Widget build(BuildContext context) {
    final items = [
      _SideItem(
        icon: Icons.shield,
        label: 'War Room',
        color: const Color(0xFFFF3B3B)),
      _SideItem(
        icon: Icons.terminal,
        label: 'Terminal',
        color: const Color(0xFF58A6FF)),
      _SideItem(
        icon: Icons.candlestick_chart,
        label: 'Markets',
        color: const Color(0xFF00FF88)),
      _SideItem(
        icon: Icons.show_chart,
        label: 'Positions',
        color: const Color(0xFFD29922)),
      _SideItem(
        icon: Icons.account_tree,
        label: 'The Den',
        color: const Color(0xFF00D1FF)),
      _SideItem(
        icon: Icons.rocket_launch,
        label: 'Autopilot',
        color: const Color(0xFFFF9D00)),
      _SideItem(
        icon: Icons.psychology,
        label: 'Neuro Pulse',
        color: const Color(0xFF00FF88)),
      _SideItem(
        icon: Icons.visibility,
        label: 'Sandbox',
        color: const Color(0xFFBC8CFF)),
      _SideItem(
        icon: Icons.history,
        label: 'History',
        color: const Color(0xFF4ECDC4)),
      _SideItem(
        icon: Icons.groups,
        label: 'Network',
        color: const Color(0xFF00FF88)),
      _SideItem(
        icon: Icons.scoreboard,
        label: 'Scoreboard',
        color: const Color(0xFFFFD700)),
      _SideItem(
        icon: Icons.hub,
        label: 'Data Moat',
        color: const Color(0xFF00E5FF)),
      _SideItem(
        icon: Icons.shield,
        label: 'Brokers',
        color: const Color(0xFF00FF88)),
      _SideItem(
        icon: Icons.settings,
        label: 'Settings',
        color: const Color(0xFF888888)),
      _SideItem(
        icon: Icons.rocket_launch,
        label: 'Journey',
        color: const Color(0xFF9E00FF)),
    ];

    return Container(
      width: 76,
      decoration: const BoxDecoration(
        color: Colors.black, // Pure black background
        border: Border(
          right: BorderSide(color: Color(0xFF151515), width: 1), // Extremely subtle dark grey separator
        ),
      ),
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          // TIGER LOGO MASTER BUTTON — BRIGHT & PREMIUM
          GestureDetector(
            onTap: onLogoTap,
            child: Container(
              margin: const EdgeInsets.only(bottom: 24),
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF1E3A5F), Color(0xFF0D1B2A)],
                ),
                border: Border.all(color: const Color(0xFF58A6FF).withOpacity(0.6), width: 1.5),
                boxShadow: [
                  BoxShadow(color: const Color(0xFF58A6FF).withOpacity(0.3), blurRadius: 18, spreadRadius: 2),
                  BoxShadow(color: const Color(0xFF58A6FF).withOpacity(0.1), blurRadius: 35, spreadRadius: 5),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Image.asset('assets/images/mehd_logo.png',
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const Center(child: Text('🐯', style: TextStyle(fontSize: 22)))),
            ),
          ),
          
          Expanded(
            child: ListView.builder(
              itemCount: items.length,
              itemBuilder: (context, index) => _buildItem(items[index], index, context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItem(_SideItem item, int index, BuildContext ctx) {
    final isSelected = selectedIndex == index;

    return Tooltip(
      message: item.label,
      preferBelow: false,
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A),
        border: Border.all(color: item.color.withOpacity(0.5)),
        borderRadius: BorderRadius.circular(6)),
      textStyle: TextStyle(
        color: item.color,
        fontSize: 11,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.5),
      child: GestureDetector(
        onTap: () => onSelect(index),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          width: 58,
          height: 58,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  gradient: isSelected 
                      ? LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            item.color.withOpacity(0.2), 
                            Colors.white.withOpacity(0.05),
                          ],
                        )
                      : null,
                  color: isSelected ? null : Colors.transparent,
                  // IMPORTANT: Uniform border prevents the Flutter assertion crash!
                  border: isSelected 
                      ? Border.all(color: item.color.withOpacity(0.4), width: 1)
                      : Border.all(color: Colors.transparent),
                ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(item.icon,
                  size: 20,
                  color: isSelected ? item.color : item.color.withOpacity(0.6),
                  shadows: [
                    Shadow(
                      color: item.color.withOpacity(isSelected ? 0.8 : 0.2),
                      blurRadius: isSelected ? 14 : 4,
                    ),
                  ]),
                const SizedBox(height: 4),
                Text(item.label,
                  style: TextStyle(
                    color: isSelected ? item.color : item.color.withOpacity(0.7),
                    fontSize: isSelected ? 8.5 : 8,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    letterSpacing: 0.3),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  textAlign: TextAlign.center),
              ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SideItem {
  final IconData icon;
  final String label;
  final Color color;
  _SideItem({
    required this.icon,
    required this.label,
    required this.color,
  });
}
