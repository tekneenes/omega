import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:http/http.dart' as http;
import '../models/call_session.dart';
import '../models/chat_message.dart';
import '../firebase_options.dart';
import 'notification_service.dart';
import 'firebase_config_service.dart';

typedef OnIncomingCallCallback = void Function(CallSession session);
typedef OnCallAnswerCallback = void Function(Map<String, dynamic> sdpAnswer);
typedef OnCallRejectedCallback = void Function(String callId);
typedef OnCallEndedCallback = void Function(String callId);
typedef OnIceCandidateCallback = void Function(Map<String, dynamic> candidate);
typedef OnChatMessageCallback = void Function(ChatMessage message);
typedef OnMessageStatusUpdatedCallback = void Function(String messageId, String status);
typedef OnTypingStatusCallback = void Function(String senderId, bool isTyping, int timestampMs);

class SignalingService {
  static final SignalingService _instance = SignalingService._internal();
  factory SignalingService() => _instance;
  SignalingService._internal();

  DatabaseReference? _dbRef;
  String _activeRtdbUrl = DefaultFirebaseOptions.rtdbUrl;
  String get activeRtdbUrl => _activeRtdbUrl;

  final Set<String> _extraListenTargets = {};
  final Set<String> _processedCallIds = {};
  final Set<String> _processedEndedCallIds = {};
  final Set<String> _processedAnswerCallIds = {};

  void _trimProcessedSets() {
    if (_processedCallIds.length > 50) {
      final excess = _processedCallIds.length - 30;
      _processedCallIds.removeAll(_processedCallIds.take(excess).toList());
    }
    if (_processedEndedCallIds.length > 50) {
      final excess = _processedEndedCallIds.length - 30;
      _processedEndedCallIds.removeAll(_processedEndedCallIds.take(excess).toList());
    }
    if (_processedAnswerCallIds.length > 50) {
      final excess = _processedAnswerCallIds.length - 30;
      _processedAnswerCallIds.removeAll(_processedAnswerCallIds.take(excess).toList());
    }
  }

  OnIncomingCallCallback? onIncomingCall;
  OnCallAnswerCallback? onCallAnswer;
  OnCallRejectedCallback? onCallRejected;
  OnCallEndedCallback? onCallEnded;
  OnIceCandidateCallback? onIceCandidate;
  OnChatMessageCallback? onChatMessageReceived;
  OnChatMessageCallback? onGroupChatMessageReceived;
  OnMessageStatusUpdatedCallback? onMessageStatusUpdated;
  OnTypingStatusCallback? onTypingStatusChanged;

  void addListenTarget(String target) {
    if (target.trim().isNotEmpty) {
      _extraListenTargets.add(target.trim());
    }
  }

  void addListenTargets(Iterable<String> targets) {
    for (final t in targets) {
      addListenTarget(t);
    }
  }

  StreamSubscription? _callSubscription;
  StreamSubscription? _candidateSubscription;
  StreamSubscription? _chatSubscription;
  StreamSubscription? _pairSubscription;
  Timer? _pollingTimer;

  // Multi-channel pairing support
  final Map<String, StreamSubscription> _pairSubscriptions = {};
  final Map<String, Timer> _pairPollingTimers = {};

  Future<void> init(String currentDeviceId) async {
    try {
      // Fetch dynamic active RTDB URL configured by user/QR
      _activeRtdbUrl = await FirebaseConfigService.getActiveRtdbUrl();
      debugPrint('🔥 [FIREBASE RTDB] Initializing with URL: $_activeRtdbUrl');

      // Initialize Firebase Auth (not on Web)
      if (!kIsWeb && Firebase.apps.isNotEmpty) {
        try {
          final authResult = await FirebaseAuth.instance.signInAnonymously();
          debugPrint('🔥 [FIREBASE AUTH] Anonymous Auth UID: ${authResult.user?.uid}');
        } catch (authErr) {
          debugPrint('⚠️ [FIREBASE AUTH NOTICE] Anonymous auth skipped: $authErr');
        }
      }

      // Initialize RTDB on ALL platforms (including Web)
      if (Firebase.apps.isNotEmpty) {
        try {
          _dbRef = FirebaseDatabase.instanceFor(
            app: Firebase.app(),
            databaseURL: _activeRtdbUrl,
          ).ref();
        } catch (_) {
          _dbRef = FirebaseDatabase.instance.ref();
        }

        debugPrint('🔥 [FIREBASE RTDB] Realtime WebSocket active for $currentDeviceId. REST Polling OFF.');

        _listenForCalls(currentDeviceId);
        _listenForMessages(currentDeviceId);
        _listenForMessageStatus(currentDeviceId);
        _listenForTypingStatus(currentDeviceId);
      } else {
        debugPrint('🌐 [REST ONLY FALLBACK] Enabling REST Polling for $currentDeviceId');
        _startPollingForMessages(currentDeviceId);
        _startPollingForMessageStatus(currentDeviceId);
        _startPollingForTypingStatus(currentDeviceId);
        _startPollingForCalls(currentDeviceId);
      }
    } catch (e, stack) {
      debugPrint('⚠️ [FIREBASE INIT NOTICE]: $e\n$stack');
      _startPollingForMessages(currentDeviceId);
      _startPollingForMessageStatus(currentDeviceId);
      _startPollingForTypingStatus(currentDeviceId);
      _startPollingForCalls(currentDeviceId);
    }
  }

  // --- Realtime Mutual Pairing Handshake (Dual REST + SDK) ---

