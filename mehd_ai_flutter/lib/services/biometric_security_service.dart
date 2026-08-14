import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class BiometricSecurityService extends ChangeNotifier {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const String _pinKey = 'mehd_security_pin_hash';
  static const String _enabledKey = 'mehd_security_pin_enabled';
  static const String _codenameKey = 'mehd_war_room_codename';
  
  bool _isLocked = false;
  bool _isPinSet = false;
  String _codename = ''; // e.g. 'Golden Falcon 2026'
  DateTime? _lastActivityTime;
  static const Duration inactivityTimeout = Duration(minutes: 5);

  bool get isLocked => _isLocked;
  bool get isPinSet => _isPinSet;
  String get codename => _codename;

  BiometricSecurityService() {
    _init();
  }

  Future<String?> _readKey(String key) async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        return prefs.getString(key);
      } else {
        return await _storage.read(key: key);
      }
    } catch (e) {
      debugPrint("BiometricSecurity: readKey error on key $key: $e");
      return null;
    }
  }

  Future<void> _writeKey(String key, String value) async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(key, value);
      } else {
        await _storage.write(key: key, value: value);
      }
    } catch (e) {
      debugPrint("BiometricSecurity: writeKey error on key $key: $e");
    }
  }

  Future<void> _deleteKey(String key) async {
    try {
      if (kIsWeb) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(key);
      } else {
        await _storage.delete(key: key);
      }
    } catch (e) {
      debugPrint("BiometricSecurity: deleteKey error on key $key: $e");
    }
  }

  Future<void> _init() async {
    final pinHash = await _readKey(_pinKey);
    final enabled = await _readKey(_enabledKey);
    final savedCodename = await _readKey(_codenameKey);
    _isPinSet = (pinHash != null && pinHash.isNotEmpty) && (enabled == 'true');
    _codename = savedCodename ?? '';
    if (_isPinSet) {
      _isLocked = true; // Lock on boot if PIN is set & enabled
    } else {
      _isLocked = false;
    }
    _updateActivity();
    notifyListeners();
  }

  void _updateActivity() {
    _lastActivityTime = DateTime.now();
  }

  /// Hashes a 4-digit PIN using SHA-256 for secure comparison
  String _hashPin(String pin) {
    return sha256.convert(utf8.encode('MEHD_PIN_SALT_$pin')).toString();
  }

  /// Sets up a new 4-digit PIN
  Future<bool> setPin(String pin) async {
    if (pin.length != 4 || int.tryParse(pin) == null) return false;
    final hash = _hashPin(pin);
    await _writeKey(_pinKey, hash);
    await _writeKey(_enabledKey, 'true');
    _isPinSet = true;
    _isLocked = false;
    _updateActivity();
    notifyListeners();
    return true;
  }

  /// Verifies an entered PIN against stored hash
  Future<bool> verifyPin(String pin) async {
    if (!_isPinSet) return true;
    final storedHash = await _readKey(_pinKey);
    final inputHash = _hashPin(pin);
    if (storedHash == inputHash) {
      _isLocked = false;
      _updateActivity();
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Clears stored PIN security
  Future<void> disablePin() async {
    await _deleteKey(_pinKey);
    await _writeKey(_enabledKey, 'false');
    _isPinSet = false;
    _isLocked = false;
    notifyListeners();
  }


  /// Manually locks the application
  void lockApp() {
    if (_isPinSet) {
      _isLocked = true;
      notifyListeners();
    }
  }

  /// Checks if app should auto-lock due to 5 minutes of inactivity
  void checkInactivityAutoLock() {
    if (!_isPinSet || _isLocked) return;
    if (_lastActivityTime != null) {
      final elapsed = DateTime.now().difference(_lastActivityTime!);
      if (elapsed >= inactivityTimeout) {
        _isLocked = true;
        notifyListeners();
      }
    }
  }

  /// Registers user touch/action to reset 5-minute inactivity timer
  void registerUserActivity() {
    _updateActivity();
  }

  /// Sets the user's personal War Room codename (e.g. 'Golden Falcon 2026')
  Future<void> setCodename(String name) async {
    final trimmed = name.trim();
    await _writeKey(_codenameKey, trimmed);
    _codename = trimmed;
    notifyListeners();
  }

  /// Clears the War Room codename
  Future<void> clearCodename() async {
    await _deleteKey(_codenameKey);
    _codename = '';
    notifyListeners();
  }
}
