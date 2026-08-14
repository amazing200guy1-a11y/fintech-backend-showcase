import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:google_fonts/google_fonts.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _bootCtrl;
  late Animation<double> _bracketScale;
  late Animation<double> _logoOpacity;

  String _terminalOutput = '';
  final List<String> _bootSequence = [
    '> [SYS_INIT] KERNEL LOADED...',
    '> CONNECTING TO THE DEN...',
    '> UPLINK SECURED. ALPHA CERTIFIED.'
  ];
  
  @override
  void initState() {
    super.initState();

    _bootCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    _bracketScale = Tween<double>(begin: 1.5, end: 1.0).animate(
      CurvedAnimation(parent: _bootCtrl, curve: Curves.easeOutExpo),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _bootCtrl, curve: const Interval(0.2, 1.0, curve: Curves.easeIn)),
    );

    // Start sequence after first frame to avoid setState in initState crash
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _runBootSequence();
    });
  }

  Future<void> _runBootSequence() async {
    // Phase 1: Snap HUD and Logo in immediately
    _bootCtrl.forward();
    
    // Phase 2: Fast terminal typewriter (snappy boot)
    for (String line in _bootSequence) {
      if (!mounted) return;
      setState(() => _terminalOutput += '$line\n');
      await Future.delayed(const Duration(milliseconds: 350)); 
    }

    // Phase 3: Immediate check and route
    if (!mounted) return;
    _navigate();
  }

  Future<void> _navigate() async {
    bool done = false;
    User? user;
    try {
      try {
        final p = await SharedPreferences.getInstance();
        done = p.getBool('onboarding_complete') ?? false;
      } catch (e) {
        debugPrint("Splash: SharedPreferences error: $e");
      }
      
      try {
        if (Firebase.apps.isNotEmpty) {
          user = FirebaseAuth.instance.currentUser;
        }
      } catch (e) {
        debugPrint("Splash: Auth error: $e");
      }

      if (!mounted) return;

      if (user != null) {
        Navigator.pushReplacementNamed(context, '/home');
      } else if (!done) {
        Navigator.pushReplacementNamed(context, '/welcome');
      } else {
        Navigator.pushReplacementNamed(context, '/login');
      }
    } catch (e) {
      debugPrint("Splash: Navigation fallback triggered: $e");
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/welcome');
      }
    }
  }

  @override
  void dispose() {
    _bootCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF02040A), // Extremely dark blue/black
      body: CustomPaint(
        painter: _GridPainter(),
        child: AnimatedBuilder(
          animation: _bootCtrl,
          builder: (context, child) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // HUD Brackets + Logo
                  SizedBox(
                    width: 200,
                    height: 200,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // HUD Brackets
                        Transform.scale(
                          scale: _bracketScale.value,
                          child: CustomPaint(
                            size: const Size(180, 180),
                            painter: _HudBracketPainter(opacity: _logoOpacity.value),
                          ),
                        ),
                        // Tiger Logo
                        Opacity(
                          opacity: _logoOpacity.value,
                          child: Container(
                            width: 110,
                            height: 110,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: const Color(0xFF00E5FF).withOpacity(0.2),
                                  blurRadius: 40,
                                  spreadRadius: 5,
                                )
                              ],
                            ),
                            child: ClipOval(
                              child: Image.asset(
                                'assets/images/mehd_logo.png',
                                fit: BoxFit.cover,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 32),
                  
                  // MEHD AI TITLE
                  Opacity(
                    opacity: _logoOpacity.value,
                    child: Text(
                      'MEHD AI',
                      style: GoogleFonts.orbitron(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 8,
                        shadows: [
                          Shadow(
                            color: const Color(0xFF00E5FF).withOpacity(0.5),
                            blurRadius: 10,
                          )
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 48),

                  // FAST TERMINAL BOOT SEQUENCE
                  Container(
                    width: 300,
                    height: 80,
                    alignment: Alignment.topLeft,
                    child: Text(
                      _terminalOutput,
                      style: GoogleFonts.jetBrainsMono(
                        color: const Color(0xFF00E5FF).withOpacity(0.8),
                        fontSize: 10,
                        height: 1.6,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── CUSTOM PAINTERS ──

class _GridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF58A6FF).withOpacity(0.03) // Very subtle
      ..strokeWidth = 1.0;

    const double gridSize = 40.0;
    
    // Draw vertical lines
    for (double i = 0; i <= size.width; i += gridSize) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    // Draw horizontal lines
    for (double i = 0; i <= size.height; i += gridSize) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }

    // Radial gradient to fade grid out at edges (looks better on mobile)
    final Rect rect = Offset.zero & size;
    final Gradient gradient = RadialGradient(
      center: Alignment.center,
      radius: 0.8,
      colors: [
        Colors.transparent,
        const Color(0xFF02040A).withOpacity(0.8),
        const Color(0xFF02040A),
      ],
      stops: const [0.4, 0.8, 1.0],
    );
    canvas.drawRect(rect, Paint()..shader = gradient.createShader(rect));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _HudBracketPainter extends CustomPainter {
  final double opacity;
  _HudBracketPainter({required this.opacity});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00E5FF).withOpacity(opacity * 0.8)
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final double w = size.width;
    final double h = size.height;
    const double length = 30.0; // Length of the bracket corner lines

    // Top Left
    canvas.drawLine(const Offset(0, length), const Offset(0, 0), paint);
    canvas.drawLine(const Offset(0, 0), const Offset(length, 0), paint);

    // Top Right
    canvas.drawLine(Offset(w - length, 0), Offset(w, 0), paint);
    canvas.drawLine(Offset(w, 0), Offset(w, length), paint);

    // Bottom Left
    canvas.drawLine(Offset(0, h - length), Offset(0, h), paint);
    canvas.drawLine(Offset(0, h), Offset(length, h), paint);

    // Bottom Right
    canvas.drawLine(Offset(w - length, h), Offset(w, h), paint);
    canvas.drawLine(Offset(w, h), Offset(w, h - length), paint);
    
    // Tiny crosshairs
    final crossPaint = Paint()
      ..color = const Color(0xFF00E5FF).withOpacity(opacity * 0.3)
      ..strokeWidth = 1.0;
      
    canvas.drawLine(Offset(w/2, -10), Offset(w/2, 10), crossPaint);
    canvas.drawLine(Offset(w/2, h - 10), Offset(w/2, h + 10), crossPaint);
    canvas.drawLine(Offset(-10, h/2), Offset(10, h/2), crossPaint);
    canvas.drawLine(Offset(w - 10, h/2), Offset(w + 10, h/2), crossPaint);
  }

  @override
  bool shouldRepaint(covariant _HudBracketPainter oldDelegate) => 
      opacity != oldDelegate.opacity;
}
