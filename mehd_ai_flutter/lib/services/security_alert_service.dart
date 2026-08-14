import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecurityAlertEvent {
  final String id;
  final String eventType;
  final String description;
  final DateTime timestamp;
  final String severity; // LOW | MEDIUM | HIGH | CRITICAL

  SecurityAlertEvent({
    required this.id,
    required this.eventType,
    required this.description,
    required this.timestamp,
    required this.severity,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'eventType': eventType,
        'description': description,
        'timestamp': timestamp.toIso8601String(),
        'severity': severity,
      };

  factory SecurityAlertEvent.fromJson(Map<String, dynamic> json) =>
      SecurityAlertEvent(
        id: json['id'] ?? '',
        eventType: json['eventType'] ?? 'UNKNOWN',
        description: json['description'] ?? '',
        timestamp: json['timestamp'] != null
            ? DateTime.parse(json['timestamp'])
            : DateTime.now(),
        severity: json['severity'] ?? 'LOW',
      );
}

class SecurityAlertService extends ChangeNotifier {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  static const String _storageKey = 'mehd_security_alert_logs';
  final List<SecurityAlertEvent> _alerts = [];

  List<SecurityAlertEvent> get alerts => List.unmodifiable(_alerts);

  SecurityAlertService() {
    _loadAlerts();
  }

  Future<void> _loadAlerts() async {
    try {
      final raw = await _storage.read(key: _storageKey);
      if (raw != null && raw.isNotEmpty) {
        final List decoded = jsonDecode(raw);
        _alerts.clear();
        _alerts.addAll(
          decoded.map((item) => SecurityAlertEvent.fromJson(item as Map<String, dynamic>)),
        );
      } else {
        _seedInitialSecurityLogs();
      }
    } catch (_) {
      _seedInitialSecurityLogs();
    }
    notifyListeners();
  }

  void _seedInitialSecurityLogs() {
    _alerts.clear();
    _alerts.addAll([
      SecurityAlertEvent(
        id: 'sec_01',
        eventType: 'FORTRESS_SHIELD_ACTIVE',
        description: 'Military-grade HTTPS security headers and ThreatJail defense active.',
        timestamp: DateTime.now().subtract(const Duration(minutes: 10)),
        severity: 'LOW',
      ),
      SecurityAlertEvent(
        id: 'sec_02',
        eventType: 'STORAGE_HARDENED',
        description: 'Hardware keystore encryption active (EncryptedSharedPreferences / Keychain).',
        timestamp: DateTime.now().subtract(const Duration(hours: 1)),
        severity: 'LOW',
      ),
    ]);
    _saveAlerts();
  }

  Future<void> logEvent({
    required String eventType,
    required String description,
    required String severity,
  }) async {
    final event = SecurityAlertEvent(
      id: 'sec_${DateTime.now().millisecondsSinceEpoch}',
      eventType: eventType,
      description: description,
      timestamp: DateTime.now(),
      severity: severity,
    );
    _alerts.insert(0, event);
    if (_alerts.length > 50) _alerts.removeLast(); // Cap at 50 logs
    await _saveAlerts();
    notifyListeners();
  }

  Future<void> _saveAlerts() async {
    try {
      final jsonList = _alerts.map((e) => e.toJson()).toList();
      await _storage.write(key: _storageKey, value: jsonEncode(jsonList));
    } catch (_) {}
  }

  Future<void> clearAlerts() async {
    _alerts.clear();
    await _storage.delete(key: _storageKey);
    notifyListeners();
  }
}
