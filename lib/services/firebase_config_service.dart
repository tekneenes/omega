import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../firebase_options.dart';

/// Manages dynamic Firebase Realtime Database URL configurations,
/// live ping tests, automated Security Rules deployment, and Family Network QR sharing.
class FirebaseConfigService {
  static const String keyCustomRtdbUrl = 'omega_custom_rtdb_url';
  static const String keyNetworkId = 'omega_network_id';
  static const String qrPrefix = 'omega_net://v1?url=';

  /// Standard Optimized Security Rules & Index Configuration for Omega
  /// CRITICAL: Node names MUST match the exact paths used in SignalingService code.
  /// calls → /calls/$targetId (flat set/update, NOT nested $targetId/$callId)
  /// candidates → /candidates/$targetId (flat push, NOT nested)
  /// msg_status → code uses "msg_status", NOT "message_status"
  /// typing_status → code uses "typing_status", NOT "typing"
  static const Map<String, dynamic> omegaRulesMap = {
    "rules": {
      "devices": {
        ".read": true,
        ".write": true,
        "\$deviceId": {
          ".read": true,
          ".write": true,
          ".indexOn": ["pairCode", "phoneNumber", "email"]
        }
      },
      "pairs": {
        ".read": true,
        ".write": true,
        "\$pairCode": {
          ".read": true,
          ".write": true
        }
      },
      "calls": {
        "\$targetId": {
          ".read": true,
          ".write": true
        }
      },
      "candidates": {
        "\$targetId": {
          ".read": true,
          ".write": true
        }
      },
      "messages": {
        "\$targetId": {
          ".read": true,
          ".write": true,
          ".indexOn": ["timestamp", "senderId"]
        }
      },
      "msg_status": {
        "\$targetId": {
          ".read": true,
          ".write": true
        }
      },
      "typing_status": {
        "\$targetId": {
          ".read": true,
          ".write": true
        }
      },
      "group_chat": {
        ".read": true,
        ".write": true,
        ".indexOn": ["timestamp"]
      },
      "group_typing": {
        ".read": true,
        ".write": true
      },
      "viewers": {
        "\$broadcasterId": {
          ".read": true,
          ".write": true
        }
      },
      "network_settings": {
        ".read": true,
        ".write": true
      },
      "telemetry": {
        "\$deviceId": {
          ".read": true,
          ".write": true
        }
      },
      "history_calls": {
        "\$pinCode": {
          ".read": true,
          ".write": true
        }
      },
      "history_chats": {
        "\$pinCode": {
          ".read": true,
          ".write": true,
          ".indexOn": ["timestamp"]
        }
      },
      "camera_motion_alerts": {
        "\$channelId": {
          ".read": true,
          ".write": true
        }
      },
      "family_cameras": {
        "\$pin": {
          ".read": true,
          ".write": true
        }
      },
      "camera_signaling": {
        "\$cameraDeviceId": {
          ".read": true,
          ".write": true
        }
      },
      "camera_ice": {
        "\$cameraDeviceId": {
          ".read": true,
          ".write": true
        }
      },
      "camera_talk_lock": {
        "\$familyPin": {
          ".read": true,
          ".write": true
        }
      },
      "group_messages": {
        "\$familyPin": {
          ".read": true,
          ".write": true,
          ".indexOn": ["timestamp"]
        }
      },
      "group_inbox": {
        "\$inboxNode": {
          ".read": true,
          ".write": true
        }
      },
      "fcmTokens": {
        "\$deviceId": {
          ".read": true,
          ".write": true
        }
      },
      "fcm_queue": {
        ".read": true,
        ".write": true
      }
    }
  };

  static const String keyIsNetworkAdmin = 'omega_is_network_admin';
  static const String keyAdminOnlySharing = 'omega_admin_only_sharing';

  static String get formattedRulesJson =>
      const JsonEncoder.withIndent('  ').convert(omegaRulesMap);

