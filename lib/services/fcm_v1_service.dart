import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:http/http.dart' as http;
import 'package:googleapis_auth/auth_io.dart';
import '../firebase_options.dart';

class FcmV1Service {
  static final FcmV1Service _instance = FcmV1Service._internal();
  factory FcmV1Service() => _instance;
  FcmV1Service._internal();

  static const String _fcmEndpoint =
      'https://fcm.googleapis.com/v1/projects/omega-call/messages:send';
  static const List<String> _scopes = [
    'https://www.googleapis.com/auth/firebase.messaging',
  ];

  AuthClient? _authClient;
  DateTime? _tokenExpiry;
  Map<String, dynamic>? _serviceAccountMap;

  void configureServiceAccount(Map<String, dynamic> serviceAccountJson) {
    _serviceAccountMap = serviceAccountJson;
    _authClient = null;
    _tokenExpiry = null;
  }

  Future<AuthClient?> _getAuthClient() async {
    if (_authClient != null &&
        _tokenExpiry != null &&
        DateTime.now().isBefore(_tokenExpiry!.subtract(const Duration(minutes: 5)))) {
      return _authClient;
    }

    if (_serviceAccountMap == null) {
      await _tryFetchServiceAccountConfig();
    }

    if (_serviceAccountMap == null) {
      debugPrint('⚠️ [FCM v1] No Service Account credentials configured');
      return null;
    }

    try {
      final credentials = ServiceAccountCredentials.fromJson(_serviceAccountMap!);
      _authClient = await clientViaServiceAccount(credentials, _scopes);
      _tokenExpiry = DateTime.now().add(const Duration(hours: 1));
      debugPrint('🔐 [FCM v1] OAuth2 token generated successfully for omega-call');
      return _authClient;
    } catch (e) {
      debugPrint('❌ [FCM v1 AUTH ERROR]: $e');
      return null;
    }
  }

  Future<void> _tryFetchServiceAccountConfig() async {
    // 1. Try local assets bundle
    try {
      final assetStr = await rootBundle.loadString('assets/service_account.json');
      if (assetStr.isNotEmpty) {
        final data = jsonDecode(assetStr);
        if (data is Map && data['private_key'] != null) {
          _serviceAccountMap = Map<String, dynamic>.from(data);
          debugPrint('🔐 [FCM v1] Service account loaded directly from assets bundle');
          return;
        }
      }
    } catch (_) {}

    // 2. Fallback to default RTDB config node
    try {
      final url = Uri.parse('${DefaultFirebaseOptions.rtdbUrl}/_fcm_config.json');
      final res = await http.get(url);
      if (res.statusCode == 200 && res.body != 'null') {
        final data = jsonDecode(res.body);
        if (data is Map && data['private_key'] != null) {
          _serviceAccountMap = Map<String, dynamic>.from(data);
          debugPrint('🔐 [FCM v1] Service account loaded from secure config node');
        }
      }
    } catch (_) {}
  }

