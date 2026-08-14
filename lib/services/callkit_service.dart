import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import '../models/call_session.dart';

class CallKitService {
  static Future<void> showIncomingCall(CallSession session) async {
    if (kIsWeb) return; // CallKit is not supported on web
    try {
      final params = CallKitParams(
        id: session.callId,
        nameCaller: session.callerName,
        appName: 'Omega',
        avatar: 'https://i.imgur.com/8Km9tLL.png',
        handle: session.type == CallType.video
            ? 'Görüntülü Arama'
            : 'Sesli Arama',
        type: session.type == CallType.video ? 1 : 0,
        duration: 30000,
        textAccept: 'Cevapla',
        textDecline: 'Reddet',
        extra: <String, dynamic>{'callId': session.callId},
      );
      await FlutterCallkitIncoming.showCallkitIncoming(params);
    } catch (_) {}
  }

  static void listenCallEvents({
    required Function(String callId) onAccept,
    required Function(String callId) onDecline,
  }) {
    if (kIsWeb) return;
    try {
      FlutterCallkitIncoming.onEvent.listen((CallEvent? event) {
        switch (event?.event) {
          case Event.actionCallAccept:
            final callId = event?.body['id'] as String?;
            if (callId != null) onAccept(callId);
            break;
          case Event.actionCallDecline:
            final callId = event?.body['id'] as String?;
            if (callId != null) onDecline(callId);
            break;
          default:
            break;
        }
      });
    } catch (_) {}
  }

  static Future<void> endAllCalls() async {
    if (kIsWeb) return;
    try {
      await FlutterCallkitIncoming.endAllCalls();
    } catch (_) {}
  }
}
