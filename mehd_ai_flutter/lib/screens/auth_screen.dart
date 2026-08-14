import 'package:flutter/material.dart';
import 'package:mehd_ai_flutter/core/theme.dart';
import 'package:mehd_ai_flutter/services/auth_service.dart';
import 'package:mehd_ai_flutter/screens/onboarding/broker_connect_screen.dart';
import 'package:provider/provider.dart';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:mehd_ai_flutter/widgets/auth_terms_checkbox.dart';

class AuthScreen extends StatefulWidget {
  final bool initialIsLogin;
  const AuthScreen({super.key, this.initialIsLogin = true});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _emailCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  final TextEditingController _confirmPassCtrl = TextEditingController();
  
  bool _isLoading = false;
  String? _errorMsg;
  bool _obscurePass = true;
  bool _obscureConfirm = true;
  late bool _isLogin;
  bool _termsAccepted = false;
  int _passwordStrength = 0;

  @override
  void initState() {
    super.initState();
    _isLogin = widget.initialIsLogin;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  void _updatePasswordStrength(String password) {
    int strength = 0;
    if (password.length >= 6) strength++;
    if (password.length >= 10) strength++;
    if (RegExp(r'[A-Z]').hasMatch(password) && RegExp(r'[a-z]').hasMatch(password)) strength++;
    if (RegExp(r'[0-9!@#$%^&*(),.?":{}|<>]').hasMatch(password)) strength++;
    setState(() => _passwordStrength = strength);
  }

  void _handleError(String? error) {
    if (error == null) return;
    setState(() => _errorMsg = error);
  }

  void _submit() async {
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });

    if (_isLogin) {
      if (_emailCtrl.text.trim().isEmpty || _passCtrl.text.trim().isEmpty) {
        setState(() {
          _isLoading = false;
          _errorMsg = "Please enter your email and password.";
        });
        return;
      }
    } else {
      if (!_formKey.currentState!.validate()) {
        setState(() => _isLoading = false);
        return;
      }
      if (!_termsAccepted) {
        setState(() {
          _isLoading = false;
          _errorMsg = "You must agree to the terms to continue.";
        });
        return;
      }
    }

    final authService = context.read<AuthService>();
    
