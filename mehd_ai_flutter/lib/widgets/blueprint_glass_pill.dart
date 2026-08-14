import 'package:flutter/material.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/widgets/blueprint_helpers.dart';

class BlueprintGlassPill extends StatefulWidget {
  final BlueprintNode node;
  final int uniqueIndex;
  final double pillWidth;
  final VoidCallback onTap;

  const BlueprintGlassPill({
    super.key,
    required this.node,
    required this.uniqueIndex,
    this.pillWidth = 160,
    required this.onTap,
  });

  @override
  State<BlueprintGlassPill> createState() => _BlueprintGlassPillState();
}

class _BlueprintGlassPillState extends State<BlueprintGlassPill> {
  bool isHovered = false;

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    return MouseRegion(
      onEnter: (_) => setState(() => isHovered = true),
      onExit: (_) => setState(() => isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: isHovered ? 1.05 : 1.0,
          duration: const Duration(milliseconds: 150),
          child: Container(
            width: widget.pillWidth,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF232532).withOpacity(0.85),
                      const Color(0xFF13151B).withOpacity(0.95),
                    ]),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: isHovered
                        ? node.color.withOpacity(0.5)
                        : Colors.white.withOpacity(0.08),
                    width: 1.5),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.4),
                      blurRadius: 10,
                      offset: const Offset(0, 5)),
                  if (isHovered)
                    BoxShadow(
                        color: node.color.withOpacity(0.15),
                        blurRadius: 20,
                        spreadRadius: -2),
                ]),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.white.withOpacity(0.15),
                            Colors.white.withOpacity(0.02),
                          ]),
                      border: Border.all(color: Colors.white.withOpacity(0.1)),
                      boxShadow: [
                        BoxShadow(
                            color: node.color.withOpacity(0.2),
                            blurRadius: 10,
                            spreadRadius: 1)
                      ]),
                  child: Center(
                    child: Icon(node.icon,
                        color: node.color.withOpacity(0.9), size: 22),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  node.title,
                  style: MehdAiTheme.headingStyle.copyWith(
                      color: Colors.white,
                      fontSize: 12,
                      letterSpacing: 0.5,
                      fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
                Text(
                  node.subtitle,
                  style: MehdAiTheme.bodyStyle.copyWith(
                      color: Colors.white.withOpacity(0.6), fontSize: 9),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
