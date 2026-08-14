import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:math';
import 'package:firebase_core/firebase_core.dart';
import 'package:mehd_ai_flutter/core/constants.dart';

class PaymentService extends ChangeNotifier {
  String _currentTier = 'institutional'; // TEMP: bypassed for UI inspection — restore to 'observer'
  int _analysesPerDay = 999; // TEMP: bypassed for UI inspection — restore to 0
  int _tokensUsedToday = 0;
  int _analysesUsedToday = 0;
  final bool _isLoading = false;
  String? _portalUrl; // Billing management URL (Paddle or pricing page)

  /// VULN-FIX: Auto-fetch tier on construction so users never see stale data.
  /// Firebase auth state listener ensures we fetch as soon as the user is logged in.
  PaymentService() {
    _initAsync();
  }

  Future<void> _initAsync() async {
    // Poll for Firebase ready state in parallel boot scenario
    int attempts = 0;
    while (Firebase.apps.isEmpty && attempts < 20) {
      await Future.delayed(const Duration(milliseconds: 200));
      attempts++;
    }

    if (Firebase.apps.isNotEmpty) {
      FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user != null) {
          fetchStatus();
        }
      });
    } else {
      debugPrint("DEN_PAYMENT: Firebase failed to initialize in time.");
    }
  }

  // Trial state
  bool _isOnTrial = false;
  int _trialDaysRemaining = 0;
  String? _trialTier;

  // Tiger Mode State (Temporary Override)
  bool _isTigerModeEnabled = false;
  bool get isTigerModeEnabled => _isTigerModeEnabled;

  void toggleTigerMode(bool value) {
    _isTigerModeEnabled = value;
    notifyListeners();
  }

  // Returns 'tiger' if Tiger Mode is ON, otherwise returns the actual subscribed tier
  String get currentTier => _isTigerModeEnabled ? 'tiger' : _currentTier;
  
  // To allow UI components to still display the real subscription plan
  String get realSubscriptionTier => _currentTier;

  int get analysesPerDay => _analysesPerDay;
  int get tokensUsedToday => _tokensUsedToday;
  int get analysesUsedToday => _analysesUsedToday;
  bool get isLoading => _isLoading;
  String? get portalUrl => _portalUrl;

  // Trial getters
  bool get isOnTrial => _isOnTrial;
  int get trialDaysRemaining => _trialDaysRemaining;
  String? get trialTier => _trialTier;
  bool get isTrialExpired =>
      !_isOnTrial && _trialDaysRemaining == 0 && _currentTier == 'observer';

  /// FIX #9: Use flutter_secure_storage for device ID — prevents trial abuse
  /// via clearing app data (secure storage persists differently per platform).
  static const _secureStorage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  Future<String> _getDeviceId() async {
    String? deviceId = await _secureStorage.read(key: 'mehd_device_id');
    if (deviceId == null) {
      deviceId =
          'DEV_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(1000000)}';
      await _secureStorage.write(key: 'mehd_device_id', value: deviceId);
    }
    return deviceId;
  }

  /// Activate the 3-day free Institutional trial.
  /// Returns a status string: 'success', 'already_active', or the error details
  /// (e.g., if phone is missing or duplicate).
  Future<String> activateTrial() async {
    if (Firebase.apps.isEmpty) return 'Firebase not initialized';
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return 'User not authenticated';

    try {
      final token = await user.getIdToken();
      final deviceId = await _getDeviceId();

      final response = await http.post(
        Uri.parse('${AppConstants.baseUrl}/payments/activate-trial'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
          'X-Device-ID': deviceId,
        },
      ).timeout(const Duration(seconds: 15));

      final data = jsonDecode(response.body);
      if (response.statusCode == 200) {
        debugPrint('🔥 TRIAL: ${data['message']}');
        // Refresh status to pick up new tier
        await fetchStatus();
        return data['status'] ?? 'success';
      } else {
        final String errorDetail = data['detail'] ?? 'Failed to activate trial';
        debugPrint('Trial activation rejected: $errorDetail');
        return errorDetail;
      }
    } catch (e) {
      debugPrint('Trial activation error: $e');
      return 'Network error: $e';
    }
  }

  Future<void> fetchStatus() async {
    if (Firebase.apps.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final token = await user.getIdToken();
    try {
      final response = await http.get(
        Uri.parse('${AppConstants.baseUrl}/payments/status'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        _currentTier = data['tier'] ?? 'observer';
        _analysesPerDay = data['analyses_per_day'] ?? 1;
        _tokensUsedToday = data['tokens_used_today'] ?? 0;
        _analysesUsedToday = data['analyses_used_today'] ?? 0;
        _isOnTrial = data['is_trial'] ?? false;
        _trialDaysRemaining = data['trial_days_remaining'] ?? 0;
        _trialTier = data['trial_tier'];
        _portalUrl = data['portal_url'];
        // VULN-FIX: Cache tier in ENCRYPTED secure storage (not plain-text SharedPreferences).
        // SharedPreferences is stored as plain XML on Android — a rooted device can edit it.
        // FlutterSecureStorage uses Android Keystore / iOS Keychain — tamper-proof.
        await _secureStorage.write(key: 'cached_tier', value: _currentTier);
        await _secureStorage.write(key: 'cached_analyses_per_day', value: _analysesPerDay.toString());
        await _secureStorage.write(key: 'cached_analyses_used_today', value: _analysesUsedToday.toString());
        notifyListeners();
      } else {
        debugPrint('Failed to fetch subscription status: ${response.body}');
      }
    } catch (e) {
      debugPrint('Error fetching subscription status: $e');
      // VULN-FIX: On network failure, restore from ENCRYPTED secure storage
      // so paying users aren't downgraded during temporary connectivity issues.
      _currentTier = await _secureStorage.read(key: 'cached_tier') ?? _currentTier;
      final cachedAnalyses = await _secureStorage.read(key: 'cached_analyses_per_day');
      if (cachedAnalyses != null) _analysesPerDay = int.tryParse(cachedAnalyses) ?? _analysesPerDay;
      final cachedUsed = await _secureStorage.read(key: 'cached_analyses_used_today');
      if (cachedUsed != null) _analysesUsedToday = int.tryParse(cachedUsed) ?? _analysesUsedToday;
      notifyListeners();
    }
  }

}