  /// Sends a high-priority FCM v1 push notification for incoming calls
  Future<bool> sendCallV1Push({
    required String targetFcmToken,
    required String callId,
    required String callerName,
    required String callerId,
    required bool isVideo,
  }) async {
    final client = await _getAuthClient();
    if (client == null) return false;

    final callTypeStr = isVideo ? 'video' : 'audio';
    final title = 'Gelen ${isVideo ? 'Görüntülü' : 'Sesli'} Arama';
    final body = '$callerName sizi arıyor...';

    final v1Payload = {
      'message': {
        'token': targetFcmToken,
        'notification': {
          'title': title,
          'body': body,
        },
        'android': {
          'priority': 'HIGH',
          'ttl': '60s',
          'notification': {
            'channel_id': 'omega_incoming_calls',
            'sound': 'default',
            'default_sound': true,
            'default_vibrate_timings': true,
            'notification_priority': 'PRIORITY_MAX',
            'visibility': 'PUBLIC',
            'click_action': 'FLUTTER_NOTIFICATION_CLICK',
          },
          'data': {
            'type': 'incoming_call',
            'callId': callId,
            'callerName': callerName,
            'callerId': callerId,
            'callType': callTypeStr,
            'click_action': 'FLUTTER_NOTIFICATION_CLICK',
          },
        },
        'apns': {
          'headers': {
            'apns-priority': '10',
            'apns-push-type': 'alert',
            'apns-expiration': '${(DateTime.now().millisecondsSinceEpoch ~/ 1000) + 60}',
          },
          'payload': {
            'aps': {
              'alert': {
                'title': title,
                'body': body,
              },
              'sound': 'default',
              'badge': 1,
              'content-available': 1,
              'interruption-level': 'time-sensitive',
            },
            'type': 'incoming_call',
            'callId': callId,
            'callerName': callerName,
            'callerId': callerId,
            'callType': callTypeStr,
          },
        },
        'data': {
          'type': 'incoming_call',
          'callId': callId,
          'callerName': callerName,
          'callerId': callerId,
          'callType': callTypeStr,
        },
      },
    };

    try {
      final response = await client.post(
        Uri.parse(_fcmEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(v1Payload),
      );

      if (response.statusCode == 200) {
        debugPrint('🚀 [FCM v1 CALL PUSH SENT SUCCESS]: ${response.body}');
        return true;
      } else {
        debugPrint('⚠️ [FCM v1 CALL PUSH FAILED (${response.statusCode})]: ${response.body}');
        return false;
      }
    } catch (e) {
      debugPrint('❌ [FCM v1 CALL PUSH EXCEPTION]: $e');
      return false;
    }
  }

  /// Sends a high-priority FCM v1 push notification for chat messages
  Future<bool> sendMessageV1Push({
    required String targetFcmToken,
    required String senderName,
    required String text,
    required String senderId,
  }) async {
    final client = await _getAuthClient();
    if (client == null) return false;

    final v1Payload = {
      'message': {
        'token': targetFcmToken,
        'notification': {
          'title': senderName,
          'body': text,
        },
        'android': {
          'priority': 'HIGH',
          'notification': {
            'channel_id': 'omega_messages',
            'sound': 'default',
            'click_action': 'FLUTTER_NOTIFICATION_CLICK',
          },
          'data': {
            'type': 'new_message',
            'senderName': senderName,
            'text': text,
            'senderId': senderId,
            'click_action': 'FLUTTER_NOTIFICATION_CLICK',
          },
        },
        'apns': {
          'headers': {
            'apns-priority': '10',
          },
          'payload': {
            'aps': {
              'alert': {
                'title': senderName,
                'body': text,
              },
              'sound': 'default',
              'badge': 1,
              'content-available': 1,
            },
            'type': 'new_message',
            'senderName': senderName,
            'text': text,
            'senderId': senderId,
          },
        },
        'data': {
          'type': 'new_message',
          'senderName': senderName,
          'text': text,
          'senderId': senderId,
        },
      },
    };

    try {
      final response = await client.post(
        Uri.parse(_fcmEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(v1Payload),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ [FCM v1 MSG PUSH EXCEPTION]: $e');
      return false;
    }
  }

  /// Sends a high-priority FCM v1 push notification for security camera motion alerts
  Future<bool> sendMotionAlertV1Push({
    required String targetFcmToken,
    required String cameraName,
  }) async {
    final client = await _getAuthClient();
    if (client == null) return false;

    final title = '🚨 HAREKET ALGILANDI';
    final body = '"$cameraName" güvenlik kamerasında hareket tespit edildi!';

    final v1Payload = {
      'message': {
        'token': targetFcmToken,
        'notification': {
          'title': title,
          'body': body,
        },
        'android': {
          'priority': 'HIGH',
          'notification': {
            'channel_id': 'omega_camera_alerts',
            'sound': 'default',
            'click_action': 'FLUTTER_NOTIFICATION_CLICK',
          },
          'data': {
            'type': 'motion_alert',
            'cameraName': cameraName,
            'click_action': 'FLUTTER_NOTIFICATION_CLICK',
          },
        },
        'apns': {
          'headers': {
            'apns-priority': '10',
          },
          'payload': {
            'aps': {
              'alert': {
                'title': title,
                'body': body,
              },
              'sound': 'default',
              'badge': 1,
              'content-available': 1,
              'interruption-level': 'time-sensitive',
            },
            'type': 'motion_alert',
            'cameraName': cameraName,
          },
        },
        'data': {
          'type': 'motion_alert',
          'cameraName': cameraName,
        },
      },
    };

    try {
      final response = await client.post(
        Uri.parse(_fcmEndpoint),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(v1Payload),
      );

      return response.statusCode == 200;
    } catch (e) {
      debugPrint('❌ [FCM v1 MOTION PUSH EXCEPTION]: $e');
      return false;
    }
  }
}
