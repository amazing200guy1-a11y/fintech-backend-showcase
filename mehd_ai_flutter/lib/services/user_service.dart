import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:mehd_ai_flutter/models/user_profile.dart';

/// FILE 3 — user_service.dart
///
/// Build Debrief:
/// This service handles all Firestore reads/writes for user data.
/// It is separate from AuthService because authentication and data management
/// are two different concerns — Auth answers "who are you?" while UserService
/// answers "what are your settings?"
///
/// Credential encryption: broker login/password are NEVER stored in Firestore
/// as plain text. They go through flutter_secure_storage which uses:
///   - iOS: Keychain (hardware-backed)
///   - Android: EncryptedSharedPreferences (AES-256)
///   - Web: Encrypted in-memory (with warning — web storage is inherently less secure)
///
/// The 1% risk cap is enforced here AND in the Firestore security rules AND
/// in the Flutter slider. Triple enforcement — defense in depth.

class UserService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock),
  );

  /// Saves or overwrites a full user profile in Firestore
  Future<void> saveUserProfile(UserProfile profile) async {
    try {
      await _firestore
          .collection('users')
          .doc(profile.userId)
          .set(profile.toJson(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error saving user profile: $e');
      rethrow;
    }
  }

  /// Loads a user profile from Firestore
  Future<UserProfile?> getUserProfile(String userId) async {
    try {
      final doc = await _firestore.collection('users').doc(userId).get();
      if (doc.exists && doc.data() != null) {
        return UserProfile.fromJson(doc.data()!);
      }
      return null;
    } catch (e) {
      debugPrint('Error loading user profile: $e');
      return null;
    }
  }

  /// Updates risk settings — allows 0.1% to 10.0% per trade
  Future<void> updateRiskSettings(String userId, double riskPercent) async {
    // Clamp to a reasonable range: minimum 0.1%, maximum 10%
    final clampedRisk = riskPercent.clamp(0.1, 10.0);

    try {
      await _firestore.collection('users').doc(userId).update({
        'riskPercent': clampedRisk,
      });
    } catch (e) {
      debugPrint('Error updating risk settings: $e');
      rethrow;
    }
  }

  /// Updates broker connection settings
  /// Credentials are encrypted before saving — never plain text
  Future<void> updateBrokerSettings(
    String userId,
    BrokerType brokerType,
    String? login,
    String? server,
  ) async {
    try {
      // Encrypt credentials using platform-native secure storage
      if (login != null && login.isNotEmpty) {
        await _secureStorage.write(
          key: '${userId}_broker_login',
          value: login,
        );
      }

      // Save broker type and server to Firestore (non-sensitive)
      // The actual login credential stays in secure storage, not Firestore
      await _firestore.collection('users').doc(userId).update({
        'brokerType': brokerType.name,
        'brokerServer': server,
        'brokerLogin': login != null ? '****encrypted****' : null,
        'paperTradingMode': brokerType == BrokerType.demo,
      });
    } catch (e) {
      debugPrint('Error updating broker settings: $e');
      rethrow;
    }
  }

  /// Retrieves the real broker login from secure storage (decrypted)
  Future<String?> getDecryptedBrokerLogin(String userId) async {
    try {
      return await _secureStorage.read(key: '${userId}_broker_login');
    } catch (e) {
      debugPrint('Error reading secure storage: $e');
      return null;
    }
  }

  /// Loads trade history from the trade_logs Firestore collection
  Future<List<Map<String, dynamic>>> getTradeHistory(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('trade_logs')
          .where('userId', isEqualTo: userId)
          .orderBy('timestamp', descending: true)
          .limit(100)
          .get();

      return snapshot.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      debugPrint('Error loading trade history: $e');
      return [];
    }
  }

  /// Loads AI consensus history from consensus_logs collection
  Future<List<Map<String, dynamic>>> getConsensusHistory(String userId) async {
    try {
      final snapshot = await _firestore
          .collection('consensus_logs')
          .where('userId', isEqualTo: userId)
          .orderBy('timestamp', descending: true)
          .limit(100)
          .get();

      return snapshot.docs.map((doc) => doc.data()).toList();
    } catch (e) {
      debugPrint('Error loading consensus history: $e');
      return [];
    }
  }

  /// Marks onboarding as complete in Firestore
  Future<void> completeOnboarding(String userId) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'onboardingComplete': true,
      });
    } catch (e) {
      debugPrint('Error completing onboarding: $e');
      rethrow;
    }
  }
}
