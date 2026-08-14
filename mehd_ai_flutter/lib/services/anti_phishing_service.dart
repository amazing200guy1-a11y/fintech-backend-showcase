import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class AntiPhishingService extends ChangeNotifier {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const String _phishingCodeKey = 'mehd_anti_phishing_code';
  String _antiPhishingCode = '';

  String get antiPhishingCode => _antiPhishingCode;
  bool get hasCodeSet => _antiPhishingCode.isNotEmpty;

  AntiPhishingService() {
    _init();
  }

  Future<void> _init() async {
    final stored = await _storage.read(key: _phishingCodeKey);
    if (stored != null && stored.isNotEmpty) {
      _antiPhishingCode = stored;
    }
    notifyListeners();
  }

  /// Sets or updates the user's secret Anti-Phishing Phrase
  Future<bool> setAntiPhishingCode(String code) async {
    final trimmed = code.trim();
    if (trimmed.length < 3 || trimmed.length > 30) return false;
    await _storage.write(key: _phishingCodeKey, value: trimmed);
    _antiPhishingCode = trimmed;
    notifyListeners();
    return true;
  }

  /// Clears stored Anti-Phishing Phrase
  Future<void> clearAntiPhishingCode() async {
    await _storage.delete(key: _phishingCodeKey);
    _antiPhishingCode = '';
    notifyListeners();
  }
}