  Future<void> registerTabletPair(
      String pinCode, String tabletId, String tabletName) async {
    debugPrint('🔥 [PAIRING] Registering tablet pair code: $pinCode ($tabletId)');

    try {
      final url = Uri.parse('$_activeRtdbUrl/pairs/$pinCode.json');
      await http.put(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'tabletId': tabletId,
          'tabletName': tabletName,
          'status': 'waiting',
          'createdAt': DateTime.now().toIso8601String(),
        }),
      );
      debugPrint('🔥 [PAIRING REST SUCCESS] Registered $pinCode via REST API');
    } catch (e) {
      debugPrint('⚠️ [PAIRING REST ERROR]: $e');
    }

    if (_dbRef != null) {
      try {
        await _dbRef!.child('pairs').child(pinCode).set({
          'tabletId': tabletId,
          'tabletName': tabletName,
          'status': 'waiting',
          'createdAt': DateTime.now().toIso8601String(),
        });
      } catch (e) {
        debugPrint('⚠️ [PAIRING SDK ERROR]: $e');
      }
    }
  }

  // Update device profile and pairing info dynamically in Realtime DB
  Future<void> updateDeviceProfileAndPairing({
    required String deviceId,
    required String newName,
    required String roleName,
    required String pairCode,
    String? email,
    String? phoneNumber,
  }) async {
    final payload = {
      'deviceId': deviceId,
      'deviceName': newName,
      'role': roleName,
      'pairCode': pairCode,
      'email': email,
      'phoneNumber': phoneNumber,
      'updatedAt': DateTime.now().toIso8601String(),
    };

    try {
      final url = Uri.parse('$_activeRtdbUrl/devices/$deviceId.json');
      await http.patch(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      final pairUrl = Uri.parse('$_activeRtdbUrl/pairs/$pairCode.json');
      await http.patch(
        pairUrl,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'tabletId': deviceId,
          'tabletName': newName,
          'updatedAt': DateTime.now().toIso8601String(),
        }),
      );
      debugPrint('🔥 [PROFILE UPDATE REST SUCCESS] Updated $deviceId profile & pair node');
    } catch (e) {
      debugPrint('⚠️ [UPDATE PROFILE REST ERROR]: $e');
    }

    if (_dbRef != null) {
      try {
        await _dbRef!.child('devices').child(deviceId).update(payload);
        await _dbRef!.child('pairs').child(pairCode).update({
          'tabletId': deviceId,
          'tabletName': newName,
          'updatedAt': DateTime.now().toIso8601String(),
        });
      } catch (e) {
        debugPrint('⚠️ [UPDATE PROFILE SDK ERROR]: $e');
      }
    }
  }

  /// Upload profile photo as base64 to Firebase RTDB
  Future<void> uploadProfilePhoto(String deviceId, String photoBase64) async {
    try {
      final url = Uri.parse('$_activeRtdbUrl/devices/$deviceId/photoBase64.json');
      await http.put(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(photoBase64),
      );
      debugPrint('🔥 [PHOTO UPLOAD] Uploaded profile photo for $deviceId (${photoBase64.length} chars)');
    } catch (e) {
      debugPrint('⚠️ [PHOTO UPLOAD ERROR]: $e');
    }
  }

  /// Remove profile photo from Firebase RTDB (privacy: sharePhoto = false)
  Future<void> removeProfilePhoto(String deviceId) async {
    try {
      final url = Uri.parse('$_activeRtdbUrl/devices/$deviceId/photoBase64.json');
      await http.delete(url);
      debugPrint('🔥 [PHOTO REMOVE] Removed profile photo for $deviceId');
    } catch (e) {
      debugPrint('⚠️ [PHOTO REMOVE ERROR]: $e');
    }
  }

  /// Fetch profile photo (base64) of a remote device from Firebase RTDB
  Future<String?> fetchProfilePhoto(String deviceId) async {
    try {
      final url = Uri.parse('$_activeRtdbUrl/devices/$deviceId/photoBase64.json');
      final res = await http.get(url);
      if (res.statusCode == 200 && res.body != 'null' && res.body.isNotEmpty) {
        final decoded = jsonDecode(res.body);
        if (decoded is String && decoded.isNotEmpty) {
          debugPrint('🔥 [PHOTO FETCH] Fetched profile photo for $deviceId (${decoded.length} chars)');
          return decoded;
        }
      }
    } catch (e) {
      debugPrint('⚠️ [PHOTO FETCH ERROR]: $e');
    }
    return null;
  }

  /// Real-time listener for profile photo updates of a paired device
  StreamSubscription? listenToDevicePhotoUpdates(
    String deviceId,
    Function(String? newPhotoBase64) onPhotoUpdated,
  ) {
    if (_dbRef == null) return null;
    return _dbRef!
        .child('devices')
        .child(deviceId)
        .child('photoBase64')
        .onValue
        .listen((event) {
      if (event.snapshot.exists && event.snapshot.value != null) {
        final val = event.snapshot.value as String?;
        onPhotoUpdated(val);
      } else {
        onPhotoUpdated(null);
      }
    }, onError: (e) {
      debugPrint('⚠️ [PHOTO LISTEN ERROR]: $e');
    });
  }

  // WhatsApp-Style Live Target Device Search in Firebase
  Future<Map<String, dynamic>?> lookupTargetDevice(String input) async {
    final cleanInput = input.trim().replaceAll(' ', '');
    if (cleanInput.isEmpty) return null;

    try {
      final pairUrl =
          Uri.parse('$_activeRtdbUrl/pairs/$cleanInput.json');
      final res = await http.get(pairUrl);
      if (res.statusCode == 200 && res.body != 'null') {
        final data = jsonDecode(res.body);
        if (data is Map) {
          return {
            'found': true,
            'deviceName':
                data['tabletName'] ?? data['parentName'] ?? 'OMEGA Cihazı',
            'id': data['tabletId'] ?? data['parentId'] ?? cleanInput,
          };
        }
      }

      final devUrl =
          Uri.parse('$_activeRtdbUrl/devices.json');
      final devRes = await http.get(devUrl);
      if (devRes.statusCode == 200 && devRes.body != 'null') {
        final Map<String, dynamic> allDevs = jsonDecode(devRes.body);
        for (final entry in allDevs.entries) {
          final dev = entry.value;
          if (dev is Map) {
            if (dev['pairCode'] == cleanInput ||
                dev['phoneNumber'] == cleanInput ||
                dev['email'] == cleanInput) {
              return {
                'found': true,
                'deviceName': dev['deviceName'] ?? 'OMEGA Cihazı',
                'id': entry.key,
              };
            }
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ [LOOKUP ERROR]: $e');
    }
    return null;
  }

  // Parent submits code + custom name e.g. "Ömer'in Tableti"
  Future<void> sendPairRequest(
      String pinCode, String parentId, String parentCustomName, {String? senderPairCode}) async {
    debugPrint('🔥 [PAIR REQUEST] Parent sending pair request for $pinCode ($parentCustomName)');

    final senderCode = senderPairCode ?? parentId.split('_').last;

    final body = jsonEncode({
      'parentId': parentId,
      'parentName': parentCustomName,
      'parentPairCode': senderCode,
      'status': 'pending_approval',
    });

    try {
      final url = Uri.parse('$_activeRtdbUrl/pairs/$pinCode.json');
      await http.patch(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );
    } catch (e) {
      debugPrint('⚠️ [PAIR REQUEST REST ERROR]: $e');
    }

    if (_dbRef != null) {
      try {
        await _dbRef!.child('pairs').child(pinCode).update({
          'parentId': parentId,
          'parentName': parentCustomName,
          'parentPairCode': senderCode,
          'status': 'pending_approval',
        });
      } catch (_) {}
    }
  }

  // Tablet approves pairing + sets its custom contact name e.g. "Annem"
  // senderRealName = the approving device's actual profile name (e.g. "n")
  Future<void> approvePairing(
      String pinCode, String tabletId, String tabletCustomName, {String? senderRealName}) async {
    debugPrint('🔥 [PAIR APPROVE] Tablet approving pair code $pinCode as $tabletCustomName (realName: $senderRealName)');

    final payload = {
      'tabletId': tabletId,
      'tabletName': tabletCustomName,
      'status': 'paired',
    };
    if (senderRealName != null && senderRealName.trim().isNotEmpty) {
      payload['senderRealName'] = senderRealName;
    }

    final body = jsonEncode(payload);

    try {
      final url = Uri.parse('$_activeRtdbUrl/pairs/$pinCode.json');
      await http.patch(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );
    } catch (e) {
      debugPrint('⚠️ [PAIR APPROVE REST ERROR]: $e');
    }

    if (_dbRef != null) {
      try {
        await _dbRef!.child('pairs').child(pinCode).update(payload);
      } catch (_) {}
    }
  }

  // Send unpair signal to Firebase RTDB for both target channel and sender channel
  Future<void> unpairDevice(
      String targetPairCode, String myDeviceId, String myPairCode,
      {String? targetDeviceId}) async {
    debugPrint('🔥 [UNPAIR DEVICE] Unpairing device code $targetPairCode by $myDeviceId (targetDeviceId: $targetDeviceId)');

    final body = jsonEncode({
      'status': 'unpaired',
      'unpairedBy': myDeviceId,
    });

    // Broadcast to ALL possible pair channels so remote device detects it
    final targets = <String>{targetPairCode, myPairCode};
    
    // Add PIN extracted from target device ID (e.g. omega_parent_424027 → 424027)
    if (targetDeviceId != null && targetDeviceId.isNotEmpty) {
      final targetPin = targetDeviceId.split('_').last;
      if (targetPin.isNotEmpty) targets.add(targetPin);
      targets.add(targetDeviceId);
    }
    
    // Also extract PIN from myDeviceId
    final myPin = myDeviceId.split('_').last;
    if (myPin.isNotEmpty) targets.add(myPin);

    debugPrint('🔥 [UNPAIR TARGETS] Writing unpaired to channels: $targets');

    for (final target in targets) {
      if (target.isEmpty) continue;
      try {
        final url = Uri.parse('$_activeRtdbUrl/pairs/$target.json');
        await http.patch(
          url,
          headers: {'Content-Type': 'application/json'},
          body: body,
        );
      } catch (e) {
        debugPrint('⚠️ [UNPAIR REST ERROR]: $e');
      }

      if (_dbRef != null) {
        try {
          await _dbRef!.child('pairs').child(target).update({
            'status': 'unpaired',
            'unpairedBy': myDeviceId,
          });
        } catch (_) {}
      }
    }
  }

  // Cancel a sent pair request
  Future<void> cancelPairRequest(String targetPairCode, String myDeviceId) async {
    debugPrint('🔥 [CANCEL PAIR REQUEST] Cancelling pair request for $targetPairCode by $myDeviceId');

    final body = jsonEncode({
      'status': 'cancelled',
      'cancelledBy': myDeviceId,
    });

    try {
      final url = Uri.parse('$_activeRtdbUrl/pairs/$targetPairCode.json');
      await http.patch(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );
    } catch (e) {
      debugPrint('⚠️ [CANCEL PAIR REQUEST REST ERROR]: $e');
    }

    if (_dbRef != null) {
      try {
        await _dbRef!.child('pairs').child(targetPairCode).update({
          'status': 'cancelled',
          'cancelledBy': myDeviceId,
        });
      } catch (_) {}
    }
  }

  void listenTabletPairing(
    String pinCode, {
    required Function(Map<String, dynamic> data) onPendingApproval,
    required Function(Map<String, dynamic> data) onPaired,
    Function(Map<String, dynamic> data)? onUnpaired,
    Function(Map<String, dynamic> data)? onCancelled,
  }) {
    debugPrint('🔥 [PAIRING LISTEN] Listening to /pairs/$pinCode...');
    String? lastProcessedStatus;

    void processData(Map<String, dynamic> data) {
      final status = data['status'];
      if (lastProcessedStatus == status) return;
      lastProcessedStatus = status;
      debugPrint('🔥 [PAIRING EVENT STATUS CHANGED on $pinCode]: $status');
      if (status == 'pending_approval') {
        onPendingApproval(data);
      } else if (status == 'paired') {
        onPaired(data);
      } else if (status == 'unpaired' && onUnpaired != null) {
        onUnpaired(data);
      } else if (status == 'cancelled' && onCancelled != null) {
        onCancelled(data);
      }
    }

    // A. SDK WebSocket Listener (per-channel)
    if (_dbRef != null) {
      _pairSubscriptions[pinCode]?.cancel();
      _pairSubscriptions[pinCode] =
          _dbRef!.child('pairs').child(pinCode).onValue.listen((event) {
        if (event.snapshot.value != null) {
          try {
            final data = Map<String, dynamic>.from(event.snapshot.value as Map);
            processData(data);
          } catch (e) {
            debugPrint('⚠️ [PAIRING LISTEN ERROR on $pinCode]: $e');
          }
        }
      });
    }

    // B. REST Polling Failsafe (per-channel)
    _pairPollingTimers[pinCode]?.cancel();
    bool isPaired = false;
    _pairPollingTimers[pinCode] = Timer.periodic(const Duration(milliseconds: 1500), (timer) async {
      // After pairing confirmed, slow down to every 5 seconds (saves bandwidth)
      if (isPaired && timer.tick % 3 != 0) return;
      try {
        final url = Uri.parse('$_activeRtdbUrl/pairs/$pinCode.json');
        final response = await http.get(url);
        if (response.statusCode == 200 && response.body != 'null') {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          processData(data);
          if (data['status'] == 'paired') {
            isPaired = true;
          }
          // Only stop polling on terminal states (unpaired/cancelled)
          if (data['status'] == 'unpaired' || data['status'] == 'cancelled') {
            _pairPollingTimers[pinCode]?.cancel();
            _pairPollingTimers.remove(pinCode);
          }
        }
      } catch (e) {
        debugPrint('⚠️ [PAIRING REST POLL ERROR on $pinCode]: $e');
      }
    });
  }

  Future<Map<String, dynamic>?> claimPairCode(
      String pinCode, String parentId, String parentName) async {
    await sendPairRequest(pinCode, parentId, parentName);
    await approvePairing(pinCode, 'omega_tablet_$pinCode', 'Ev Tableti');
    return {
      'id': 'omega_tablet_$pinCode',
      'deviceName': 'Ev Tableti',
    };
  }

  // --- Calling Signaling (Dual REST + SDK) ---

  Future<void> sendCallOffer(CallSession session) async {
    debugPrint('📞 [WEBRTC OFFER] Sending call to ${session.receiverId}');
    final pin = session.receiverId.split('_').last;
    final targets = <String>{session.receiverId, pin, 'omega_tablet_$pin', 'omega_parent_$pin'};
    final jsonBody = jsonEncode(session.toJson());

    for (final target in targets) {
      // Always try SDK first
      if (_dbRef != null) {
        try {
          await _dbRef!.child('calls').child(target).set(session.toJson());
        } catch (e) {
          debugPrint('⚠️ [CALL OFFER SDK ERROR on $target]: $e');
        }
      }
      // Always also write via REST for maximum reliability
      try {
        final url = Uri.parse('$_activeRtdbUrl/calls/$target.json');
        await http.put(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonBody,
        );
      } catch (e) {
        debugPrint('⚠️ [CALL OFFER REST ERROR on $target]: $e');
      }
    }

    // Trigger FCM High Priority Data Push for target device (if app is killed/backgrounded)
    try {
      await NotificationService().sendCallPushNotification(
        targetDeviceId: session.receiverId,
        callId: session.callId,
        callerName: session.callerName,
        callerId: session.callerId,
        isVideo: session.type == CallType.video,
      );
    } catch (e) {
      debugPrint('⚠️ [FCM CALL PUSH WARN]: $e');
    }
  }

  Future<void> sendCallAnswer(
      String callerId, Map<String, dynamic> sdpAnswer, [String? callId]) async {
    debugPrint('📞 [WEBRTC ANSWER] Sending answer to $callerId (callId: $callId)');

    final callerPin = callerId.split('_').last;
    final answerTargets = <String>{callerId, callerPin, 'omega_tablet_$callerPin', 'omega_parent_$callerPin'};

    final updateData = <String, dynamic>{
      'status': CallStatus.connected.name,
      'sdpAnswer': sdpAnswer,
      'callerId': callerId,
    };
    if (callId != null && callId.isNotEmpty) {
      updateData['callId'] = callId;
    }
    final jsonBody = jsonEncode(updateData);

    for (final target in answerTargets) {
      if (_dbRef != null) {
        try {
          await _dbRef!.child('calls').child(target).update(updateData);
        } catch (e) {
          debugPrint('⚠️ [CALL ANSWER SDK ERROR on $target]: $e');
        }
      }
      try {
        final url = Uri.parse('$_activeRtdbUrl/calls/$target.json');
        await http.patch(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonBody,
        );
      } catch (e) {
        debugPrint('⚠️ [CALL ANSWER REST ERROR on $target]: $e');
      }
    }
  }

  Future<void> sendIceCandidate(
      String targetDeviceId, Map<String, dynamic> candidate) async {
    final pin = targetDeviceId.split('_').last;
    final iceTargets = <String>{targetDeviceId, pin, 'omega_tablet_$pin', 'omega_parent_$pin'};
    final jsonBody = jsonEncode(candidate);

    for (final target in iceTargets) {
      if (_dbRef != null) {
        try {
          await _dbRef!
              .child('candidates')
              .child(target)
              .push()
              .set(candidate);
        } catch (_) {}
      }
      try {
        final url = Uri.parse('$_activeRtdbUrl/candidates/$target.json');
        await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonBody,
        );
      } catch (_) {}
    }
  }

  Future<void> updateDeviceTelemetry({
    required String deviceId,
    required String pairCode,
    required int batteryLevel,
    required bool isCharging,
  }) async {
    final nowStr = DateTime.now().toIso8601String();
    final updateData = {
      'batteryLevel': batteryLevel,
      'isCharging': isCharging,
      'isOnline': true,
      'lastSeen': nowStr,
    };

    final targets = <String>{pairCode};
    for (final target in targets) {
      bool sdkSuccess = false;
      if (_dbRef != null) {
        try {
          await _dbRef!.child('telemetry').child(target).update(updateData);
          sdkSuccess = true;
        } catch (_) {}
      }
      if (!sdkSuccess) {
        try {
          final url = Uri.parse('$_activeRtdbUrl/telemetry/$target.json');
          await http.patch(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(updateData),
          );
        } catch (_) {}
      }
    }
  }

  void listenToDeviceTelemetry(
      String pairedDeviceId, void Function(Map<String, dynamic> data) onUpdate) {
    Timer.periodic(const Duration(seconds: 4), (_) async {
      try {
        final url = Uri.parse('$_activeRtdbUrl/telemetry/$pairedDeviceId.json');
        final response = await http.get(url);
        if (response.statusCode == 200 && response.body != 'null') {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          onUpdate(data);
        }
      } catch (_) {}
    });

    if (_dbRef != null) {
      try {
        _dbRef!.child('telemetry').child(pairedDeviceId).onValue.listen((event) {
          if (event.snapshot.value != null) {
            final data = Map<String, dynamic>.from(event.snapshot.value as Map);
            onUpdate(data);
          }
        });
      } catch (_) {}
    }
  }

  Future<void> rejectCall(String targetDeviceId, [String? callId, String? reason]) async {
    debugPrint('📞 [REJECT CALL] Rejecting call from $targetDeviceId (callId: $callId, reason: $reason)');
    final pin = targetDeviceId.split('_').last;
    final targets = <String>{
      targetDeviceId,
      'omega_tablet_$pin',
      'omega_parent_$pin',
      pin,
    };

    final updateData = <String, dynamic>{
      'status': (reason == 'busy') ? CallStatus.busy.name : CallStatus.rejected.name,
    };
    if (callId != null && callId.isNotEmpty) {
      updateData['callId'] = callId;
    }
    if (reason != null && reason.isNotEmpty) {
      updateData['reason'] = reason;
    }

    for (final target in targets) {
      try {
        final url = Uri.parse('$_activeRtdbUrl/calls/$target.json');
        await http.patch(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(updateData),
        );
      } catch (_) {}

      if (_dbRef != null) {
        try {
          await _dbRef!.child('calls').child(target).update(updateData);
        } catch (_) {}
      }
    }
  }

  Future<void> cleanStaleCalls(String deviceId, [String? secondaryDeviceId]) async {
    final pin = deviceId.split('_').last;
    final targets = <String>{deviceId, 'omega_tablet_$pin', 'omega_parent_$pin', pin};
    if (secondaryDeviceId != null) {
      final secPin = secondaryDeviceId.split('_').last;
      targets.addAll({secondaryDeviceId, 'omega_tablet_$secPin', 'omega_parent_$secPin', secPin});
    }

    // Safer cleanup: Check if the call is ACTUALLY stale before deleting
    // to prevent wiping out a brand new call that started right after an endCall delay.
    final futures = <Future>[];
    for (final target in targets) {
      futures.add(() async {
        try {
          final url = Uri.parse('$_activeRtdbUrl/calls/$target.json');
          final response = await http.get(url);
          if (response.statusCode == 200 && response.body != 'null') {
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            final status = data['status'] as String?;
            final createdAtStr = data['createdAt'] as String?;
            
            bool shouldDelete = false;
            if (status == CallStatus.ended.name || status == CallStatus.rejected.name) {
              shouldDelete = true;
            } else if (createdAtStr != null) {
              final createdAt = DateTime.tryParse(createdAtStr);
              if (createdAt != null) {
                final diff = DateTime.now().difference(createdAt).inSeconds.abs();
                if (diff > 45) shouldDelete = true;
              } else {
                shouldDelete = true; // Invalid date format
              }
            } else {
              shouldDelete = true; // Invalid data
            }

            if (shouldDelete) {
              await http.delete(url);
              await http.delete(Uri.parse('$_activeRtdbUrl/candidates/$target.json'));
              if (_dbRef != null) {
                await _dbRef!.child('calls').child(target).remove();
                await _dbRef!.child('candidates').child(target).remove();
              }
            }
          }
        } catch (_) {}
      }());
    }
    await Future.wait(futures);
  }

  Future<void> endCall(String myDeviceId, [String? targetDeviceId, String? callId]) async {
    debugPrint('📞 [END CALL] Ending call: $myDeviceId <-> $targetDeviceId (callId: $callId)');
    // CRITICAL FIX: Only patch the OTHER side's nodes, not our own.
    // Patching our own node causes our polling to self-trigger onCallEnded.
    final targets = <String>{};
    if (targetDeviceId != null && targetDeviceId.isNotEmpty) {
      final targetPin = targetDeviceId.split('_').last;
      targets.addAll({
        targetDeviceId,
        targetPin,
        'omega_tablet_$targetPin',
        'omega_parent_$targetPin',
      });
    } else {
      // Fallback: if no target, patch all known nodes
      final pin = myDeviceId.split('_').last;
      targets.addAll({myDeviceId, pin, 'omega_tablet_$pin', 'omega_parent_$pin'});
    }

    final endData = <String, dynamic>{
      'status': CallStatus.ended.name,
      'endedAt': DateTime.now().toIso8601String(),
    };
    if (callId != null && callId.isNotEmpty) {
      endData['callId'] = callId;
    }

    for (final target in targets) {
      try {
        final url = Uri.parse('$_activeRtdbUrl/calls/$target.json');
        await http.patch(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(endData),
        );
      } catch (_) {}

      if (_dbRef != null) {
        try {
          await _dbRef!.child('calls').child(target).update(endData);
        } catch (_) {}
      }
    }

    Future.delayed(const Duration(seconds: 5), () async {
      cleanStaleCalls(myDeviceId, targetDeviceId);
    });
  }

  // --- Instant Message Relay (Dual REST + SDK) ---

  Future<void> sendMessage(ChatMessage message) async {
    debugPrint('💬 [MESSAGE SEND] To ${message.receiverId}: "${message.text}"');
    final pin = message.receiverId.split('_').last;
    final String mainTarget = message.receiverId.isNotEmpty ? message.receiverId : pin;

    // Primary write via Firebase SDK
    if (_dbRef != null) {
      try {
        await _dbRef!
            .child('messages')
            .child(mainTarget)
            .push()
            .set(message.toJson());
      } catch (e) {
        debugPrint('⚠️ [SEND MESSAGE SDK WARN]: $e');
        // Fallback write via REST API
        try {
          final url = Uri.parse('$_activeRtdbUrl/messages/$mainTarget.json');
          await http.post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(message.toJson()),
          );
        } catch (e) {
          debugPrint('⚠️ [SEND MESSAGE REST ERROR]: $e');
        }
      }
    } else {
      // Fallback write via REST API
      try {
        final url = Uri.parse('$_activeRtdbUrl/messages/$mainTarget.json');
        await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(message.toJson()),
        );
      } catch (e) {
        debugPrint('⚠️ [SEND MESSAGE REST ERROR]: $e');
      }
    }

    // Trigger instant background push for offline/closed devices
    try {
      await NotificationService().sendMessagePushNotification(
        targetDeviceId: mainTarget,
        senderName: message.senderName ?? 'Yeni Mesaj',
        text: message.text,
        senderId: message.senderId,
      );
    } catch (_) {}
  }

  Future<void> sendMessageStatusUpdate(String targetDeviceId, String messageId, String status) async {
    debugPrint('💬 [MSG STATUS UPDATE] To $targetDeviceId: msgId=$messageId status=$status');
    final pin = targetDeviceId.split('_').last;
    final targets = <String>{
      targetDeviceId,
      pin,
      'omega_tablet_$pin',
      'omega_parent_$pin',
    };

    final payload = {
      'messageId': messageId,
      'status': status,
      'timestamp': DateTime.now().toIso8601String(),
    };

    for (final target in targets) {
      try {
        final url = Uri.parse('$_activeRtdbUrl/msg_status/$target.json');
        await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        );
      } catch (_) {}

      if (_dbRef != null) {
        try {
          await _dbRef!
              .child('msg_status')
              .child(target)
              .push()
              .set(payload);
        } catch (_) {}
      }
    }
  }

  void _listenForMessageStatus(String myDeviceId) {
    if (_dbRef == null) return;
    final myPin = myDeviceId.split('_').last;
    final targets = <String>{myDeviceId, myPin, 'omega_tablet_$myPin', 'omega_parent_$myPin'};
    for (final target in targets) {
      _dbRef!.child('msg_status').child(target).onChildAdded.listen((event) {
        if (event.snapshot.value != null && onMessageStatusUpdated != null) {
          try {
            final data = Map<String, dynamic>.from(event.snapshot.value as Map);
            final messageId = data['messageId'] as String?;
            final status = data['status'] as String?;
            if (messageId != null && status != null) {
              onMessageStatusUpdated!(messageId, status);
            }
            event.snapshot.ref.remove();
          } catch (_) {}
        }
      }, onError: (e) {
        debugPrint('⚠️ [MSG STATUS LISTEN ERROR on $target]: $e');
      });
    }
  }

  void _startPollingForMessageStatus(String myDeviceId) {
    Timer.periodic(const Duration(milliseconds: 1000), (_) async {
      if (_dbRef != null) return; // Smart Hybrid: Skip HTTP polling while WebSocket stream is active
      final pin = myDeviceId.split('_').last;
      final Set<String> targets = {myDeviceId, pin, 'omega_tablet_$pin', 'omega_parent_$pin', ..._extraListenTargets};

      for (final target in targets) {
        try {
          final url = Uri.parse('$_activeRtdbUrl/msg_status/$target.json');
          final response = await http.get(url);
          if (response.statusCode == 200 && response.body != 'null') {
            final dataMap = jsonDecode(response.body) as Map<String, dynamic>;
            dataMap.forEach((key, value) {
              try {
                final map = Map<String, dynamic>.from(value as Map);
                final messageId = map['messageId'] as String?;
                final status = map['status'] as String?;
                if (messageId != null && status != null && onMessageStatusUpdated != null) {
                  onMessageStatusUpdated!(messageId, status);
                }
                http.delete(Uri.parse('$_activeRtdbUrl/msg_status/$target/$key.json'));
              } catch (_) {}
            });
          }
        } catch (_) {}
      }
    });
  }

  Future<void> sendTypingStatus(String myDeviceId, String targetDeviceId, bool isTyping) async {
    final pin = targetDeviceId.split('_').last;
    final targets = <String>{
      targetDeviceId,
      pin,
      'omega_tablet_$pin',
      'omega_parent_$pin',
    };

    final nowMs = DateTime.now().millisecondsSinceEpoch;
    final payload = {
      'senderId': myDeviceId,
      'isTyping': isTyping,
      'timestamp': nowMs,
    };

    for (final target in targets) {
      if (!isTyping) {
        // Node cleanup on stop typing/message send so no lingering state exists
        if (_dbRef != null) {
          try {
            await _dbRef!.child('typing_status').child(target).child(myDeviceId).remove();
          } catch (_) {}
        }
        try {
          final url = Uri.parse('$_activeRtdbUrl/typing_status/$target/$myDeviceId.json');
          await http.delete(url);
        } catch (_) {}
      } else {
        if (_dbRef != null) {
          try {
            await _dbRef!.child('typing_status').child(target).child(myDeviceId).set(payload);
          } catch (_) {}
        }
        try {
          final url = Uri.parse('$_activeRtdbUrl/typing_status/$target/$myDeviceId.json');
          await http.put(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          );
        } catch (_) {}
      }
    }
  }

  void _listenForTypingStatus(String myDeviceId) {
    if (_dbRef == null) return;
    final pin = myDeviceId.split('_').last;
    final targets = {myDeviceId, pin, 'omega_tablet_$pin', 'omega_parent_$pin'};
    for (final target in targets) {
      _dbRef!.child('typing_status').child(target).onValue.listen((event) {
        if (onTypingStatusChanged == null) return;
        if (event.snapshot.value == null) {
          // Node was deleted (typing stopped) — don't emit empty senderId
          return;
        }
        try {
          final dataMap = Map<String, dynamic>.from(event.snapshot.value as Map);
          dataMap.forEach((senderId, val) {
            if (senderId.isEmpty || senderId == myDeviceId) return;
            final map = Map<String, dynamic>.from(val as Map);
            final isTyping = map['isTyping'] as bool? ?? false;
            final timestampMs = (map['timestamp'] is int)
                ? map['timestamp'] as int
                : int.tryParse(map['timestamp']?.toString() ?? '0') ?? 0;
            onTypingStatusChanged!(senderId, isTyping, timestampMs);
          });
        } catch (_) {}
      }, onError: (e) {
        debugPrint('⚠️ [TYPING STATUS LISTEN ERROR]: $e');
      });
    }
  }

  void _startPollingForTypingStatus(String myDeviceId) {
    Timer.periodic(const Duration(milliseconds: 1500), (_) async {
      if (_dbRef != null) return; // Smart Hybrid: Skip HTTP polling while WebSocket stream is active
      final pin = myDeviceId.split('_').last;
      final Set<String> targets = {myDeviceId, pin, 'omega_tablet_$pin', 'omega_parent_$pin', ..._extraListenTargets};

      for (final target in targets) {
        try {
          final url = Uri.parse('$_activeRtdbUrl/typing_status/$target.json');
          final response = await http.get(url);
          if (response.statusCode == 200) {
            if (response.body == 'null') {
              // Node is empty/deleted — do nothing (no ghost events)
            } else {
              final dataMap = jsonDecode(response.body) as Map<String, dynamic>;
              dataMap.forEach((senderId, value) {
                try {
                  if (senderId.isEmpty || senderId == myDeviceId) return;
                  final map = Map<String, dynamic>.from(value as Map);
                  final isTyping = map['isTyping'] as bool? ?? false;
                  final timestampMs = (map['timestamp'] is int)
                      ? map['timestamp'] as int
                      : int.tryParse(map['timestamp']?.toString() ?? '0') ?? 0;

                  final now = DateTime.now().millisecondsSinceEpoch;
                  if (now - timestampMs > 3500) {
                    // Stale packet -> remove stale node, don't trigger typing
                    http.delete(Uri.parse('$_activeRtdbUrl/typing_status/$target/$senderId.json'));
                  } else {
                    if (onTypingStatusChanged != null) {
                      onTypingStatusChanged!(senderId, isTyping, timestampMs);
                    }
                  }
                } catch (_) {}
              });
            }
          }
        } catch (_) {}
      }
    });
  }

  // --- Internal Listeners & REST Polling Fallbacks ---

  final List<StreamSubscription> _callSubscriptions = [];
  final List<StreamSubscription> _candidateSubscriptions = [];

  void _listenForCalls(String myDeviceId) {
    if (_dbRef == null) return;
    final myPin = myDeviceId.split('_').last;
    final targets = <String>{myDeviceId, myPin, 'omega_tablet_$myPin', 'omega_parent_$myPin'};

    // Cancel old subscriptions
    for (final sub in _callSubscriptions) { sub.cancel(); }
    _callSubscriptions.clear();
    for (final sub in _candidateSubscriptions) { sub.cancel(); }
    _candidateSubscriptions.clear();

    void processCallEvent(Map<String, dynamic> data) {
      final session = CallSession.fromJson(data);

      bool isCallStale(CallSession s) {
        final diff = DateTime.now().difference(s.createdAt).inSeconds.abs();
        return s.status == CallStatus.ended || diff > 45;
      }

      if (isCallStale(session)) {
        if (session.status == CallStatus.ended && onCallEnded != null) {
          if (!_processedEndedCallIds.contains(session.callId)) {
            _processedEndedCallIds.add(session.callId);
            onCallEnded!(session.callId);
          }
        }
        Future.delayed(const Duration(seconds: 3), () {
          cleanStaleCalls(myDeviceId);
        });
        return;
      }

      final isSelfCaller = session.callerId == myDeviceId ||
          session.callerId.contains(myDeviceId) ||
          myDeviceId.contains(session.callerId) ||
          session.callerId.endsWith(myPin);

      if (session.status == CallStatus.calling &&
          !isSelfCaller &&
          onIncomingCall != null) {
        if (!_processedCallIds.contains(session.callId)) {
          _processedCallIds.add(session.callId);
          _trimProcessedSets();
          onIncomingCall!(session);
        }
      } else if (session.status == CallStatus.connected &&
          isSelfCaller &&
          session.sdpAnswer != null &&
          onCallAnswer != null) {
        if (session.callId.isNotEmpty && !_processedAnswerCallIds.contains(session.callId)) {
          _processedAnswerCallIds.add(session.callId);
          onCallAnswer!(session.sdpAnswer!);
        }
      } else if (session.status == CallStatus.rejected || session.status == CallStatus.busy) {
        if (onCallRejected != null && !_processedEndedCallIds.contains(session.callId)) {
          _processedEndedCallIds.add(session.callId);
          onCallRejected!(session.callId);
        }
      } else if (session.status == CallStatus.ended) {
        if (onCallEnded != null && !_processedEndedCallIds.contains(session.callId)) {
          _processedEndedCallIds.add(session.callId);
          onCallEnded!(session.callId);
        }
      }
    }

    for (final target in targets) {
      final callSub = _dbRef!.child('calls').child(target).onValue.listen((event) {
        if (event.snapshot.value != null) {
          try {
            final data = Map<String, dynamic>.from(event.snapshot.value as Map);
            processCallEvent(data);
          } catch (_) {}
        }
      }, onError: (e) {
        debugPrint('⚠️ [CALL LISTEN ERROR on $target]: $e');
      });
      _callSubscriptions.add(callSub);

      final candSub = _dbRef!.child('candidates').child(target).onChildAdded.listen((event) {
        if (event.snapshot.value != null && onIceCandidate != null) {
          try {
            final candidate = Map<String, dynamic>.from(event.snapshot.value as Map);
            onIceCandidate!(candidate);
          } catch (_) {}
        }
      }, onError: (e) {
        debugPrint('⚠️ [CANDIDATE LISTEN ERROR on $target]: $e');
      });
      _candidateSubscriptions.add(candSub);
    }
  }

  void _listenForMessages(String myDeviceId) {
    if (_dbRef == null) return;
    final myPin = myDeviceId.split('_').last;
    final targets = <String>{myDeviceId, myPin, 'omega_tablet_$myPin', 'omega_parent_$myPin'};
    for (final target in targets) {
      _dbRef!.child('messages').child(target).onChildAdded.listen((event) {
        if (event.snapshot.value != null && onChatMessageReceived != null) {
          try {
            final data = Map<String, dynamic>.from(event.snapshot.value as Map);
            final msg = ChatMessage.fromJson(data);
            onChatMessageReceived!(msg);
            event.snapshot.ref.remove();
          } catch (_) {}
        }
      }, onError: (e) {
        debugPrint('⚠️ [MSG LISTEN ERROR on $target]: $e');
      });
    }
  }

  void _startPollingForMessages(String myDeviceId) {
    Timer.periodic(const Duration(milliseconds: 1000), (_) async {
      if (_dbRef != null) return; // Smart Hybrid: Skip HTTP polling while WebSocket stream is active
      final pin = myDeviceId.split('_').last;
      final Set<String> targets = {myDeviceId, pin, 'omega_tablet_$pin', 'omega_parent_$pin', ..._extraListenTargets};

      for (final target in targets) {
        try {
          final url = Uri.parse('$_activeRtdbUrl/messages/$target.json');
          final response = await http.get(url);
          if (response.statusCode == 200 && response.body != 'null') {
            final dataMap = jsonDecode(response.body) as Map<String, dynamic>;
            dataMap.forEach((key, value) {
              try {
                final msg = ChatMessage.fromJson(Map<String, dynamic>.from(value as Map));
                if (onChatMessageReceived != null) {
                  onChatMessageReceived!(msg);
                }
                http.delete(Uri.parse('$_activeRtdbUrl/messages/$target/$key.json'));
              } catch (_) {}
            });
          }
        } catch (_) {}
      }
    });
  }

  void _startPollingForCalls(String myDeviceId) {
    Timer.periodic(const Duration(milliseconds: 500), (_) async {
      if (_dbRef != null) return; // Smart Hybrid: Skip HTTP polling while WebSocket stream is active
      final pin = myDeviceId.split('_').last;
      final altMyDeviceId = myDeviceId.contains('tablet')
          ? 'omega_parent_$pin'
          : 'omega_tablet_$pin';
      final Set<String> targets = {myDeviceId, altMyDeviceId, pin, ..._extraListenTargets};

      for (final target in targets) {
        try {
          final url = Uri.parse('$_activeRtdbUrl/calls/$target.json');
          final response = await http.get(url);
          if (response.statusCode == 200 && response.body != 'null') {
            final data = jsonDecode(response.body) as Map<String, dynamic>;
            final session = CallSession.fromJson(data);

            final diff = DateTime.now().difference(session.createdAt).inSeconds.abs();
            if (session.status == CallStatus.ended || diff > 45) {
              if (session.status == CallStatus.ended && onCallEnded != null) {
                if (!_processedEndedCallIds.contains(session.callId)) {
                  _processedEndedCallIds.add(session.callId);
                  onCallEnded!(session.callId);
                }
              }
              Future.delayed(const Duration(seconds: 3), () {
                cleanStaleCalls(myDeviceId);
              });
              continue;
            }

            final isSelfCaller = session.callerId == myDeviceId ||
                session.callerId == altMyDeviceId ||
                session.callerId.contains(myDeviceId) ||
                myDeviceId.contains(session.callerId) ||
                session.callerId.endsWith(pin);

            if ((session.status == CallStatus.calling || session.status == CallStatus.ringing) &&
                !isSelfCaller) {
              if (!_processedCallIds.contains(session.callId)) {
                _processedCallIds.add(session.callId);
                _trimProcessedSets();
                if (onIncomingCall != null) {
                  onIncomingCall!(session);
                }
              }
            } else if (session.status == CallStatus.connected &&
                isSelfCaller &&
                session.sdpAnswer != null &&
                onCallAnswer != null) {
              // CRITICAL FIX: Only process answer ONCE per valid callId
              if (session.callId.isNotEmpty && !_processedAnswerCallIds.contains(session.callId)) {
                _processedAnswerCallIds.add(session.callId);
                onCallAnswer!(session.sdpAnswer!);
              }
            } else if (session.status == CallStatus.rejected || session.status == CallStatus.busy) {
              if (onCallRejected != null && !_processedEndedCallIds.contains(session.callId)) {
                _processedEndedCallIds.add(session.callId);
                onCallRejected!(session.callId);
              }
            } else if (session.status == CallStatus.ended) {
              if (onCallEnded != null && !_processedEndedCallIds.contains(session.callId)) {
                _processedEndedCallIds.add(session.callId);
                onCallEnded!(session.callId);
              }
            }
          }
        } catch (_) {}

        // Poll for ICE candidates
        try {
          final candUrl = Uri.parse('$_activeRtdbUrl/candidates/$target.json');
          final response = await http.get(candUrl);
          if (response.statusCode == 200 && response.body != 'null') {
            final dataMap = jsonDecode(response.body) as Map<String, dynamic>;
            dataMap.forEach((key, value) {
              try {
                final cand = Map<String, dynamic>.from(value as Map);
                if (onIceCandidate != null) {
                  onIceCandidate!(cand);
                }
                http.delete(Uri.parse('$_activeRtdbUrl/candidates/$target/$key.json'));
              } catch (_) {}
            });
          }
        } catch (_) {}
      }
    });
  }

  // --- Persistent Cloud History (Calls & Chats) ---

  Future<void> saveCallRecordToFirebase(String pinCode, CallSession session) async {
    try {
      final url = Uri.parse('$_activeRtdbUrl/history_calls/$pinCode/${session.callId}.json');
      await http.put(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(session.toJson()),
      );
    } catch (_) {}

    if (_dbRef != null) {
      try {
        await _dbRef!.child('history_calls').child(pinCode).child(session.callId).set(session.toJson());
      } catch (_) {}
    }
  }

  void listenCallHistoryFromFirebase(String pinCode, Function(List<CallSession> history) onHistoryUpdated) {
    if (_dbRef != null) {
      _dbRef!.child('history_calls').child(pinCode).onValue.listen((event) {
        if (event.snapshot.value != null) {
          try {
            final Map data = event.snapshot.value as Map;
            final List<CallSession> list = [];
            data.forEach((key, val) {
              list.add(CallSession.fromJson(Map<String, dynamic>.from(val as Map)));
            });
            list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
            onHistoryUpdated(list);
          } catch (_) {}
        }
      }, onError: (e) {
        debugPrint('⚠️ [CALL HISTORY LISTEN ERROR]: $e');
      });
    }

    Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final url = Uri.parse('$_activeRtdbUrl/history_calls/$pinCode.json');
        final res = await http.get(url);
        if (res.statusCode == 200 && res.body != 'null') {
          final Map<String, dynamic> data = jsonDecode(res.body);
          final List<CallSession> list = [];
          data.forEach((key, val) {
            list.add(CallSession.fromJson(Map<String, dynamic>.from(val as Map)));
          });
          list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          onHistoryUpdated(list);
        }
      } catch (_) {}
    });
  }

  /// Automatically cleanup 1-on-1 chat messages older than 90 days (3 months) from Firebase RTDB
  Future<void> cleanupOldChatHistory(String pinCode) async {
    if (pinCode.trim().isEmpty) return;
    final cleanPin = pinCode.trim();
    final cutoffDate = DateTime.now().subtract(const Duration(days: 90));

    try {
      if (_dbRef != null) {
        final snapshot = await _dbRef!.child('history_chats').child(cleanPin).get();
        if (snapshot.exists && snapshot.value != null && snapshot.value is Map) {
          final Map data = snapshot.value as Map;
          data.forEach((key, val) {
            try {
              if (val is Map) {
                final tsStr = val['timestamp'] as String?;
                if (tsStr != null) {
                  final msgDate = DateTime.parse(tsStr);
                  if (msgDate.isBefore(cutoffDate)) {
                    _dbRef!.child('history_chats').child(cleanPin).child(key).remove();
                    debugPrint('🗑️ [FIREBASE CLEANUP] Removed 90+ day old 1-on-1 chat message: $key');
                  }
                }
              }
            } catch (_) {}
          });
        }
      } else {
        final url = Uri.parse('$_activeRtdbUrl/history_chats/$cleanPin.json');
        final response = await http.get(url);
        if (response.statusCode == 200 && response.body != 'null') {
          final Map<String, dynamic> data = jsonDecode(response.body);
          data.forEach((key, val) {
            try {
              if (val is Map) {
                final tsStr = val['timestamp'] as String?;
                if (tsStr != null) {
                  final msgDate = DateTime.parse(tsStr);
                  if (msgDate.isBefore(cutoffDate)) {
                    http.delete(Uri.parse('$_activeRtdbUrl/history_chats/$cleanPin/$key.json'));
                  }
                }
              }
            } catch (_) {}
          });
        }
      }
    } catch (e) {
      debugPrint('⚠️ [FIREBASE CHAT CLEANUP NOTICE]: $e');
    }
  }

  /// Completely delete 1-on-1 chat history between my device and a paired device pin from Firebase
  Future<void> deleteEntireChatFromFirebase(String myPin, String peerPin) async {
    final cleanMyPin = myPin.trim().split('_').last;
    final cleanPeerPin = peerPin.trim().split('_').last;
    final channels = {
      cleanMyPin,
      cleanPeerPin,
      '$cleanMyPin-$cleanPeerPin',
      '$cleanPeerPin-$cleanMyPin',
    };

    for (final ch in channels) {
      if (ch.isEmpty) continue;
      try {
        if (_dbRef != null) {
          await _dbRef!.child('history_chats').child(ch).remove();
        }
        final url = Uri.parse('$_activeRtdbUrl/history_chats/$ch.json');
        await http.delete(url);
      } catch (e) {
        debugPrint('⚠️ [DELETE CHAT NOTICE]: $e');
      }
    }
  }

  Future<void> saveChatMessageToFirebase(String pinCode, ChatMessage message) async {
    // Trigger auto-cleanup for 90+ day old messages
    cleanupOldChatHistory(pinCode);

    try {
      final url = Uri.parse('$_activeRtdbUrl/history_chats/$pinCode/${message.id}.json');
      await http.put(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(message.toJson()),
      );
    } catch (_) {}

    if (_dbRef != null) {
      try {
        await _dbRef!.child('history_chats').child(pinCode).child(message.id).set(message.toJson());
      } catch (_) {}
    }
  }

  void listenChatHistoryFromFirebase(String pinCode, Function(List<ChatMessage> chats) onChatsUpdated) {
    // Trigger auto-cleanup for 90+ day old messages
    cleanupOldChatHistory(pinCode);

    if (_dbRef != null) {
      _dbRef!.child('history_chats').child(pinCode).onValue.listen((event) {
        if (event.snapshot.value != null) {
          try {
            final Map data = event.snapshot.value as Map;
            final List<ChatMessage> list = [];
            data.forEach((key, val) {
              list.add(ChatMessage.fromJson(Map<String, dynamic>.from(val as Map)));
            });
            list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
            onChatsUpdated(list);
          } catch (_) {}
        }
      }, onError: (e) {
        debugPrint('⚠️ [CHAT HISTORY LISTEN ERROR]: $e');
      });
    }

    Timer.periodic(const Duration(seconds: 3), (_) async {
      try {
        final url = Uri.parse('$_activeRtdbUrl/history_chats/$pinCode.json');
        final res = await http.get(url);
        if (res.statusCode == 200 && res.body != 'null') {
          final Map<String, dynamic> data = jsonDecode(res.body);
          final List<ChatMessage> list = [];
          data.forEach((key, val) {
            list.add(ChatMessage.fromJson(Map<String, dynamic>.from(val as Map)));
          });
          list.sort((a, b) => a.timestamp.compareTo(b.timestamp));
          onChatsUpdated(list);
        }
      } catch (_) {}
    });
  }

  final List<StreamSubscription> _groupSubscriptions = [];
  Timer? _groupPollingTimer;

  Future<void> sendGroupChatMessage(
    String familyPin,
    List<String> targetDeviceIds,
    ChatMessage message,
  ) async {
    final payload = message.toJson();

    // Trigger auto-cleanup for 90+ day old group chat messages
    cleanupOldGroupMessages(familyPin);

    // 1. Save to persistent global group history
    try {
      if (_dbRef != null) {
        await _dbRef!.child('group_messages').child(familyPin).push().set(payload);
      } else {
        final url = Uri.parse('$_activeRtdbUrl/group_messages/$familyPin.json');
        await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        );
      }
    } catch (_) {}

    // 2. Push real-time notification queue payload to every paired recipient device inbox
    final recipientTargets = <String>{
      ...targetDeviceIds,
      familyPin,
    };

    for (final target in recipientTargets) {
      if (target.trim().isEmpty) continue;
      final targetPin = target.split('_').last;
      final inboxNodes = {target, targetPin, 'omega_tablet_$targetPin', 'omega_parent_$targetPin'};

      for (final node in inboxNodes) {
        if (node.isEmpty) continue;
        if (_dbRef != null) {
          try {
            await _dbRef!.child('group_inbox').child(node).push().set(payload);
          } catch (_) {}
        }
        try {
          final url = Uri.parse('$_activeRtdbUrl/group_inbox/$node.json');
          await http.post(
            url,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          );
        } catch (_) {}
      }
    }
  }

  /// Automatically cleanup family group chat messages older than 90 days (3 months) from Firebase RTDB
  Future<void> cleanupOldGroupMessages(String familyPin) async {
    if (familyPin.trim().isEmpty) return;
    final cleanPin = familyPin.trim();
    final cutoffDate = DateTime.now().subtract(const Duration(days: 90));

    try {
      if (_dbRef != null) {
        final snapshot = await _dbRef!.child('group_messages').child(cleanPin).get();
        if (snapshot.exists && snapshot.value != null && snapshot.value is Map) {
          final Map data = snapshot.value as Map;
          data.forEach((key, val) {
            try {
              if (val is Map) {
                final tsStr = val['timestamp'] as String?;
                if (tsStr != null) {
                  final msgDate = DateTime.parse(tsStr);
                  if (msgDate.isBefore(cutoffDate)) {
                    _dbRef!.child('group_messages').child(cleanPin).child(key).remove();
                    debugPrint('🗑️ [FIREBASE CLEANUP] Removed 90+ day old group message: $key');
                  }
                }
              }
            } catch (_) {}
          });
        }
      } else {
        final url = Uri.parse('$_activeRtdbUrl/group_messages/$cleanPin.json');
        final response = await http.get(url);
        if (response.statusCode == 200 && response.body != 'null') {
          final Map<String, dynamic> data = jsonDecode(response.body);
          data.forEach((key, val) {
            try {
              if (val is Map) {
                final tsStr = val['timestamp'] as String?;
                if (tsStr != null) {
                  final msgDate = DateTime.parse(tsStr);
                  if (msgDate.isBefore(cutoffDate)) {
                    http.delete(Uri.parse('$_activeRtdbUrl/group_messages/$cleanPin/$key.json'));
                  }
                }
              }
            } catch (_) {}
          });
        }
      }
    } catch (e) {
      debugPrint('⚠️ [FIREBASE CHAT CLEANUP NOTICE]: $e');
    }
  }

  /// Completely wipe family group chat messages from Firebase RTDB (Admin only)
  Future<void> clearGroupChatFromFirebase(String familyPin) async {
    if (familyPin.trim().isEmpty) return;
    final cleanPin = familyPin.trim();
    try {
      if (_dbRef != null) {
        await _dbRef!.child('group_messages').child(cleanPin).remove();
      }
      final url = Uri.parse('$_activeRtdbUrl/group_messages/$cleanPin.json');
      await http.delete(url);
      debugPrint('🗑️ [FIREBASE GROUP CHAT WIPED] Group messages cleared for pin: $cleanPin');
    } catch (e) {
      debugPrint('⚠️ [FIREBASE GROUP CHAT WIPE ERROR]: $e');
    }
  }


  void listenGroupMessages(String myDeviceId, {List<String>? fallbackPins}) {
    for (final sub in _groupSubscriptions) {
      sub.cancel();
    }
    _groupSubscriptions.clear();
    _groupPollingTimer?.cancel();

    final myPin = myDeviceId.split('_').last;
    final Set<String> targets = {
      myDeviceId,
      myPin,
      'omega_tablet_$myPin',
      'omega_parent_$myPin',
      ...?fallbackPins,
    };

    // Run auto-cleanup for group messages older than 90 days (3 months)
    for (final pin in targets) {
      if (pin.trim().isNotEmpty) {
        cleanupOldGroupMessages(pin);
      }
    }

    // WebSocket real-time queue listener with auto-delete after consumption
    if (_dbRef != null) {
      for (final target in targets) {
        if (target.trim().isEmpty) continue;
        final sub = _dbRef!
            .child('group_inbox')
            .child(target.trim())
            .onChildAdded
            .listen((event) {
          if (event.snapshot.value != null && onGroupChatMessageReceived != null) {
            try {
              final data = Map<String, dynamic>.from(event.snapshot.value as Map);
              final msg = ChatMessage.fromJson(data);
              onGroupChatMessageReceived!(msg);
              event.snapshot.ref.remove();
            } catch (_) {}
          }
        });
        _groupSubscriptions.add(sub);
      }
    }

    // Polling fallback (every 1000ms) for 100% guaranteed delivery even when sockets pause
    _groupPollingTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) async {
      if (_dbRef != null) return; // Smart Hybrid: Skip HTTP polling while WebSocket stream is active
      for (final target in targets) {
        if (target.trim().isEmpty) continue;
        try {
          final url = Uri.parse('$_activeRtdbUrl/group_inbox/$target.json');
          final response = await http.get(url);
          if (response.statusCode == 200 && response.body != 'null') {
            final dataMap = jsonDecode(response.body) as Map<String, dynamic>;
            dataMap.forEach((key, value) {
              try {
                final msg = ChatMessage.fromJson(Map<String, dynamic>.from(value as Map));
                if (onGroupChatMessageReceived != null) {
                  onGroupChatMessageReceived!(msg);
                }
                http.delete(Uri.parse('$_activeRtdbUrl/group_inbox/$target/$key.json'));
              } catch (_) {}
            });
          }
        } catch (_) {}
      }
    });
  }

  void dispose() {
    _callSubscription?.cancel();
    _candidateSubscription?.cancel();
    _chatSubscription?.cancel();
    for (final sub in _groupSubscriptions) {
      sub.cancel();
    }
    _groupSubscriptions.clear();
    _groupPollingTimer?.cancel();
    _pairSubscription?.cancel();
    _pollingTimer?.cancel();
    for (final sub in _cameraSubscriptions) {
      sub.cancel();
    }
    _cameraSubscriptions.clear();
  }

  // --- SECURITY CAMERA MODE SIGNALS & TALK-BACK MUTEX LOCK ---

  final List<StreamSubscription> _cameraSubscriptions = [];
  Timer? _cameraPollingTimer;

  Future<void> publishCameraStatus({
    required String familyPin,
    required String deviceId,
    required String deviceName,
    required bool isActive,
    List<String>? fallbackPins,
    Map<String, dynamic>? settings,
  }) async {
    final targets = <String>{familyPin, ...?fallbackPins}.where((p) => p.trim().isNotEmpty).toList();
    if (targets.isEmpty) return;

    for (final pin in targets) {
      try {
        final camPath = 'family_cameras/$pin/$deviceId';
        if (isActive) {
          final payload = {
            'deviceId': deviceId,
            'deviceName': deviceName,
            'isActive': true,
            'timestamp': DateTime.now().millisecondsSinceEpoch,
            'settings': settings ?? {},
          };
          if (_dbRef != null) {
            try {
              await _dbRef!.child(camPath).set(payload);
              await _dbRef!.child(camPath).onDisconnect().remove();
            } catch (_) {}
          }
          final url = Uri.parse('$_activeRtdbUrl/$camPath.json');
          await http.put(url, body: jsonEncode(payload));
        } else {
          if (_dbRef != null) {
            try {
              await _dbRef!.child(camPath).remove();
              await _dbRef!.child(camPath).onDisconnect().cancel();
            } catch (_) {}
          }
          final url = Uri.parse('$_activeRtdbUrl/$camPath.json');
          await http.delete(url);
        }
      } catch (e) {
        debugPrint('⚠️ [CAMERA PUBLISH ERROR for $pin]: $e');
      }
    }
  }

  void listenFamilyCameras(List<String> pins, Function(List<Map<String, dynamic>>) onUpdate) {
    for (final sub in _cameraSubscriptions) {
      sub.cancel();
    }
    _cameraSubscriptions.clear();
    _cameraPollingTimer?.cancel();

    final validPins = pins.where((p) => p.trim().isNotEmpty).toSet();
    if (validPins.isEmpty) return;

    final Map<String, Map<String, Map<String, dynamic>>> pinResults = {};

    void emitUpdatedCameras() {
      final Map<String, Map<String, dynamic>> combined = {};
      for (final pinCams in pinResults.values) {
        combined.addAll(pinCams);
      }
      onUpdate(combined.values.toList());
    }

    // 1. SDK WebSocket stream listeners
    if (_dbRef != null) {
      for (final pin in validPins) {
        try {
          final sub = _dbRef!.child('family_cameras').child(pin).onValue.listen((event) {
            final Map<String, Map<String, dynamic>> currentPinCameras = {};
            if (event.snapshot.value != null) {
              try {
                final data = Map<String, dynamic>.from(event.snapshot.value as Map);
                data.forEach((key, val) {
                  if (val is Map) {
                    final cam = Map<String, dynamic>.from(val);
                    if (cam['isActive'] == true && cam['deviceId'] != null) {
                      currentPinCameras[cam['deviceId'] as String] = cam;
                    }
                  }
                });
              } catch (_) {}
            }
            pinResults[pin] = currentPinCameras;
            emitUpdatedCameras();
          }, onError: (e) {
            debugPrint('⚠️ [CAMERA LISTEN SDK ERROR on $pin]: $e');
          });
          _cameraSubscriptions.add(sub);
        } catch (_) {}
      }
    }

    // 2. REST Polling Fallback (ensures Web, backgrounding, and reconnecting always see active cameras)
    _cameraPollingTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      for (final pin in validPins) {
        try {
          final url = Uri.parse('$_activeRtdbUrl/family_cameras/$pin.json');
          final response = await http.get(url);
          if (response.statusCode == 200) {
            final Map<String, Map<String, dynamic>> currentPinCameras = {};
            if (response.body != 'null') {
              final data = jsonDecode(response.body);
              if (data is Map) {
                data.forEach((key, val) {
                  if (val is Map) {
                    final cam = Map<String, dynamic>.from(val);
                    if (cam['isActive'] == true && cam['deviceId'] != null) {
                      currentPinCameras[cam['deviceId'] as String] = cam;
                    }
                  }
                });
              }
            }
            pinResults[pin] = currentPinCameras;
            emitUpdatedCameras();
          }
        } catch (_) {}
      }
    });
  }

  // --- CAMERA WebRTC SIGNALING (offer/answer/ICE for camera streams) ---

  /// Camera Station: listen for incoming viewer connection requests
  StreamSubscription? listenForCameraViewers({
    required String cameraDeviceId,
    required Function(Map<String, dynamic> viewerRequest) onViewerRequest,
  }) {
    if (cameraDeviceId.trim().isEmpty) {
      debugPrint('❌ [CAMERA LISTENER] Empty cameraDeviceId!');
      return null;
    }

    debugPrint('👂 [CAMERA LISTENER] Subscribing to camera_signaling/$cameraDeviceId/viewers');

    final Set<String> processedViewerEvents = {};

    void handleData(String viewerId, Map<String, dynamic> data) {
      data['viewerId'] = viewerId;
      final ts = data['timestamp'] ?? 0;
      final key = '${viewerId}_$ts';
      if (processedViewerEvents.contains(key)) return;
      processedViewerEvents.add(key);
      if (processedViewerEvents.length > 50) processedViewerEvents.remove(processedViewerEvents.first);
      debugPrint('📩 [CAMERA LISTENER] Viewer event: viewerId=$viewerId, ts=$ts');
      onViewerRequest(data);
    }

    StreamSubscription? addedSub;
    if (_dbRef != null) {
      final viewersRef = _dbRef!
          .child('camera_signaling')
          .child(cameraDeviceId)
          .child('viewers');

      void handleEvent(DatabaseEvent event) {
        if (event.snapshot.value != null) {
          try {
            final data = Map<String, dynamic>.from(event.snapshot.value as Map);
            final viewerId = event.snapshot.key ?? '';
            handleData(viewerId, data);
          } catch (e) {
            debugPrint('❌ [CAMERA LISTENER] Error parsing viewer data: $e');
          }
        }
      }

      addedSub = viewersRef.onChildAdded.listen(handleEvent);
      _viewerChangedSub?.cancel();
      _viewerChangedSub = viewersRef.onChildChanged.listen(handleEvent);
    }

    // REST Polling failsafe for viewers
    Timer.periodic(const Duration(milliseconds: 1000), (timer) async {
      try {
        final url = Uri.parse('$_activeRtdbUrl/camera_signaling/$cameraDeviceId/viewers.json');
        final response = await http.get(url);
        if (response.statusCode == 200 && response.body != 'null') {
          final data = jsonDecode(response.body);
          if (data is Map) {
            data.forEach((viewerId, val) {
              if (val is Map) {
                handleData(viewerId.toString(), Map<String, dynamic>.from(val));
              }
            });
          }
        }
      } catch (_) {}
    });

    return addedSub;
  }

  // onChildChanged subscription (cancelled separately)
  StreamSubscription? _viewerChangedSub;

  /// Cancel viewer changed subscription (call from camera station dispose)
  void cancelViewerChangedSub() {
    _viewerChangedSub?.cancel();
    _viewerChangedSub = null;
  }

  /// Viewer: send offer to camera station
  Future<void> sendCameraOffer({
    required String cameraDeviceId,
    required String viewerDeviceId,
    required Map<String, dynamic> offer,
  }) async {
    if (cameraDeviceId.trim().isEmpty || viewerDeviceId.trim().isEmpty) return;
    final payload = {
      'offer': offer,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    if (_dbRef != null) {
      try {
        await _dbRef!
            .child('camera_signaling')
            .child(cameraDeviceId)
            .child('viewers')
            .child(viewerDeviceId)
            .set(payload);
        debugPrint('✅ [CAMERA OFFER SDK SENT] to $cameraDeviceId from $viewerDeviceId');
      } catch (e) {
        debugPrint('⚠️ [CAMERA OFFER SDK WARN]: $e. Falling back to HTTP...');
      }
    }

    try {
      final path = 'camera_signaling/$cameraDeviceId/viewers/$viewerDeviceId';
      final url = Uri.parse('$_activeRtdbUrl/$path.json');
      await http.put(url, body: jsonEncode(payload));
    } catch (e) {
      debugPrint('⚠️ [CAMERA OFFER HTTP ERROR]: $e');
    }
  }

  /// Camera Station: send answer back to viewer
  Future<void> sendCameraAnswer({
    required String cameraDeviceId,
    required String viewerDeviceId,
    required Map<String, dynamic> answer,
  }) async {
    if (cameraDeviceId.trim().isEmpty || viewerDeviceId.trim().isEmpty) return;
    final payload = {
      'answer': answer,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
    };

    if (_dbRef != null) {
      try {
        await _dbRef!
            .child('camera_signaling')
            .child(cameraDeviceId)
            .child('answer_$viewerDeviceId')
            .set(payload);
        debugPrint('✅ [CAMERA ANSWER SDK SENT] to $viewerDeviceId');
      } catch (e) {
        debugPrint('⚠️ [CAMERA ANSWER SDK WARN]: $e. Falling back to HTTP...');
      }
    }

    try {
      final path = 'camera_signaling/$cameraDeviceId/answer_$viewerDeviceId';
      final url = Uri.parse('$_activeRtdbUrl/$path.json');
      await http.put(url, body: jsonEncode(payload));
    } catch (e) {
      debugPrint('⚠️ [CAMERA ANSWER HTTP ERROR]: $e');
    }
  }

  /// Viewer: listen for answer from camera station
  StreamSubscription? listenForCameraAnswer({
    required String cameraDeviceId,
    required String viewerDeviceId,
    required Function(Map<String, dynamic> answer) onAnswer,
  }) {
    if (cameraDeviceId.trim().isEmpty || viewerDeviceId.trim().isEmpty) return null;

    bool answered = false;

    StreamSubscription? sub;
    if (_dbRef != null) {
      sub = _dbRef!
          .child('camera_signaling')
          .child(cameraDeviceId)
          .child('answer_$viewerDeviceId')
          .onValue
          .listen((event) {
        if (event.snapshot.value != null && !answered) {
          try {
            final data = Map<String, dynamic>.from(event.snapshot.value as Map);
            if (data['answer'] != null) {
              answered = true;
              onAnswer(Map<String, dynamic>.from(data['answer'] as Map));
            }
          } catch (_) {}
        }
      });
    }

    // REST Polling fallback for Answer
    Timer.periodic(const Duration(milliseconds: 600), (timer) async {
      if (answered) {
        timer.cancel();
        return;
      }
      try {
        final url = Uri.parse('$_activeRtdbUrl/camera_signaling/$cameraDeviceId/answer_$viewerDeviceId.json');
        final response = await http.get(url);
        if (response.statusCode == 200 && response.body != 'null' && !answered) {
          final data = jsonDecode(response.body);
          if (data is Map && data['answer'] != null) {
            answered = true;
            timer.cancel();
            onAnswer(Map<String, dynamic>.from(data['answer'] as Map));
          }
        }
      } catch (_) {}
    });

    return sub;
  }

  /// Send ICE candidate for camera signaling
  Future<void> sendCameraIceCandidate({
    required String cameraDeviceId,
    required String senderDeviceId,
    required String targetRole, // 'station' or 'viewer_$viewerId'
    required Map<String, dynamic> candidate,
  }) async {
    if (cameraDeviceId.trim().isEmpty) return;

    if (_dbRef != null) {
      try {
        await _dbRef!
            .child('camera_ice')
            .child(cameraDeviceId)
            .child(targetRole)
            .push()
            .set(candidate);
      } catch (_) {}
    }

    try {
      final path = 'camera_ice/$cameraDeviceId/$targetRole';
      final url = Uri.parse('$_activeRtdbUrl/$path.json');
      await http.post(url, body: jsonEncode(candidate));
    } catch (e) {
      debugPrint('⚠️ [CAMERA ICE SEND ERROR]: $e');
    }
  }

  /// Listen for ICE candidates
  StreamSubscription? listenCameraIceCandidates({
    required String cameraDeviceId,
    required String role, // 'station' or 'viewer_$viewerId'
    required Function(Map<String, dynamic> candidate) onCandidate,
  }) {
    if (cameraDeviceId.trim().isEmpty) return null;

    final Set<String> processedCandidates = {};

    StreamSubscription? sub;
    if (_dbRef != null) {
      sub = _dbRef!
          .child('camera_ice')
          .child(cameraDeviceId)
          .child(role)
          .onChildAdded
          .listen((event) {
        if (event.snapshot.value != null) {
          try {
            final key = event.snapshot.key ?? '';
            if (key.isNotEmpty && processedCandidates.contains(key)) return;
            if (key.isNotEmpty) processedCandidates.add(key);
            final data = Map<String, dynamic>.from(event.snapshot.value as Map);
            onCandidate(data);
          } catch (_) {}
        }
      });
    }

    // REST polling fallback for ICE candidates
    Timer.periodic(const Duration(milliseconds: 700), (timer) async {
      try {
        final url = Uri.parse('$_activeRtdbUrl/camera_ice/$cameraDeviceId/$role.json');
        final response = await http.get(url);
        if (response.statusCode == 200 && response.body != 'null') {
          final data = jsonDecode(response.body);
          if (data is Map) {
            data.forEach((key, val) {
              final k = key.toString();
              if (!processedCandidates.contains(k) && val is Map) {
                processedCandidates.add(k);
                onCandidate(Map<String, dynamic>.from(val));
              }
            });
          }
        }
      } catch (_) {}
    });

    return sub;
  }

  /// Clean up camera signaling data
  Future<void> cleanupCameraSignaling({
    required String cameraDeviceId,
  }) async {
    if (cameraDeviceId.trim().isEmpty) return;
    if (_dbRef != null) {
      try {
        await _dbRef!.child('camera_signaling').child(cameraDeviceId).remove();
        await _dbRef!.child('camera_ice').child(cameraDeviceId).remove();
      } catch (_) {}
    }
    try {
      final sigUrl = Uri.parse('$_activeRtdbUrl/camera_signaling/$cameraDeviceId.json');
      await http.delete(sigUrl);
      final iceUrl = Uri.parse('$_activeRtdbUrl/camera_ice/$cameraDeviceId.json');
      await http.delete(iceUrl);
    } catch (_) {}
  }

  /// Clean up only viewer-specific signaling data (answer + viewer ICE)
  /// Does NOT remove the camera station's listeners or other viewers
  Future<void> cleanupViewerSignaling({
    required String cameraDeviceId,
    required String viewerDeviceId,
  }) async {
    if (cameraDeviceId.trim().isEmpty || viewerDeviceId.trim().isEmpty) return;

    // Remove old answer, viewer offer, and per-viewer ICE paths
    if (_dbRef != null) {
      try {
        await _dbRef!.child('camera_signaling').child(cameraDeviceId).child('answer_$viewerDeviceId').remove();
        await _dbRef!.child('camera_signaling').child(cameraDeviceId).child('viewers').child(viewerDeviceId).remove();
        await _dbRef!.child('camera_ice').child(cameraDeviceId).child('viewer_$viewerDeviceId').remove();
        await _dbRef!.child('camera_ice').child(cameraDeviceId).child('station_$viewerDeviceId').remove();
      } catch (_) {}
    }

    try {
      final ansUrl = Uri.parse('$_activeRtdbUrl/camera_signaling/$cameraDeviceId/answer_$viewerDeviceId.json');
      await http.delete(ansUrl);
      final viewUrl = Uri.parse('$_activeRtdbUrl/camera_signaling/$cameraDeviceId/viewers/$viewerDeviceId.json');
      await http.delete(viewUrl);
      final iceUrl = Uri.parse('$_activeRtdbUrl/camera_ice/$cameraDeviceId/viewer_$viewerDeviceId.json');
      await http.delete(iceUrl);
      final stationIceUrl = Uri.parse('$_activeRtdbUrl/camera_ice/$cameraDeviceId/station_$viewerDeviceId.json');
      await http.delete(stationIceUrl);
    } catch (_) {}

    debugPrint('🧹 [SIGNALING] Cleaned viewer-specific data: camera=$cameraDeviceId, viewer=$viewerDeviceId');
  }

  // --- TALK LOCK ---

  Future<void> updateCameraTalkLock({
    required String familyPin,
    required String cameraDeviceId,
    required String? talkerDeviceId,
    required String? talkerDeviceName,
  }) async {
    if (familyPin.trim().isEmpty || cameraDeviceId.trim().isEmpty) return;
    try {
      final url = Uri.parse('$_activeRtdbUrl/family_cameras/$familyPin/$cameraDeviceId/talkLock.json');
      if (talkerDeviceId != null) {
        final payload = {
          'talkerDeviceId': talkerDeviceId,
          'talkerDeviceName': talkerDeviceName ?? 'Biri',
          'timestamp': DateTime.now().millisecondsSinceEpoch,
        };
        await http.put(url, body: jsonEncode(payload));
      } else {
        await http.delete(url);
      }
    } catch (e) {
      debugPrint('⚠️ [TALK LOCK ERROR]: $e');
    }
  }

  /// Returns a StreamSubscription so the caller can cancel it in dispose()
  StreamSubscription? listenCameraTalkLock(
    String familyPin,
    String cameraDeviceId,
    Function(Map<String, dynamic>?) onLockChange,
  ) {
    if (familyPin.trim().isEmpty || cameraDeviceId.trim().isEmpty) return null;
    if (_dbRef == null) return null;

    return _dbRef!
        .child('family_cameras')
        .child(familyPin)
        .child(cameraDeviceId)
        .child('talkLock')
        .onValue
        .listen((event) {
      if (event.snapshot.value != null) {
        try {
          final data = Map<String, dynamic>.from(event.snapshot.value as Map);
          onLockChange(data);
        } catch (_) {
          onLockChange(null);
        }
      } else {
        onLockChange(null);
      }
    });
  }

  // --- CAMERA MOTION ALERTS ---

  final List<StreamSubscription> _motionAlertSubscriptions = [];

  /// Send camera motion alert event to all target family RTDB nodes
  Future<void> sendCameraMotionEvent({
    required String familyPin,
    required String cameraDeviceId,
    required String cameraDeviceName,
    List<String>? fallbackPins,
    String? snapshotBase64,
  }) async {
    final targets = <String>{familyPin, ...?fallbackPins}.where((p) => p.trim().isNotEmpty).toList();
    if (targets.isEmpty || cameraDeviceId.trim().isEmpty) return;

    final payload = {
      'type': 'motion_detected',
      'cameraDeviceId': cameraDeviceId,
      'cameraDeviceName': cameraDeviceName,
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      if (snapshotBase64 != null) 'snapshotBase64': snapshotBase64,
    };

    for (final pin in targets) {
      if (_dbRef != null) {
        try {
          await _dbRef!
              .child('camera_motion_alerts')
              .child(pin)
              .set(payload);
          debugPrint('✅ [MOTION SIGNAL SENT] Camera $cameraDeviceName to pin $pin');
        } catch (e) {
          debugPrint('⚠️ [MOTION SIGNAL WARN for $pin]: $e');
        }
      }

      try {
        final url = Uri.parse('$_activeRtdbUrl/camera_motion_alerts/$pin.json');
        await http.put(url, body: jsonEncode(payload));
      } catch (e) {
        debugPrint('⚠️ [MOTION SIGNAL HTTP ERROR for $pin]: $e');
      }

      // Dispatch high-priority background push
      try {
        await NotificationService().sendCameraMotionPushNotification(
          targetDeviceId: pin,
          cameraName: cameraDeviceName,
        );
      } catch (_) {}
    }
  }

  /// Listen for camera motion alert events across all family group pins
  void listenCameraMotionAlerts({
    required List<String> pins,
    required Function(Map<String, dynamic> alertData) onMotionAlert,
  }) {
    for (final sub in _motionAlertSubscriptions) {
      sub.cancel();
    }
    _motionAlertSubscriptions.clear();

    final validPins = pins.where((p) => p.trim().isNotEmpty).toSet();
    if (validPins.isEmpty || _dbRef == null) return;

    for (final pin in validPins) {
      debugPrint('👂 [MOTION LISTENER] Listening on camera_motion_alerts/$pin');
      final sub = _dbRef!
          .child('camera_motion_alerts')
          .child(pin)
          .onValue
          .listen((event) {
        if (event.snapshot.value != null) {
          try {
            final data = Map<String, dynamic>.from(event.snapshot.value as Map);
            onMotionAlert(data);
          } catch (e) {
            debugPrint('⚠️ [MOTION PARSE ERROR for $pin]: $e');
          }
        }
      });
      _motionAlertSubscriptions.add(sub);
    }
  }
}