  /// Checks if this device is the Network Administrator (the one that created the network)
  static Future<bool> isNetworkAdmin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(keyIsNetworkAdmin) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Sets whether this device is the Network Administrator
  static Future<void> setIsNetworkAdmin(bool isAdmin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyIsNetworkAdmin, isAdmin);
  }

  /// Checks if sharing is restricted to Admin Only (default: true)
  static Future<bool> isAdminOnlySharing() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(keyAdminOnlySharing) ?? true;
    } catch (_) {
      return true;
    }
  }

  /// Sets whether only the admin can share the network QR
  static Future<void> setAdminOnlySharing(bool adminOnly) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(keyAdminOnlySharing, adminOnly);
  }

  /// Checks if current device is allowed to generate & show the Family Network QR code
  static Future<bool> canShareNetworkQr() async {
    final isAdmin = await isNetworkAdmin();
    if (isAdmin) return true;
    final adminOnly = await isAdminOnlySharing();
    return !adminOnly;
  }

  /// Returns the saved custom RTDB URL or null if clean/unconfigured
  static Future<String?> getSavedCustomRtdbUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final customUrl = prefs.getString(keyCustomRtdbUrl);
      if (customUrl != null && customUrl.trim().isNotEmpty) {
        return cleanRtdbUrl(customUrl.trim());
      }
    } catch (e) {
      debugPrint('⚠️ [FIREBASE CONFIG] Error reading custom RTDB URL: $e');
    }
    return null;
  }

  /// Clears any saved custom RTDB URL for a fresh start
  static Future<void> clearSavedRtdbUrl() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(keyCustomRtdbUrl);
      debugPrint('🧹 [FIREBASE CONFIG] Cleared saved custom RTDB URL.');
    } catch (e) {
      debugPrint('⚠️ [FIREBASE CONFIG] Error clearing custom RTDB URL: $e');
    }
  }

  /// Returns the active Firebase Realtime Database URL (custom or fallback default)
  static Future<String> getActiveRtdbUrl() async {
    final saved = await getSavedCustomRtdbUrl();
    if (saved != null && saved.isNotEmpty) {
      return saved;
    }
    return cleanRtdbUrl(DefaultFirebaseOptions.rtdbUrl);
  }

  /// Cleans and formats raw URL input (trims trailing slashes, whitespace, .json suffix)
  static String cleanRtdbUrl(String rawUrl) {
    var url = rawUrl.trim();
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      url = 'https://$url';
    }
    if (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.endsWith('.json')) {
      url = url.substring(0, url.length - 5);
    }
    return url;
  }

  /// Saves the active custom RTDB URL locally
  static Future<void> saveActiveRtdbUrl(String url) async {
    final cleaned = cleanRtdbUrl(url);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(keyCustomRtdbUrl, cleaned);
    debugPrint('🔥 [FIREBASE CONFIG] Saved active RTDB URL: $cleaned');
  }

  /// Tests connectivity to the given Firebase RTDB URL
  /// Returns a map with success boolean, status message, and latency ms.
  static Future<Map<String, dynamic>> testConnection(String rawUrl) async {
    final cleanUrl = cleanRtdbUrl(rawUrl);
    final stopwatch = Stopwatch()..start();

    try {
      final pingUri = Uri.parse('$cleanUrl/.json?shallow=true');
      final response = await http.get(pingUri).timeout(const Duration(seconds: 8));
      stopwatch.stop();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return {
          'success': true,
          'statusCode': response.statusCode,
          'latencyMs': stopwatch.elapsedMilliseconds,
          'message': 'Bağlantı başarılı! (${stopwatch.elapsedMilliseconds} ms)',
          'url': cleanUrl,
        };
      } else if (response.statusCode == 401 || response.statusCode == 403) {
        // Permission denied means the database exists and responded!
        return {
          'success': true,
          'statusCode': response.statusCode,
          'latencyMs': stopwatch.elapsedMilliseconds,
          'message': 'Veritabanı bulundu (Kurallar ayarlanabilir).',
          'url': cleanUrl,
        };
      } else {
        return {
          'success': false,
          'statusCode': response.statusCode,
          'latencyMs': stopwatch.elapsedMilliseconds,
          'message': 'Sunucu yanıt verdi ancak durum kodu geçersiz: ${response.statusCode}',
          'url': cleanUrl,
        };
      }
    } catch (e) {
      stopwatch.stop();
      return {
        'success': false,
        'latencyMs': stopwatch.elapsedMilliseconds,
        'message': 'Bağlantı kurulamadı: ${e.toString().replaceAll('Exception: ', '')}',
        'url': cleanUrl,
      };
    }
  }

  /// Automatically deploys security rules and index definitions via Firebase REST API
  static Future<Map<String, dynamic>> deployRules(String rawUrl) async {
    final cleanUrl = cleanRtdbUrl(rawUrl);
    try {
      final rulesUri = Uri.parse('$cleanUrl/.settings/rules.json');
      final response = await http
          .put(
            rulesUri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(omegaRulesMap),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        debugPrint('🛡️ [FIREBASE RULES SUCCESS] Rules automatically deployed to $cleanUrl');
        return {
          'success': true,
          'message': 'Güvenlik kuralları ve indeksler başarıyla yüklendi!',
        };
      } else {
        debugPrint('⚠️ [FIREBASE RULES NOTICE]: Status code ${response.statusCode}');
        return {
          'success': false,
          'statusCode': response.statusCode,
          'message':
              'Otomatik yükleme tamamlanamadı (${response.statusCode}). Lütfen kuralları manuel kopyalayarak Firebase Console\'a yapıştırın.',
        };
      }
    } catch (e) {
      debugPrint('⚠️ [FIREBASE RULES ERROR]: $e');
      return {
        'success': false,
        'message': 'Hata: $e. Kuralları manuel kopyalayabilirsiniz.',
      };
    }
  }

  /// Generates the standard QR payload for sharing the family network with other devices
  static String generateNetworkQrPayload(String activeRtdbUrl) {
    final cleanUrl = cleanRtdbUrl(activeRtdbUrl);
    return '$qrPrefix${Uri.encodeComponent(cleanUrl)}';
  }

  /// Parses a scanned QR payload. Returns the extracted RTDB URL or null if invalid.
  static String? parseNetworkQrPayload(String scannedPayload) {
    final trimmed = scannedPayload.trim();
    if (trimmed.startsWith(qrPrefix)) {
      final encodedUrl = trimmed.substring(qrPrefix.length);
      final decodedUrl = Uri.decodeComponent(encodedUrl);
      return cleanRtdbUrl(decodedUrl);
    } else if (trimmed.contains('firebaseio.com') ||
        trimmed.contains('firebasedatabase.app')) {
      return cleanRtdbUrl(trimmed);
    }
    return null;
  }
}
