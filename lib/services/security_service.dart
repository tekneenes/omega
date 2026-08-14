import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';

class SecurityService {
  /// Generates a random 6-digit pair PIN (e.g., "789123")
  static String generatePairPin() {
    final random = Random.secure();
    final pin = List.generate(6, (_) => random.nextInt(10)).join('');
    return pin;
  }

  /// Generates a SHA-256 hash string for securing communication topics
  static String hashKey(String input) {
    final bytes = utf8.encode(input);
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  /// Encrypts text using simple symmetric stream cipher for E2EE payload
  static String encryptPayload(String text, String secretKey) {
    final keyBytes = utf8.encode(secretKey);
    final textBytes = utf8.encode(text);
    final encrypted = List<int>.generate(textBytes.length, (i) {
      return textBytes[i] ^ keyBytes[i % keyBytes.length];
    });
    return base64.encode(encrypted);
  }

  /// Decrypts text using simple symmetric stream cipher
  static String decryptPayload(String base64Encrypted, String secretKey) {
    try {
      final encryptedBytes = base64.decode(base64Encrypted);
      final keyBytes = utf8.encode(secretKey);
      final decrypted = List<int>.generate(encryptedBytes.length, (i) {
        return encryptedBytes[i] ^ keyBytes[i % keyBytes.length];
      });
      return utf8.decode(decrypted);
    } catch (_) {
      return base64Encrypted;
    }
  }
}
