import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/services/biometric_security_service.dart';


class PinLockScreen extends StatefulWidget {
  final VoidCallback? onUnlocked;

  const PinLockScreen({super.key, this.onUnlocked});

  @override
  State<PinLockScreen> createState() => _PinLockScreenState();
}

class _PinLockScreenState extends State<PinLockScreen> {
  String _enteredPin = '';
  String? _errorMessage;
  bool _isVerifying = false;

  void _onKeyPress(String digit) {
    if (_enteredPin.length < 4 && !_isVerifying) {
      setState(() {
        _enteredPin += digit;
        _errorMessage = null;
      });

      if (_enteredPin.length == 4) {
        _verifyPin();
      }
    }
  }

  void _onDelete() {
    if (_enteredPin.isNotEmpty && !_isVerifying) {
      setState(() {
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
        _errorMessage = null;
      });
    }
  }

  Future<void> _verifyPin() async {
    setState(() => _isVerifying = true);
    final service = context.read<BiometricSecurityService>();
    final success = await service.verifyPin(_enteredPin);

    if (!mounted) return;

    if (success) {
      widget.onUnlocked?.call();
    } else {
      setState(() {
        _enteredPin = '';
        _errorMessage = 'Incorrect PIN. Please try again.';
        _isVerifying = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MehdAiTheme.bgPrimary,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // App Security Logo Shield
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: MehdAiTheme.gold.withOpacity(0.1),
                      border: Border.all(color: MehdAiTheme.gold.withOpacity(0.4), width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: MehdAiTheme.gold.withOpacity(0.15),
                          blurRadius: 20,
                          spreadRadius: 2,
                        )
                      ],
                    ),
                    child: const Icon(
                      Icons.shield_outlined,
                      color: MehdAiTheme.gold,
                      size: 36,
                    ),
                  ),
                  const SizedBox(height: 24),

                  Text(
                    'MEHD AI SECURITY LOCK',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const SizedBox(height: 8),

                  Text(
                    'Enter your 4-digit PIN to access trading controls',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(
                      color: MehdAiTheme.textSecondary,
                      fontSize: 13,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // 4-Digit Indicator Dots
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(4, (index) {
                      final isFilled = index < _enteredPin.length;
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        margin: const EdgeInsets.symmetric(horizontal: 10),
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: isFilled ? MehdAiTheme.gold : Colors.transparent,
                          border: Border.all(
                            color: isFilled ? MehdAiTheme.gold : MehdAiTheme.textSecondary.withOpacity(0.4),
                            width: 2,
                          ),
                          boxShadow: isFilled
                              ? [
                                  BoxShadow(
                                    color: MehdAiTheme.gold.withOpacity(0.4),
                                    blurRadius: 8,
                                  )
                                ]
                              : [],
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 16),

                  if (_errorMessage != null)
                    Text(
                      _errorMessage!,
                      style: GoogleFonts.inter(
                        color: MehdAiTheme.red,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    )
                  else
                    const SizedBox(height: 18),

                  const SizedBox(height: 24),

                  // Keypad Grid
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 1.4,
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                    ),
                    itemCount: 12,
                    itemBuilder: (context, index) {
                      if (index == 9) {
                        return const SizedBox.shrink(); // Empty bottom-left
                      }
                      if (index == 10) {
                        return _buildKey('0');
                      }
                      if (index == 11) {
                        return InkWell(
                          onTap: _onDelete,
                          borderRadius: BorderRadius.circular(16),
                          child: Container(
                            alignment: Alignment.center,
                            child: const Icon(
                              Icons.backspace_outlined,
                              color: Colors.white70,
                              size: 22,
                            ),
                          ),
                        );
                      }
                      return _buildKey('${index + 1}');
                    },
                  ),
                  const SizedBox(height: 16),
                  TextButton(
                    onPressed: _showForgotPinDialog,
                    child: Text(
                      'Forgot PIN?',
                      style: GoogleFonts.inter(
                        color: MehdAiTheme.gold,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showForgotPinDialog() {
    final user = FirebaseAuth.instance.currentUser;
    final email = user?.email ?? 'your registered email';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF0F172A),
        title: Text('Reset PIN Security', style: GoogleFonts.outfit(color: Colors.white)),
        content: Text(
          'To reset your PIN, an authentication verification request will be processed for $email.',
          style: GoogleFonts.inter(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: MehdAiTheme.gold),
            onPressed: () async {
              Navigator.pop(ctx);
              // Capture context-dependent refs before async gap
              final service = context.read<BiometricSecurityService>();
              final messenger = ScaffoldMessenger.of(context);
              if (user?.email != null) {
                try {
                  await FirebaseAuth.instance.sendPasswordResetEmail(email: user!.email!);
                } catch (_) {}
              }
              await service.disablePin();
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('PIN disabled. You can set a new PIN in Security Settings.'),
                  backgroundColor: Color(0xFF00E676),
                ),
              );
            },
            child: const Text('Reset PIN', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildKey(String label) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Material(
          color: Colors.white.withOpacity(0.04),
          child: InkWell(
            onTap: () => _onKeyPress(label),
            splashColor: MehdAiTheme.gold.withOpacity(0.2),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withOpacity(0.08)),
              ),
              child: Text(
                label,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
