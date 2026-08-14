import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:uuid/uuid.dart';

class RequestSigner {
  static const _uuid = Uuid();

  /// Generates a signed request header map containing:
  /// - `X-Timestamp`: Current UTC timestamp in epoch milliseconds
  /// - `X-Nonce`: Cryptographically unique UUID v4 nonce
  /// - `X-Signature`: HMAC-SHA256 digest of "{timestamp}.{nonce}.{body_utf8}"
  static Map<String, String> generateSignedHeaders({
    required String body,
    required String secret,
  }) {
    final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
    final nonce = _uuid.v4();

    final messageBytes = utf8.encode('$timestamp.$nonce.$body');
    final secretBytes = utf8.encode(secret);

    final hmacSha256 = Hmac(sha256, secretBytes);
    final digest = hmacSha256.convert(messageBytes);

    return {
      'X-Timestamp': timestamp,
      'X-Nonce': nonce,
      'X-Signature': digest.toString(),
    };
  }
}
