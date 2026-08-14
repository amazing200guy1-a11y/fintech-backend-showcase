import 'dart:ui';
import 'package:flutter/material.dart';

/// Reusable settings section title and glassmorphism card builder.
/// Extracted from SettingsScreen for modularity.

Widget buildSettingsSectionTitle(String title, {Color color = const Color(0xFF444444)}) {
  return Padding(
    padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
    child: Text(
      title,
      style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5),
    ),
  );
}

Widget build3DSettingsCard(
  BuildContext context, String title, String subtitle,
  IconData icon, List<Color> gradient, Color accent, VoidCallback onTap,
) {
  return GestureDetector(
    onTap: onTap,
    child: ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
        child: Container(
          height: 90,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradient,
            ),
            border: Border.all(color: Colors.white.withOpacity(0.05), width: 0.5),
            boxShadow: [
              BoxShadow(color: gradient[0].withOpacity(0.2), blurRadius: 12, offset: const Offset(0, 4)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(13),
                  gradient: LinearGradient(
                    colors: [Colors.white.withOpacity(0.12), Colors.white.withOpacity(0.03)],
                  ),
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 6, offset: const Offset(0, 3)),
                  ],
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(title, style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 12, fontWeight: FontWeight.w600, height: 1.2)),
                  const SizedBox(height: 3),
                  Text(subtitle, style: TextStyle(color: Colors.white.withOpacity(0.35), fontSize: 10)),
                ],
              )),
              Icon(Icons.arrow_forward_ios_rounded, color: Colors.white.withOpacity(0.15), size: 14),
            ],
          ),
        ),
      ),
    ),
  );
}