    String? error;
    if (_isLogin) {
      error = await authService.signInWithEmail(_emailCtrl.text.trim(), _passCtrl.text.trim());
    } else {
      error = await authService.signUpWithEmail(
        _emailCtrl.text.trim(), 
        _passCtrl.text.trim(), 
        _nameCtrl.text.trim().isEmpty ? 'Trader' : _nameCtrl.text.trim()
      );
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (error != null) {
      _handleError(error);
    } else {
      if (_isLogin) {
        Navigator.of(context).pushReplacementNamed('/home');
      } else {
        // Success Sign Up -> Push Onboarding
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const BrokerConnectScreen()),
          (route) => false,
        );
      }
    }
  }

  void _signInGoogle() async {
    setState(() {
      _isLoading = true;
      _errorMsg = null;
    });
    
    final authService = context.read<AuthService>();
    final error = await authService.signInWithGoogle();

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (error != null) {
      _handleError(error);
    } else {
      Navigator.of(context).pushReplacementNamed('/home');
    }
  }

  void _forgotPassword() async {
    if (_emailCtrl.text.trim().isEmpty) {
      setState(() => _errorMsg = 'Enter your email first, then tap forgot password.');
      return;
    }
    final authService = context.read<AuthService>();
    final error = await authService.resetPassword(_emailCtrl.text.trim());
    if (!mounted) return;

    if (error != null) {
      _handleError(error);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: MehdAiTheme.gold,
          content: Text('Password reset email sent. Check your inbox.', style: TextStyle(color: Colors.black)),
        ),
      );
    }
  }

  void _toggleMode() {
    setState(() {
      _isLogin = !_isLogin;
      _errorMsg = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: MehdAiTheme.bgPrimary,
      body: Stack(children: [
        // Subtle logo background
        Center(child: Opacity(
          opacity: 0.03,
          child: Image.asset('assets/images/mehd_logo.png', width: 400, height: 400))),
        
        SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Form(
              key: _formKey,
              child: Column(children: [
                const SizedBox(height: 48),
                
                // Logo
                Image.asset('assets/images/mehd_logo.png', width: 64, height: 64),
                const SizedBox(height: 20),
                
                // Title
                Text(_isLogin ? 'THE DEN' : 'CREATE ACCOUNT',
                  style: MehdAiTheme.headingStyle.copyWith(
                    color: MehdAiTheme.blue,
                    fontSize: 24,
                    letterSpacing: _isLogin ? 8 : 4,
                    fontWeight: FontWeight.bold)),
                const SizedBox(height: 6),
                Text(_isLogin ? 'Sign in to continue' : 'Join the AI-powered trading terminal',
                  style: MehdAiTheme.labelStyle.copyWith(
                    color: MehdAiTheme.textSecondary,
                    fontSize: 12)),
                const SizedBox(height: 40),
                
                // Name Field (Register Only)
                if (!_isLogin) ...[
                  _field(
                    controller: _nameCtrl,
                    label: 'DISPLAY NAME',
                    hint: 'Your Name',
                    validator: (v) => v!.trim().isEmpty ? 'Name required' : null,
                  ),
                  const SizedBox(height: 16),
                ],

                // Email field
                _field(
                  controller: _emailCtrl,
                  label: 'EMAIL ADDRESS',
                  hint: 'trader@example.com',
                  type: TextInputType.emailAddress,
                  validator: (v) => v!.contains('@') ? null : 'Valid email required',
                ),
                const SizedBox(height: 16),
                
                // Password field
                _passField(
                  controller: _passCtrl,
                  label: 'PASSWORD',
                  obscure: _obscurePass,
                  toggleObscure: () => setState(() => _obscurePass = !_obscurePass),
                  onChanged: _isLogin ? null : _updatePasswordStrength,
                ),
                
                // Strength Indicator (Register Only)
                if (!_isLogin) ...[
                  const SizedBox(height: 8),
                  _buildStrengthBar(),
                  const SizedBox(height: 16),
                  _passField(
                    controller: _confirmPassCtrl,
                    label: 'CONFIRM PASSWORD',
                    obscure: _obscureConfirm,
                    toggleObscure: () => setState(() => _obscureConfirm = !_obscureConfirm),
                    validator: (v) => v == _passCtrl.text ? null : 'Passwords do not match',
                  ),
                ],
                
                if (_isLogin) 
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _forgotPassword,
                      child: Text('Forgot password?',
                        style: MehdAiTheme.labelStyle.copyWith(fontSize: 11, color: Colors.grey)))),
                
                const SizedBox(height: 16),
                
                // Terms Checkbox (Register Only)
                if (!_isLogin) ...[
                  _buildTermsCheckbox(),
                  const SizedBox(height: 24),
                ],

                // Error message
                if (_errorMsg != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: Text(_errorMsg!,
                      style: MehdAiTheme.labelStyle.copyWith(
                        color: MehdAiTheme.gold,
                        fontSize: 12),
                      textAlign: TextAlign.center)),
                
                // SUBMIT button
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: MehdAiTheme.bgSecondary,
                      side: BorderSide(
                        color: _isLoading ? MehdAiTheme.borderColor : MehdAiTheme.blue,
                        width: 1.5),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8))),
                    child: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: MehdAiTheme.blue))
                      : Text(_isLogin ? 'ENTER THE DEN' : 'CREATE ACCOUNT',
                          style: MehdAiTheme.headingStyle.copyWith(
                            color: MehdAiTheme.blue,
                            fontSize: 14,
                            letterSpacing: 2,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
                
                const SizedBox(height: 24),
                
                if (kIsWeb || defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS) ...[
                  // OR divider
                  Row(children: [
                    const Expanded(child: Divider(color: MehdAiTheme.borderColor)),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Text('or',
                        style: MehdAiTheme.labelStyle.copyWith(fontSize: 11, color: Colors.grey))),
                    const Expanded(child: Divider(color: MehdAiTheme.borderColor)),
                  ]),
                  const SizedBox(height: 24),
                  
                  // Google button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton(
                      onPressed: _signInGoogle,
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: MehdAiTheme.borderColor),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8))),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.g_mobiledata, color: MehdAiTheme.textSecondary, size: 28),
                          const SizedBox(width: 4),
                          Text('Continue with Google',
                            style: MehdAiTheme.labelStyle.copyWith(fontSize: 13, color: MehdAiTheme.textSecondary)),
                        ]),
                    ),
                  ),
                  const SizedBox(height: 32),
                ],
                
                // Toggle link
                GestureDetector(
                  onTap: _toggleMode,
                  child: RichText(
                    text: TextSpan(children: [
                      TextSpan(
                        text: _isLogin ? 'New to Mehd AI? ' : 'Already have an account? ',
                        style: MehdAiTheme.labelStyle.copyWith(fontSize: 13, color: MehdAiTheme.textSecondary)),
                      TextSpan(
                        text: _isLogin ? 'Create account' : 'Sign in',
                        style: MehdAiTheme.labelStyle.copyWith(
                          color: MehdAiTheme.blue,
                          fontSize: 13,
                          decoration: TextDecoration.underline)),
                    ]),
                  ),
                ),
                const SizedBox(height: 48),
              ]),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _field({
    required TextEditingController controller,
    required String label,
    String? hint,
    TextInputType type = TextInputType.text,
    String? Function(String?)? validator,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: MehdAiTheme.labelStyle.copyWith(fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          keyboardType: type,
          validator: validator,
          style: MehdAiTheme.terminalStyle.copyWith(fontSize: 14, color: MehdAiTheme.textPrimary),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: MehdAiTheme.terminalStyle.copyWith(color: MehdAiTheme.textSecondary.withOpacity(0.3), fontSize: 14),
            enabledBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: MehdAiTheme.borderColor),
              borderRadius: BorderRadius.circular(8)),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: MehdAiTheme.blue, width: 1.5),
              borderRadius: BorderRadius.circular(8)),
            errorBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: MehdAiTheme.gold, width: 1.0),
              borderRadius: BorderRadius.circular(8)),
            focusedErrorBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: MehdAiTheme.gold, width: 1.5),
              borderRadius: BorderRadius.circular(8)),
            filled: true,
            fillColor: MehdAiTheme.bgSecondary,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16)),
        ),
      ],
    );
  }

  Widget _passField({
    required TextEditingController controller,
    required String label,
    required bool obscure,
    required VoidCallback toggleObscure,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: MehdAiTheme.labelStyle.copyWith(fontSize: 10, letterSpacing: 1.5, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          obscureText: obscure,
          validator: validator,
          onChanged: onChanged,
          style: MehdAiTheme.terminalStyle.copyWith(fontSize: 14, color: MehdAiTheme.textPrimary),
          decoration: InputDecoration(
            hintText: '••••••••',
            hintStyle: MehdAiTheme.terminalStyle.copyWith(color: MehdAiTheme.textSecondary.withOpacity(0.3), fontSize: 14),
            enabledBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: MehdAiTheme.borderColor),
              borderRadius: BorderRadius.circular(8)),
            focusedBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: MehdAiTheme.blue, width: 1.5),
              borderRadius: BorderRadius.circular(8)),
            errorBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: MehdAiTheme.gold, width: 1.0),
              borderRadius: BorderRadius.circular(8)),
            focusedErrorBorder: OutlineInputBorder(
              borderSide: const BorderSide(color: MehdAiTheme.gold, width: 1.5),
              borderRadius: BorderRadius.circular(8)),
            filled: true,
            fillColor: MehdAiTheme.bgSecondary,
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
            suffixIcon: IconButton(
              icon: Icon(obscure ? Icons.visibility_off : Icons.visibility, color: MehdAiTheme.textSecondary, size: 20),
              onPressed: toggleObscure,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStrengthBar() {
    return Row(
      children: List.generate(4, (index) {
        Color color = MehdAiTheme.borderColor;
        if (index < _passwordStrength) {
          if (_passwordStrength == 1) {
            color = MehdAiTheme.red;
          } else if (_passwordStrength == 2) {
            color = MehdAiTheme.gold;
          } else if (_passwordStrength == 3) {
            color = MehdAiTheme.blue;
          } else {
            color = MehdAiTheme.green;
          }
        }
        return Expanded(
          child: Container(
            height: 4,
            margin: const EdgeInsets.symmetric(horizontal: 2),
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2)),
          ),
        );
      }),
    );
  }

  Widget _buildTermsCheckbox() {
    return AuthTermsCheckbox(
      termsAccepted: _termsAccepted,
      onChanged: (v) => setState(() => _termsAccepted = v),
    );
  }
}
