import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import '../firebase_options.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }
  } catch (_) {}

  debugPrint('🔥 [FCM BACKGROUND MSG] Payload: ${message.data}');
  final data = message.data;
  final type = data['type'] ?? '';

  if (type == 'incoming_call') {
    final callerName = data['callerName'] ?? 'Bilinmeyen Arayan';
    final callId = data['callId'] ?? 'call_${DateTime.now().millisecondsSinceEpoch}';
    final isVideo = data['callType'] == 'video';
    final callerId = data['callerId'] ?? '';

    await NotificationService().showNativeIncomingCallUI(
      callId: callId,
      callerName: callerName,
      isVideo: isVideo,
      handle: callerId,
    );
  } else if (type == 'new_message') {
    final senderName = data['senderName'] ?? 'Yeni Mesaj';
    final messageText = data['text'] ?? 'Bir mesaj aldınız';
    await NotificationService().showMessageNotification(
      senderName: senderName,
      messageText: messageText,
    );
  } else if (type == 'motion_alert') {
    final cameraName = data['cameraName'] ?? 'Güvenlik Kamerası';
    await NotificationService().showCameraMotionNotification(
      cameraName: cameraName,
    );
  } else if (type == 'end_call' || type == 'cancel_call') {
    await NotificationService().stopIncomingCallUI();
  }
}

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  String? currentFcmToken;
  bool _isInitialized = false;
  Function(String callId)? onCallkitAccept;
  Function(String callId)? onCallkitDecline;
  Function(String callId)? onCallkitEnded;

  Future<void> init(String myDeviceId) async {
    if (_isInitialized) return;
    _isInitialized = true;

    // 1. Initialize Local Notifications Plugin
    const androidInitSettings = AndroidInitializationSettings('@drawable/ic_stat_omega');
    const darwinInitSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidInitSettings,
      iOS: darwinInitSettings,
      macOS: darwinInitSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) {
        debugPrint('🔔 [NOTIFICATION CLICK] Action: ${response.actionId}, Payload: ${response.payload}');
      },
    );

    // 2. High Priority Channels for Android
    if (!kIsWeb) {
      const callChannel = AndroidNotificationChannel(
        'omega_incoming_calls',
        'Gelen Aramalar',
        description: 'OMEGA yüksek öncelikli arama bildirim kanalı',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

      const msgChannel = AndroidNotificationChannel(
        'omega_messages',
        'Mesajlar',
        description: 'OMEGA mesaj bildirimleri',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

      const cameraChannel = AndroidNotificationChannel(
        'omega_camera_alerts',
        'Kamera Hareket İkazları',
        description: 'OMEGA güvenlik kamerası hareket algılama bildirimleri',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(callChannel);
      await androidPlugin?.createNotificationChannel(msgChannel);
      await androidPlugin?.createNotificationChannel(cameraChannel);
    }

    // 3. FCM Setup
    try {
      if (!kIsWeb && Firebase.apps.isNotEmpty) {
        FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

        final messaging = FirebaseMessaging.instance;
        final settings = await messaging.requestPermission(
          alert: true,
          badge: true,
          sound: true,
          provisional: false,
          announcement: true,
          criticalAlert: true,
        );

        debugPrint('🔥 [FCM PERMISSION] Status: ${settings.authorizationStatus}');

        // On iOS, check APNs Token before fetching FCM Token
        if (defaultTargetPlatform == TargetPlatform.iOS) {
          try {
            String? apnsToken = await messaging.getAPNSToken();
            if (apnsToken == null) {
              await Future.delayed(const Duration(milliseconds: 1500));
              apnsToken = await messaging.getAPNSToken();
            }
            debugPrint('🍎 [APNS TOKEN READY]: $apnsToken');
          } catch (e) {
            debugPrint('🍎 [APNS TOKEN CHECK WARN]: $e');
          }
        }

        currentFcmToken = await messaging.getToken();
        if (currentFcmToken != null) {
          debugPrint('🔥 [FCM TOKEN] $currentFcmToken');
          await _saveFcmTokenToDatabase(myDeviceId, currentFcmToken!);
        }

        messaging.onTokenRefresh.listen((newToken) async {
          currentFcmToken = newToken;
          await _saveFcmTokenToDatabase(myDeviceId, newToken);
        });

        // Handle Foreground Messages
        FirebaseMessaging.onMessage.listen((RemoteMessage message) {
          debugPrint('🔥 [FCM FOREGROUND MSG] Payload: ${message.data}');
          final data = message.data;
          final type = data['type'] ?? '';
          if (type == 'incoming_call') {
            showNativeIncomingCallUI(
              callId: data['callId'] ?? 'call_${DateTime.now().millisecondsSinceEpoch}',
              callerName: data['callerName'] ?? 'Bilinmeyen Arayan',
              isVideo: data['callType'] == 'video',
              handle: data['callerId'] ?? '',
            );
          } else if (type == 'new_message') {
            showMessageNotification(
              senderName: data['senderName'] ?? 'Yeni Mesaj',
              messageText: data['text'] ?? 'Bir mesaj aldınız',
            );
          } else if (type == 'motion_alert') {
            showCameraMotionNotification(
              cameraName: data['cameraName'] ?? 'Güvenlik Kamerası',
            );
          } else if (type == 'end_call' || type == 'cancel_call') {
            stopIncomingCallUI();
          }
        });
      }
    } catch (e) {
      debugPrint('⚠️ [NOTIFICATION INIT WARN]: $e');
    }

    // 4. CallKit Listeners (Android and iOS only)
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
      try {
        FlutterCallkitIncoming.onEvent.listen(
          (CallEvent? event) {
            if (event == null) return;
            final callId = (event.body is Map && event.body['id'] != null)
                ? event.body['id'].toString()
                : '';

            switch (event.event) {
              case Event.actionCallAccept:
                debugPrint('📞 [CALLKIT ACCEPT] Accepted call $callId');
                onCallkitAccept?.call(callId);
                break;
              case Event.actionCallDecline:
                debugPrint('📞 [CALLKIT DECLINE] Declined call $callId');
                onCallkitDecline?.call(callId);
                break;
              case Event.actionCallEnded:
                debugPrint('📞 [CALLKIT ENDED] Ended call $callId');
                onCallkitEnded?.call(callId);
                break;
              case Event.actionCallTimeout:
                debugPrint('📞 [CALLKIT TIMEOUT] Timeout call $callId');
                onCallkitEnded?.call(callId);
                break;
              default:
                break;
            }
          },
          onError: (e) {
            debugPrint('ℹ️ [CALLKIT LISTEN WARN]: $e');
          },
        );
      } catch (e) {
        debugPrint('ℹ️ [CALLKIT LISTEN EXCEPTION]: $e');
      }
    }
  }

  Future<void> _saveFcmTokenToDatabase(String deviceId, String token) async {
    try {
      final pin = deviceId.split('_').last;
      final targets = <String>{deviceId, pin, 'omega_tablet_$pin', 'omega_parent_$pin'};
      for (final target in targets) {
        final url = Uri.parse('${DefaultFirebaseOptions.rtdbUrl}/fcmTokens/$target.json');
        await http.put(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({'fcmToken': token, 'updatedAt': DateTime.now().toIso8601String()}),
        );
      }
    } catch (e) {
      debugPrint('⚠️ [FCM TOKEN SAVE ERROR]: $e');
    }
  }

  Future<String?> fetchTargetFcmToken(String targetDeviceId) async {
    try {
      final pin = targetDeviceId.split('_').last;
      final targets = <String>{targetDeviceId, 'omega_tablet_$pin', 'omega_parent_$pin', pin};
      for (final target in targets) {
        final url = Uri.parse('${DefaultFirebaseOptions.rtdbUrl}/fcmTokens/$target.json');
        final res = await http.get(url);
        if (res.statusCode == 200 && res.body != 'null') {
          final data = jsonDecode(res.body);
          if (data is Map && data['fcmToken'] != null) {
            return data['fcmToken'] as String;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  // --- Push Notification Dispatchers (Direct FCM + RTDB Signal) ---

  /// Dispatches a high-priority push notification for an incoming call to wake up a backgrounded/closed phone
  Future<void> sendCallPushNotification({
    required String targetDeviceId,
    required String callId,
    required String callerName,
    required String callerId,
    required bool isVideo,
  }) async {
    try {
      final token = await fetchTargetFcmToken(targetDeviceId);
      if (token == null || token.isEmpty) {
        debugPrint('⚠️ [PUSH DISPATCH] No FCM token found for $targetDeviceId');
        return;
      }

      debugPrint('🚀 [PUSH DISPATCH] Sending incoming_call push to $targetDeviceId (Token: ${token.substring(0, 10)}...)');

      final payload = {
        'to': token,
        'priority': 'high',
        'content_available': true,
        'notification': {
          'title': 'Gelen ${isVideo ? 'Görüntülü' : 'Sesli'} Arama',
          'body': '$callerName sizi arıyor...',
          'sound': 'default',
          'channel_id': 'omega_incoming_calls',
          'android_channel_id': 'omega_incoming_calls',
        },
        'data': {
          'type': 'incoming_call',
          'callId': callId,
          'callerName': callerName,
          'callerId': callerId,
          'callType': isVideo ? 'video' : 'audio',
          'click_action': 'FLUTTER_NOTIFICATION_CLICK',
        },
      };

      // 1. Direct FCM Legacy API Call
      try {
        final fcmUrl = Uri.parse('https://fcm.googleapis.com/fcm/send');
        await http.post(
          fcmUrl,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'key=AIzaSyB_G0rADbyWby2BV9o4J8VFMMl_yh90teA',
          },
          body: jsonEncode(payload),
        );
      } catch (_) {}

      // 2. Write to RTDB Push Queue (Triggers Cloud Functions or WebSocket listeners)
      try {
        final queueUrl = Uri.parse('${DefaultFirebaseOptions.rtdbUrl}/fcm_queue.json');
        await http.post(
          queueUrl,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        );
      } catch (_) {}
    } catch (e) {
      debugPrint('⚠️ [PUSH SEND ERROR]: $e');
    }
  }

  /// Dispatches an instant push notification for chat messages
  Future<void> sendMessagePushNotification({
    required String targetDeviceId,
    required String senderName,
    required String text,
    required String senderId,
  }) async {
    try {
      final token = await fetchTargetFcmToken(targetDeviceId);
      if (token == null || token.isEmpty) return;

      final payload = {
        'to': token,
        'priority': 'high',
        'content_available': true,
        'notification': {
          'title': senderName,
          'body': text,
          'sound': 'default',
          'channel_id': 'omega_messages',
          'android_channel_id': 'omega_messages',
        },
        'data': {
          'type': 'new_message',
          'senderName': senderName,
          'text': text,
          'senderId': senderId,
          'click_action': 'FLUTTER_NOTIFICATION_CLICK',
        },
      };

      try {
        await http.post(
          Uri.parse('https://fcm.googleapis.com/fcm/send'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'key=AIzaSyB_G0rADbyWby2BV9o4J8VFMMl_yh90teA',
          },
          body: jsonEncode(payload),
        );
      } catch (_) {}
    } catch (e) {
      debugPrint('⚠️ [MSG PUSH ERROR]: $e');
    }
  }

  /// Dispatches a high-priority push notification for security camera motion alerts
  Future<void> sendCameraMotionPushNotification({
    required String targetDeviceId,
    required String cameraName,
  }) async {
    try {
      final token = await fetchTargetFcmToken(targetDeviceId);
      if (token == null || token.isEmpty) return;

      final payload = {
        'to': token,
        'priority': 'high',
        'content_available': true,
        'notification': {
          'title': '🚨 HAREKET ALGILANDI',
          'body': '"$cameraName" kamerasında hareket tespit edildi!',
          'sound': 'default',
          'channel_id': 'omega_camera_alerts',
          'android_channel_id': 'omega_camera_alerts',
        },
        'data': {
          'type': 'motion_alert',
          'cameraName': cameraName,
          'click_action': 'FLUTTER_NOTIFICATION_CLICK',
        },
      };

      try {
        await http.post(
          Uri.parse('https://fcm.googleapis.com/fcm/send'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'key=AIzaSyB_G0rADbyWby2BV9o4J8VFMMl_yh90teA',
          },
          body: jsonEncode(payload),
        );
      } catch (_) {}
    } catch (e) {
      debugPrint('⚠️ [CAMERA PUSH ERROR]: $e');
    }
  }

  Future<void> showNativeIncomingCallUI({
    required String callId,
    required String callerName,
    required bool isVideo,
    required String handle,
    String? avatarUrl,
  }) async {
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
      try {
        final params = CallKitParams(
          id: callId,
          nameCaller: callerName,
          appName: 'Omega',
          avatar: avatarUrl ?? 'https://i.pravatar.cc/100',
          handle: handle,
          type: isVideo ? 1 : 0,
          duration: 30000,
          textAccept: 'Cevapla',
          textDecline: 'Reddet',
          extra: <String, dynamic>{'callId': callId, 'callerName': callerName},
          android: const AndroidParams(
            isCustomNotification: true,
            isShowLogo: true,
            ringtonePath: 'system_ringtone_default',
            backgroundColor: '#384353',
            actionColor: '#4CAF50',
            textColor: '#ffffff',
          ),
          ios: const IOSParams(
            iconName: 'CallKitIcon',
            handleType: 'generic',
            supportsVideo: true,
            maximumCallGroups: 1,
            maximumCallsPerCallGroup: 1,
            audioSessionMode: 'default',
            audioSessionActive: true,
            audioSessionPreferredSampleRate: 44100.0,
            audioSessionPreferredIOBufferDuration: 0.005,
            supportsDTMF: true,
            supportsHolding: true,
            supportsGrouping: false,
            supportsUngrouping: false,
            ringtonePath: 'system_ringtone_default',
          ),
        );

        await FlutterCallkitIncoming.showCallkitIncoming(params);
      } catch (e) {
        debugPrint('⚠️ [CALLKIT WARN]: $e');
        await _showLocalNotificationFallback(callerName: callerName, isVideo: isVideo);
      }
    } else {
      await _showLocalNotificationFallback(callerName: callerName, isVideo: isVideo);
    }
  }

  Future<void> _showLocalNotificationFallback({
    required String callerName,
    required bool isVideo,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'omega_incoming_calls',
      'Gelen Aramalar',
      channelDescription: 'OMEGA yüksek öncelikli arama bildirim kanalı',
      importance: Importance.max,
      priority: Priority.max,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.call,
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
    );

    await _localNotifications.show(
      888,
      'Gelen ${isVideo ? 'Görüntülü' : 'Sesli'} Arama',
      '$callerName sizi arıyor...',
      notificationDetails,
    );
  }

  /// Show a local notification for incoming chat message
  Future<void> showMessageNotification({
    required String senderName,
    required String messageText,
    int? notificationId,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'omega_messages',
      'Mesajlar',
      channelDescription: 'OMEGA mesaj bildirimleri',
      importance: Importance.max,
      priority: Priority.max,
      showWhen: true,
      onlyAlertOnce: false,
      icon: '@drawable/ic_stat_omega',
      largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      color: Color(0xFF00E5FF),
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: true,
        interruptionLevel: InterruptionLevel.active,
        threadIdentifier: 'omega_chat_thread',
      ),
      macOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: true,
        interruptionLevel: InterruptionLevel.active,
        threadIdentifier: 'omega_chat_thread',
      ),
    );

    final id = notificationId ?? (DateTime.now().microsecondsSinceEpoch % 2147483647);
    await _localNotifications.show(
      id,
      senderName,
      messageText,
      notificationDetails,
    );
  }

  /// Show a local notification for a missed call
  Future<void> showMissedCallNotification({
    required String callerName,
    required bool isVideo,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'omega_missed_calls',
      'Cevapsız Aramalar',
      channelDescription: 'OMEGA cevapsız arama bildirimleri',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_stat_omega',
      largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      color: Color(0xFFFF5252),
    );

    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: true,
      ),
      macOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: true,
      ),
    );

    await _localNotifications.show(
      889,
      'Cevapsız ${isVideo ? 'Görüntülü' : 'Sesli'} Arama',
      '$callerName aradı',
      notificationDetails,
    );
  }

  /// Show a local native notification for security camera motion detection
  Future<void> showCameraMotionNotification({
    required String cameraName,
    String? snapshotBase64,
    int? notificationId,
  }) async {
    String? imagePath;
    if (!kIsWeb && snapshotBase64 != null && snapshotBase64.isNotEmpty) {
      try {
        final tempDir = await getTemporaryDirectory();
        final file = File('${tempDir.path}/motion_snap_${DateTime.now().millisecondsSinceEpoch}.jpg');
        final cleanBase64 = snapshotBase64.contains(',') ? snapshotBase64.split(',').last : snapshotBase64;
        final bytes = base64Decode(cleanBase64);
        await file.writeAsBytes(bytes);
        imagePath = file.path;
      } catch (e) {
        debugPrint('⚠️ [NOTIF SNAPSHOT DECODE ERROR]: $e');
      }
    }

    final androidDetails = AndroidNotificationDetails(
      'omega_camera_alerts',
      'Kamera Hareket İkazları',
      channelDescription: 'OMEGA güvenlik kamerası hareket algılama bildirimleri',
      importance: Importance.max,
      priority: Priority.max,
      showWhen: true,
      onlyAlertOnce: false,
      icon: '@drawable/ic_stat_omega',
      largeIcon: const DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
      color: const Color(0xFFFF9100),
      styleInformation: imagePath != null
          ? BigPictureStyleInformation(
              FilePathAndroidBitmap(imagePath),
              contentTitle: '🚨 HAREKET ALGILANDI',
              summaryText: '"$cameraName" güvenlik kamerasında hareket tespit edildi!',
            )
          : null,
    );

    final notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
        attachments: imagePath != null ? [DarwinNotificationAttachment(imagePath)] : null,
      ),
      macOS: DarwinNotificationDetails(
        presentAlert: true,
        presentSound: true,
        presentBadge: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
        attachments: imagePath != null ? [DarwinNotificationAttachment(imagePath)] : null,
      ),
    );

    final id = notificationId ?? (DateTime.now().microsecondsSinceEpoch % 2147483647);
    await _localNotifications.show(
      id,
      '🚨 HAREKET ALGILANDI',
      '"$cameraName" güvenlik kamerasında hareket tespit edildi!',
      notificationDetails,
    );
  }

  Future<void> stopIncomingCallUI() async {
    if (!kIsWeb && (defaultTargetPlatform == TargetPlatform.android || defaultTargetPlatform == TargetPlatform.iOS)) {
      try {
        await FlutterCallkitIncoming.endAllCalls();
      } catch (_) {}
    }
    try {
      await _localNotifications.cancel(888);
    } catch (_) {}
  }
}
