import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SettingsService extends ChangeNotifier {
  Future<SharedPreferences> get _prefs async {
    try {
      return await SharedPreferences.getInstance();
    } catch (e) {
      debugPrint("SettingsService: LocalStorage blocked, falling back to mock: $e");
      // ignore: invalid_use_of_visible_for_testing_member
      SharedPreferences.setMockInitialValues({});
      return await SharedPreferences.getInstance();
    }
  }
  StreamSubscription<User?>? _authSub;

  SettingsService() {
    _setupAuthListener();
  }

  void _setupAuthListener() {
    try {
      _authSub = FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user != null) {
          load().catchError((e) {
            debugPrint("SettingsService: Error loading cloud settings: $e");
          });
        }
      });
    } catch (e) {
      // Firebase not yet initialized — retry after 3 seconds
      debugPrint("SettingsService: Firebase not ready, will retry auth listener in 3s: $e");
      Future.delayed(const Duration(seconds: 3), _setupAuthListener);
    }
  }

  @override
  void dispose() {
    _authSub?.cancel();
    super.dispose();
  }

  bool _darkMode = true;
  bool _tradeSignals = true;
  bool _autoStopLoss = true;
  bool _guardianAlerts = true;
  bool _showAgentNames = true;
  bool _sandboxMode = false;
  bool _paperMode = true;
  bool _autopilotEngaged = true;   // Autopilot Command Center master switch
  bool _alphaPredatorMode = false; // 1.5x lot size boost on ≥92% conviction
  String _language = 'English';
  double _convictionThreshold = 75.0;
  double _defaultLotSize = 1.00;

  // Global Risk Settings
  double _accountBalance = 10000.0;
  double _riskPerTrade = 1.0;
  double _defaultStopLoss = 2.0;   // pips — kept within slider range (max 10)
  double _defaultLeverage = 100.0;

  bool get darkMode => _darkMode;
  bool get tradeSignals => _tradeSignals;
  bool get autoStopLoss => _autoStopLoss;
  bool get guardianAlerts => _guardianAlerts;
  bool get showAgentNames => _showAgentNames;
  bool get sandboxMode => _sandboxMode;
  bool get paperMode => _paperMode;
  bool get autopilotEngaged => _autopilotEngaged;
  bool get alphaPredatorMode => _alphaPredatorMode;
  String get language => _language;
  double get convictionThreshold => _convictionThreshold;
  double get defaultLotSize => _defaultLotSize;

  String _profileName = 'Trader';
  int _maxDailyTrades = 3;

  // Active broker connection — broadcast to the whole ecosystem.
  // Set by BrokerScreen when trader connects. Empty string = no broker connected.
  String _connectedBrokerId = '';
  String _connectedBrokerType = ''; // 'demo' | 'live' | ''

  String get profileName => _profileName;
  int get maxDailyTrades => _maxDailyTrades;

  String get connectedBrokerId => _connectedBrokerId;
  String get connectedBrokerType => _connectedBrokerType;
  bool get hasBrokerConnected => _connectedBrokerId.isNotEmpty;

  double get accountBalance => _accountBalance;
  double get riskPerTrade => _riskPerTrade;
  double get defaultStopLoss => _defaultStopLoss;
  double get defaultLeverage => _defaultLeverage;

  /// Loads settings — cloud first, device fallback.
  /// On a new device, this restores all the user's saved preferences
  /// from their Firebase account automatically.
  Future<void> load() async {
    final p = await _prefs;
    String? uid;
    try {
      uid = FirebaseAuth.instance.currentUser?.uid;
    } catch (e) {
      debugPrint("SettingsService: Firebase not initialized in load(), using local prefs only: $e");
    }

    // ── 1. Try to pull from Firestore (cloud-first) ───────────────────────
    Map<String, dynamic> cloud = {};
    if (uid != null) {
      try {
        final doc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('settings')
            .doc('prefs')
            .get();
        if (doc.exists) cloud = doc.data() ?? {};
      } catch (_) {
        // No internet / Firestore unavailable — fall through to local
      }
    }

    // ── 2. Apply values: cloud wins, local is fallback, defaults are last ──
    _darkMode           = (cloud['darkMode']        as bool?)   ?? p.getBool('darkMode')        ?? true;
    _tradeSignals       = (cloud['signals']         as bool?)   ?? p.getBool('signals')         ?? true;
    _autoStopLoss       = (cloud['autoSL']          as bool?)   ?? p.getBool('autoSL')          ?? true;
    _guardianAlerts     = (cloud['guardian']        as bool?)   ?? p.getBool('guardian')        ?? true;
    _showAgentNames     = (cloud['agentNames']      as bool?)   ?? p.getBool('agentNames')      ?? true;
    _sandboxMode        = (cloud['sandbox']         as bool?)   ?? p.getBool('sandbox')         ?? false;
    _paperMode          = (cloud['paper']           as bool?)   ?? p.getBool('paper')           ?? true;
    _autopilotEngaged   = (cloud['autopilotEngaged'] as bool?)  ?? p.getBool('autopilotEngaged') ?? true;
    _alphaPredatorMode  = (cloud['alphaPredator']   as bool?)   ?? p.getBool('alphaPredator')   ?? false;
    _language           = (cloud['language']        as String?) ?? p.getString('language')      ?? 'English';
    _convictionThreshold= (cloud['conviction']      as num?)?.toDouble() ?? p.getDouble('conviction')    ?? 75.0;
    _defaultLotSize     = ((cloud['defaultLotSize']  as num?)?.toDouble() ?? p.getDouble('defaultLotSize')  ?? 1.00).clamp(0.01, 10.0);
    _profileName        = (cloud['profileName']     as String?) ?? p.getString('profileName')      ?? 'Trader';
    _maxDailyTrades     = (cloud['maxDailyTrades']  as num?)?.toInt()    ?? p.getInt('maxDailyTrades')       ?? 3;
    _accountBalance     = (cloud['accountBalance']  as num?)?.toDouble() ?? p.getDouble('accountBalance')  ?? 10000.0;
    _riskPerTrade       = ((cloud['riskPerTrade']    as num?)?.toDouble() ?? p.getDouble('riskPerTrade')    ?? 1.0).clamp(0.1, 10.0);
    _defaultStopLoss    = ((cloud['defaultStopLoss'] as num?)?.toDouble() ?? p.getDouble('defaultStopLoss') ?? 2.0).clamp(0.1, 10.0);
    _defaultLeverage    = (cloud['defaultLeverage'] as num?)?.toDouble() ?? p.getDouble('defaultLeverage') ?? 100.0;
    _connectedBrokerId  = (cloud['connectedBroker'] as String?) ?? p.getString('connectedBroker') ?? '';
    _connectedBrokerType= (cloud['connectedBrokerType'] as String?) ?? p.getString('connectedBrokerType') ?? '';

    // ── 3. Write cloud values back to local cache (keeps device in sync) ───
    if (cloud.isNotEmpty) {
      await p.setBool('darkMode',       _darkMode);
      await p.setBool('signals',        _tradeSignals);
      await p.setBool('autoSL',         _autoStopLoss);
      await p.setBool('guardian',       _guardianAlerts);
      await p.setBool('agentNames',     _showAgentNames);
      await p.setBool('sandbox',        _sandboxMode);
      await p.setBool('paper',          _paperMode);
      await p.setString('language',     _language);
      await p.setDouble('conviction',   _convictionThreshold);
      await p.setDouble('defaultLotSize', _defaultLotSize);
      await p.setDouble('accountBalance', _accountBalance);
      await p.setDouble('riskPerTrade',   _riskPerTrade);
      await p.setDouble('defaultStopLoss',_defaultStopLoss);
      await p.setDouble('defaultLeverage',_defaultLeverage);
    }

    notifyListeners();
  }

  Future<void> _save(String key, dynamic val) async {
    final p = await _prefs;
    if (val is bool) await p.setBool(key, val);
    if (val is String) await p.setString(key, val);
    if (val is double) await p.setDouble(key, val);
    
    // Sync to Firebase if user is logged in
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        await FirebaseFirestore.instance
          .collection('users').doc(uid)
          .collection('settings').doc('prefs')
          .set({key: val}, SetOptions(merge: true));
      } catch (e) {
        // Ignored
      }
    }
    notifyListeners();
  }

  Future<void> setDarkMode(bool v) async {
    _darkMode = v;
    await _save('darkMode', v);
  }

  Future<void> setTradeSignals(bool v) async {
    _tradeSignals = v;
    await _save('signals', v);
  }

  Future<void> setAutoStopLoss(bool v) async {
    _autoStopLoss = v;
    await _save('autoSL', v);
  }

  Future<void> setGuardianAlerts(bool v) async {
    _guardianAlerts = v;
    await _save('guardian', v);
  }

  Future<void> setShowAgentNames(bool v) async {
    _showAgentNames = v;
    await _save('agentNames', v);
  }

  Future<void> setSandboxMode(bool v) async {
    _sandboxMode = v;
    await _save('sandbox', v);
    // Update Firebase visibility on parent user document:
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      try {
        await FirebaseFirestore.instance
          .collection('users').doc(uid)
          .update({'sandboxMode': v});
      } catch (e) {
        // Ignored
      }
    }
  }

  Future<void> setPaperMode(bool v) async {
    _paperMode = v;
    await _save('paper', v);
  }

  Future<void> setAutopilotEngaged(bool v) async {
    _autopilotEngaged = v;
    await _save('autopilotEngaged', v);
  }

  Future<void> setAlphaPredatorMode(bool v) async {
    _alphaPredatorMode = v;
    await _save('alphaPredator', v);
  }

  Future<void> setLanguage(String lang) async {
    _language = lang;
    await _save('language', lang);
  }

  Future<void> setConvictionThreshold(double v, {bool save = true}) async {
    _convictionThreshold = v;
    notifyListeners();
    if (save) {
      await _save('conviction', v);
    }
  }

  Future<void> setAccountBalance(double v) async {
    _accountBalance = v;
    await _save('accountBalance', v);
  }

  Future<void> setRiskPerTrade(double v, {bool save = true}) async {
    _riskPerTrade = v;
    notifyListeners();
    if (save) {
      await _save('riskPerTrade', v);
    }
  }

  Future<void> setDefaultStopLoss(double v) async {
    _defaultStopLoss = v;
    await _save('defaultStopLoss', v);
  }

  Future<void> setDefaultLeverage(double v) async {
    _defaultLeverage = v;
    await _save('defaultLeverage', v);
  }

  Future<void> setDefaultLotSize(double v, {bool save = true}) async {
    _defaultLotSize = v;
    notifyListeners();
    if (save) {
      await _save('defaultLotSize', v);
    }
  }

  Future<void> setProfileName(String name) async {
    _profileName = name;
    await _save('profileName', name);
  }

  Future<void> setMaxDailyTrades(int count) async {
    _maxDailyTrades = count;
    await _save('maxDailyTrades', count);
  }

  /// Called by BrokerScreen when a broker is connected or disconnected.
  /// Broadcasts to the entire ecosystem via notifyListeners().
  Future<void> setConnectedBroker(String brokerId, String brokerType) async {
    _connectedBrokerId = brokerId;
    _connectedBrokerType = brokerType;
    await _save('connectedBroker', brokerId);
    await _save('connectedBrokerType', brokerType);
  }

  Future<void> clearBrokerConnection() async {
    _connectedBrokerId = '';
    _connectedBrokerType = '';
    await _save('connectedBroker', '');
    await _save('connectedBrokerType', '');
  }

  Future<void> clearLocal() async {
    final p = await _prefs;
    await p.clear();
    await load();
  }
}
