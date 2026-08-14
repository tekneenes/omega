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
  if (data['type'] == 'incoming_call') {
    final callerName = data['callerName'] ?? 'Bilinmeyen Arayan';
    final callId = data['callId'] ?? 'call_${DateTime.now().millisecondsSinceEpoch}';
    final isVideo = data['callType'] == 'video';

    await NotificationService().showNativeIncomingCallUI(
      callId: callId,
      callerName: callerName,
      isVideo: isVideo,
      handle: data['callerId'] ?? '',
    );
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

    // 2. High Priority Call Channel for Android
    if (!kIsWeb) {
      const androidChannel = AndroidNotificationChannel(
        'omega_incoming_calls',
        'Gelen Aramalar',
        description: 'OMEGA yüksek öncelikli arama bildirim kanalı',
        importance: Importance.max,
        playSound: true,
        enableVibration: true,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(androidChannel);
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
        );

        debugPrint('🔥 [FCM PERMISSION] Status: ${settings.authorizationStatus}');

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
          if (data['type'] == 'incoming_call') {
            showNativeIncomingCallUI(
              callId: data['callId'] ?? 'call_${DateTime.now().millisecondsSinceEpoch}',
              callerName: data['callerName'] ?? 'Bilinmeyen Arayan',
              isVideo: data['callType'] == 'video',
              handle: data['callerId'] ?? '',
            );
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
