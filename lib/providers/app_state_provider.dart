import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../models/user_profile.dart';
import '../models/chat_message.dart';
import '../models/call_session.dart';
import '../models/call_log.dart';
import '../services/local_storage_service.dart';
import '../services/security_service.dart';
import '../services/signaling_service.dart';
import '../services/webrtc_service.dart';
import '../services/audio_ringtone_service.dart';
import '../services/notification_service.dart';

class AppStateProvider extends ChangeNotifier {
  UserProfile? myProfile;
  UserProfile? pairedProfile; // Currently active target profile
  List<UserProfile> pairedDevicesList = []; // Multi-device support list
  UserProfile? pendingPairRequest; // Pending incoming pair request

  List<String> blockedDeviceIds = [];
  List<String> sentPairRequests = [];
  String? lastNotificationMessage;

  // Interactive flow state
  String? generatedPairPin;
  String? createdContactName;
  bool isPhoneEnteredCode = false;

  CallSession? activeCall;
  DateTime? _callConnectedTime;
  List<CallLog> callHistory = [];
  List<ChatMessage> chatHistory = [];
  List<ChatMessage> groupChatHistory = [];
  int groupUnreadCount = 0;
  bool isGroupChatActive = false;
  String? activeChatPartnerId;
  bool isPeerTyping = false;
  Timer? _typingTimeoutTimer;
  int _lastTypingTimestamp = 0;
  bool _typingCooldownActive = false;
  Timer? _typingCooldownTimer;

  /// Set for deduplicating incoming messages across multiple listener targets and polling
  final Set<String> _processedMessageKeys = {};

  String? favoriteDeviceId;

  void toggleFavoriteDevice(String deviceId) {
    if (favoriteDeviceId == deviceId) {
      favoriteDeviceId = null;
    } else {
      favoriteDeviceId = deviceId;
    }
    LocalStorageService.saveFavoriteDeviceId(favoriteDeviceId);
    notifyListeners();
  }

  UserProfile? get favoriteDevice {
    if (favoriteDeviceId == null) return null;
    try {
      return pairedDevicesList.firstWhere((d) => d.id == favoriteDeviceId);
    } catch (_) {
      return null;
    }
  }

  void setActiveChatPartner(String? partnerId) {
    activeChatPartnerId = partnerId;
    if (partnerId != null) {
      markMessagesAsRead(partnerId);
    }
  }

  void sendTypingStatus(bool isTyping) {
    if (myProfile != null && pairedProfile != null) {
      _signalingService.sendTypingStatus(myProfile!.id, pairedProfile!.id, isTyping);
    }
  }

  /// Deterministic shared group channel PIN so all paired devices calculate the exact same group key
  String get familyGroupPin {
    if (myProfile == null) return 'global_family';
    final myPin = myProfile!.pairCode.isNotEmpty
        ? myProfile!.pairCode
        : myProfile!.id.split('_').last;

    final pins = <String>{myPin};
    for (final device in pairedDevicesList) {
      final pin = device.pairCode.isNotEmpty
          ? device.pairCode
          : device.id.split('_').last;
      if (pin.isNotEmpty) pins.add(pin);
    }

    final sortedPins = pins.toList()..sort();
    return sortedPins.join('_');
  }

  /// Check if two device IDs refer to the same device (flexible matching via pairCode suffix)
  bool _isSameDevice(String id1, String id2) {
    if (id1 == id2) return true;
    final pin1 = id1.split('_').last;
    final pin2 = id2.split('_').last;
    return pin1 == pin2 && pin1.isNotEmpty;
  }

  /// Total unread messages from active paired contacts and Family Group
  int get totalUnreadCount {
    if (myProfile == null) return 0;
    int count = groupUnreadCount;
    for (final device in pairedDevicesList) {
      if (device.id != myProfile!.id) {
        count += unreadCountFrom(device.id);
      }
    }
    return count;
  }

  /// Unread message count from a specific sender
  int unreadCountFrom(String senderId) {
    if (myProfile != null && (senderId == myProfile!.id || _isSameDevice(senderId, myProfile!.id))) {
      return 0;
    }
    final targetPin = senderId.split('_').last;
    return chatHistory.where((m) {
      if (m.senderId == myProfile?.id) return false;
      if (m.text.contains('HAREKET ALGILANDI')) return false;
      final isMatch = _isSameDevice(m.senderId, senderId) || m.senderId.endsWith(targetPin);
      return isMatch && !m.isRead;
    }).length;
  }

  /// Strictly isolate and return ONLY the messages exchanged with a specific contact/device
  List<ChatMessage> getMessagesForContact(String contactId, [String? contactPin]) {
    final cleanContactPin = (contactPin != null && contactPin.isNotEmpty)
        ? contactPin
        : contactId.split('_').last;
    final myPin = myProfile?.pairCode.isNotEmpty == true
        ? myProfile!.pairCode
        : (myProfile?.id.split('_').last ?? '');
    final myId = myProfile?.id ?? '';

    return chatHistory.where((m) {
      // Exclude legacy motion alerts or system messages from normal chat display
      if (m.text.contains('HAREKET ALGILANDI')) return false;

      final senderPin = m.senderId.split('_').last;
      final receiverPin = m.receiverId.split('_').last;

      final isFromContact = m.senderId == contactId ||
          (cleanContactPin.isNotEmpty && senderPin == cleanContactPin);
      final isToContact = m.receiverId == contactId ||
          (cleanContactPin.isNotEmpty && receiverPin == cleanContactPin);

      final isFromMe = m.senderId == myId ||
          (myPin.isNotEmpty && senderPin == myPin);
      final isToMe = m.receiverId == myId ||
          (myPin.isNotEmpty && receiverPin == myPin);

      // Match 1-on-1 dialogue between me and this contact
      return (isFromContact && isToMe) ||
             (isFromMe && isToContact) ||
             (isFromContact && (m.receiverId.isEmpty || m.receiverId == 'direct')) ||
             (isToContact && (m.senderId.isEmpty || m.senderId == 'direct'));
    }).toList();
  }

  final WebRTCService webRTCService = WebRTCService();
  final SignalingService _signalingService = SignalingService();
  Timer? _callTimeoutTimer;

  bool isInitializing = true;

  /// Completely deduplicates pairedDevicesList by ID, pairCode, phone number, and email.
  void _deduplicatePairedDevices() {
    final Map<String, UserProfile> uniqueMap = {};
    for (final d in pairedDevicesList) {
      if (myProfile != null &&
          (d.id == myProfile!.id ||
              _isSameDevice(d.id, myProfile!.id) ||
              (d.pairCode.isNotEmpty && d.pairCode == myProfile!.pairCode))) {
        continue;
      }
      final key = d.pairCode.isNotEmpty
          ? d.pairCode
          : (d.phoneNumber?.isNotEmpty == true
              ? d.phoneNumber!
              : (d.email?.isNotEmpty == true
                  ? d.email!
                  : d.id.split('_').last));

      if (!uniqueMap.containsKey(key)) {
        uniqueMap[key] = d;
      } else {
        final existing = uniqueMap[key]!;
        if ((existing.deviceName.startsWith('Cihaz ') ||
                existing.deviceName == 'Yeni Ebeveyn Telefonu' ||
                existing.deviceName == 'OMEGA Cihazı') &&
            !d.deviceName.startsWith('Cihaz ') &&
            d.deviceName.isNotEmpty) {
          uniqueMap[key] = d;
        }
      }
    }
    pairedDevicesList = uniqueMap.values.toList();
    if (pairedProfile != null) {
      final matching = pairedDevicesList.firstWhere(
        (d) =>
            d.id == pairedProfile!.id ||
            _isSameDevice(d.id, pairedProfile!.id) ||
            (d.pairCode.isNotEmpty && d.pairCode == pairedProfile!.pairCode),
        orElse: () => pairedDevicesList.isNotEmpty
            ? pairedDevicesList.first
            : pairedProfile!,
      );
      pairedProfile = matching;
    }
  }

  /// Safely adds a device to pairedDevicesList, removing any existing matches first.
  bool _addPairedDeviceSafe(UserProfile device) {
    if (myProfile != null &&
        (device.id == myProfile!.id ||
            _isSameDevice(device.id, myProfile!.id) ||
            (device.pairCode.isNotEmpty &&
                device.pairCode == myProfile!.pairCode))) {
      return false;
    }
    final pin = device.pairCode.isNotEmpty
        ? device.pairCode
        : device.id.split('_').last;

    pairedDevicesList.removeWhere((d) =>
        d.id == device.id ||
        _isSameDevice(d.id, device.id) ||
        (pin.isNotEmpty &&
            (d.pairCode == pin ||
                d.id.endsWith('_$pin') ||
                device.id.endsWith('_${d.pairCode}'))) ||
        (device.phoneNumber != null &&
            device.phoneNumber!.isNotEmpty &&
            d.phoneNumber == device.phoneNumber) ||
        (device.email != null &&
            device.email!.isNotEmpty &&
            d.email == device.email));

    pairedDevicesList.add(device);
    _deduplicatePairedDevices();
    return true;
  }

  Future<void> initializeApp() async {
    await LocalStorageService.init();
    await webRTCService.initRenderers();

    myProfile = LocalStorageService.getUserProfile();
    pairedProfile = LocalStorageService.getPairedDevice();
    pairedDevicesList = LocalStorageService.getPairedDevicesList();
    _deduplicatePairedDevices();
    await LocalStorageService.savePairedDevicesList(pairedDevicesList);

    chatHistory = LocalStorageService.getChatHistory();
    groupChatHistory = LocalStorageService.getGroupChatHistory();
    callHistory = LocalStorageService.getCallLogs();
    blockedDeviceIds = LocalStorageService.getBlockedDevices();
    sentPairRequests = LocalStorageService.getSentPairRequests();
    approvedPairHistory = LocalStorageService.getApprovedPairHistory();
    favoriteDeviceId = LocalStorageService.getFavoriteDeviceId();

    // Clean up any legacy test motion alert messages from chat history
    chatHistory.removeWhere((m) {
      if (m.text.contains('HAREKET ALGILANDI')) {
        LocalStorageService.deleteChatMessage(m.id);
        return true;
      }
      return false;
    });

    if (myProfile != null) {
      pairedDevicesList.removeWhere((d) => d.id == myProfile!.id);
      _deduplicatePairedDevices();
      if (pairedProfile != null && pairedProfile!.id == myProfile!.id) {
        pairedProfile = pairedDevicesList.isNotEmpty ? pairedDevicesList.first : null;
      }

      _updateSignalingListenTargets();

      if (pendingPairRequest != null &&
          pairedDevicesList.any((d) => d.id == pendingPairRequest!.id || d.pairCode == pendingPairRequest!.pairCode)) {
        pendingPairRequest = null;
      }

      // Clean up own messages in chat history storage so they are never marked unread
      final myPin = myProfile?.id.split('_').last ?? '';
      for (int i = 0; i < chatHistory.length; i++) {
        final m = chatHistory[i];
        final isOwn = myProfile != null && (m.senderId == myProfile!.id || (myPin.isNotEmpty && m.senderId.endsWith(myPin)));
        if (!m.isRead && isOwn) {
          final updated = m.copyWith(isRead: true);
          chatHistory[i] = updated;
          LocalStorageService.saveChatMessage(updated);
        }
      }

      await _signalingService.init(myProfile!.id);
      await NotificationService().init(myProfile!.id);
      NotificationService().onCallkitAccept = (callId) async {
        if (activeCall != null && activeCall!.status == CallStatus.ringing) {
          await acceptCall();
        }
      };
      NotificationService().onCallkitDecline = (callId) async {
        if (activeCall != null && activeCall!.status == CallStatus.ringing) {
          await rejectCall();
        }
      };
      NotificationService().onCallkitEnded = (callId) async {
        if (activeCall != null) {
          await endCall();
        }
      };
      _setupSignalingListeners();
      _updateSignalingListenTargets();
      startListeningFamilyCameras();
      _listenForSentPairRequestResponses();

      // Fetch all paired devices' profile photos from Firebase
      fetchAllPairedPhotos();
    }

    isInitializing = false;
    notifyListeners();
  }

  Future<void> removePairedDevice(String deviceId) async {
    final target = pairedDevicesList.firstWhere(
      (d) => d.id == deviceId,
      orElse: () => UserProfile(
        id: deviceId,
        deviceName: 'Cihaz',
        role: DeviceRole.parent,
        pairCode: deviceId.split('_').last,
        lastSeen: DateTime.now(),
      ),
    );

    pairedDevicesList.removeWhere((d) => d.id == deviceId);
    approvedPairHistory.removeWhere((d) => d.id == deviceId);

    if (pairedProfile?.id == deviceId) {
      pairedProfile = pairedDevicesList.isNotEmpty ? pairedDevicesList.first : null;
      if (pairedProfile != null) {
        await LocalStorageService.savePairedDevice(pairedProfile!);
      } else {
        await LocalStorageService.savePairedDevice(
          UserProfile(
            id: 'dummy',
            deviceName: '',
            role: DeviceRole.parent,
            pairCode: '',
            pairedDeviceId: '',
            lastSeen: DateTime.now(),
          ),
        );
      }
    }
    await LocalStorageService.savePairedDevicesList(pairedDevicesList);

    if (myProfile != null) {
      await _signalingService.unpairDevice(
        target.pairCode,
        myProfile!.id,
        myProfile!.pairCode,
        targetDeviceId: target.id,
      );
    }

    lastNotificationMessage = '${target.deviceName} rehberinizden ve eşleşmelerden çıkarıldı.';
    notifyListeners();
  }

  void clearSampleTestDevices() {
    pairedDevicesList.removeWhere((d) => d.id.startsWith('test_') || d.id.startsWith('sample_'));
    notifyListeners();
  }



  void selectActiveDevice(UserProfile device) async {
    pairedProfile = device;
    await LocalStorageService.savePairedDevice(device);
    notifyListeners();
  }

  Future<void> renamePairedDevice(String deviceId, String newName) async {
    final index = pairedDevicesList.indexWhere((d) => d.id == deviceId);
    if (index != -1) {
      final updated = pairedDevicesList[index].copyWith(deviceName: newName);
      pairedDevicesList[index] = updated;
      if (pairedProfile?.id == deviceId) {
        pairedProfile = updated;
        await LocalStorageService.savePairedDevice(updated);
      }
      await LocalStorageService.savePairedDevicesList(pairedDevicesList);
      notifyListeners();
    }
  }

  // --- Unique Contact Code Generation & Mutual Approval Flow ---

  bool isPendingBannerDismissed = false;
  List<UserProfile> approvedPairHistory = [];

  Future<String> generateUniqueCodeForContact(String contactName) async {
    final pin = SecurityService.generatePairPin();
    generatedPairPin = pin;
    createdContactName = contactName.trim().isEmpty ? 'Annem' : contactName.trim();
    isPhoneEnteredCode = false;

    final myDeviceId = myProfile?.id ?? 'omega_tablet_$pin';
    await _signalingService.registerTabletPair(pin, myDeviceId, createdContactName!);

    _signalingService.listenTabletPairing(
      pin,
      onPendingApproval: (data) {
        isPhoneEnteredCode = true;
        notifyListeners();
      },
      onPaired: (data) async {
        isPhoneEnteredCode = true;
        notifyListeners();
      },
    );

    notifyListeners();
    return pin;
  }

  Future<void> confirmAndSaveCreatedContact() async {
    if (generatedPairPin == null || createdContactName == null) return;

    final pin = generatedPairPin!;
    final name = createdContactName!;
    final targetParentId = 'omega_parent_$pin';
    final myDeviceId = myProfile?.id ?? 'omega_tablet_$pin';

    final newContact = UserProfile(
      id: targetParentId,
      deviceName: name,
      role: DeviceRole.parent,
      pairCode: pin,
      pairedDeviceId: myDeviceId,
      avatarIcon: 'parent',
      isOnline: true,
      lastSeen: DateTime.now(),
    );

    pairedProfile = newContact;
    _addPairedDeviceSafe(newContact);

    await LocalStorageService.savePairedDevice(newContact);
    await LocalStorageService.savePairedDevicesList(pairedDevicesList);

    // Send mutual approval status to Firebase (with real device name)
    await _signalingService.approvePairing(
      pin, myDeviceId, name,
      senderRealName: myProfile?.deviceName,
    );

    generatedPairPin = null;
    createdContactName = null;
    isPhoneEnteredCode = false;
    _updateSignalingListenTargets();

    notifyListeners();
  }

  void resetContactCreationFlow() {
    generatedPairPin = null;
    createdContactName = null;
    isPhoneEnteredCode = false;
    notifyListeners();
  }

  void minimizePendingPairBanner() {
    isPendingBannerDismissed = true;
    notifyListeners();
  }

  void acceptPendingPairRequest(String customLabel) async {
    if (pendingPairRequest != null) {
      final targetPairCode = pendingPairRequest!.pairCode;
      final updated = pendingPairRequest!.copyWith(
        deviceName: customLabel,
        isOnline: true,
        lastSeen: DateTime.now(),
      );
      
      pairedProfile = updated;
      
      _addPairedDeviceSafe(updated);

      if (!approvedPairHistory.any((d) => d.id == updated.id)) {
        approvedPairHistory.add(updated);
        await LocalStorageService.saveApprovedPairHistory(approvedPairHistory);
      }
      
      await LocalStorageService.savePairedDevice(updated);
      await LocalStorageService.savePairedDevicesList(pairedDevicesList);

      // Clean sentPairRequests if this device was in our sent list
      sentPairRequests.removeWhere((code) =>
          code == targetPairCode || code == updated.id);
      await LocalStorageService.saveSentPairRequests(sentPairRequests);

      final myListeningCode = myProfile?.pairCode ?? myProfile?.phoneNumber ?? myProfile?.email ?? '773223';
      final myRealName = myProfile?.deviceName ?? 'Omega Cihazı';

      // 1. Approve on my listening channel (e.g. 773223)
      await _signalingService.approvePairing(
        myListeningCode,
        myProfile?.id ?? 'omega_device_$myListeningCode',
        customLabel,
        senderRealName: myRealName,
      );

      // 2. Approve on sender's channel (e.g. 05317011121)
      if (targetPairCode.isNotEmpty && targetPairCode != myListeningCode) {
        await _signalingService.approvePairing(
          targetPairCode,
          myProfile?.id ?? 'omega_device_$myListeningCode',
          customLabel,
          senderRealName: myRealName,
        );
      }

      pendingPairRequest = null;
      isPendingBannerDismissed = false;
      _updateSignalingListenTargets();
      notifyListeners();
    }
  }

  void dismissPendingPairRequest() {
    pendingPairRequest = null;
    isPendingBannerDismissed = false;
    notifyListeners();
  }

  void _setupSignalingListeners() {
    _signalingService.onIncomingCall = (session) async {
      if (session.callerId == myProfile?.id) return;
      if (activeCall != null && activeCall!.callId == session.callId) return;

      // 🛡️ LINE BUSY AUTO-REJECT GUARD:
      // If user is already talking or has an ongoing call, DO NOT interrupt!
      final isBusy = activeCall != null &&
          (activeCall!.status == CallStatus.connected ||
           activeCall!.status == CallStatus.calling ||
           activeCall!.status == CallStatus.ringing);

      if (isBusy) {
        debugPrint('🛡️ [CALL BUSY] Device is busy in call ${activeCall!.callId}. Auto-rejecting incoming call ${session.callId} from ${session.callerName}');
        // 1. Auto-reject specifically back to the 3rd caller with 'busy' status
        await _signalingService.rejectCall(session.callerId, session.callId, 'busy');
        // 2. Silently record missed call in call history
        await _recordMissedCallLogFromSession(session);
        // 3. Gentle in-call notification banner (without interrupting WebRTC or screen)
        lastNotificationMessage = '⚠️ ${session.callerName} aradı (Cihaz Meşgul)';
        notifyListeners();
        return;
      }

      final callerPin = session.callerId.split('_').last;
      final matchedContact = pairedDevicesList.firstWhere(
        (d) => d.id == session.callerId || d.pairCode == callerPin,
        orElse: () => UserProfile(
          id: session.callerId,
          deviceName: session.callerName,
          role: DeviceRole.parent,
          pairCode: callerPin,
          pairedDeviceId: myProfile?.id ?? '',
          lastSeen: DateTime.now(),
        ),
      );
      pairedProfile = matchedContact;
      activeCall = session.copyWith(status: CallStatus.ringing);
      AudioRingtoneService().playRingtone();
      notifyListeners();

      // CRITICAL FIX: Safety timeout for incoming calls
      final ringingCallId = session.callId;
      _callTimeoutTimer?.cancel();
      _callTimeoutTimer = Timer(const Duration(seconds: 35), () {
        if (activeCall != null &&
            activeCall!.callId == ringingCallId &&
            activeCall!.status == CallStatus.ringing) {
          AudioRingtoneService().stopAll();
          NotificationService().stopIncomingCallUI();
          NotificationService().showMissedCallNotification(
            callerName: session.callerName,
            isVideo: session.type == CallType.video,
          );
          activeCall = null;
          webRTCService.dispose();
          lastNotificationMessage = 'Cevapsız arama.';
          notifyListeners();
        }
      });
    };

    _signalingService.onCallAnswer = (sdpAnswer) async {
      // Guard: only process answer ONCE, and only for the CURRENT call
      if (activeCall == null || activeCall!.status == CallStatus.connected) return;
      // The answer came from polling - verify it's not stale by checking status
      if (activeCall!.status != CallStatus.calling) return;
      _callTimeoutTimer?.cancel();
      AudioRingtoneService().stopAll();
      NotificationService().stopIncomingCallUI();
      _callConnectedTime = DateTime.now();
      activeCall = activeCall!.copyWith(status: CallStatus.connected);
      notifyListeners();
      try {
        await webRTCService.setRemoteAnswer(sdpAnswer);
      } catch (e) {
        debugPrint('⚠️ [WEBRTC ANSWER WARN]: $e');
      }
    };

    _signalingService.onCallRejected = (callId) async {
      if (activeCall != null && callId == activeCall!.callId) {
        _callTimeoutTimer?.cancel();
        NotificationService().stopIncomingCallUI();
        _recordCallLog(direction: CallDirection.outgoing, customDurationSeconds: 0);
        lastNotificationMessage = '⚠️ Cihaz Meşgul / Başka Görüşmede';
        
        // Update status so CallScreen shows "Başka Bir Görüşmede (Meşgul)" text
        activeCall = activeCall!.copyWith(status: CallStatus.busy);
        notifyListeners();

        // Play custom "başka kişiyle görüşüyor" announcement sound and WAIT for it to finish
        await AudioRingtoneService().playUserBusySound();

        // Now dismiss the call screen
        activeCall = null;
        webRTCService.dispose();
        notifyListeners();
      }
    };

    _signalingService.onCallEnded = (callId) async {
      if (activeCall != null && callId == activeCall!.callId) {
        _callTimeoutTimer?.cancel();
        NotificationService().stopIncomingCallUI();
        final isConnected = activeCall!.status == CallStatus.connected;
        final isCallerMe = myProfile != null && activeCall!.callerId == myProfile!.id;
        final direction = isConnected
            ? (isCallerMe ? CallDirection.outgoing : CallDirection.incoming)
            : (isCallerMe ? CallDirection.outgoing : CallDirection.missed);
        _recordCallLog(direction: direction);

        // Normal end call / peer ended: NO MP3 sound plays on either side (like a normal phone)
        await AudioRingtoneService().stopAll();

        // Dismiss call screen immediately
        activeCall = null;
        webRTCService.dispose();
        notifyListeners();
      }
    };

    webRTCService.onPeerDisconnected = () {
      endCall();
    };

    webRTCService.onTrackReceived = () {
      notifyListeners();
    };

    _signalingService.onIceCandidate = (candidate) async {
      await webRTCService.addCandidate(candidate);
    };

    _signalingService.onChatMessageReceived = (message) async {
      // 1. Strict Deduplication: check by message ID or content fingerprint
      final fingerprint = '${message.senderId}_${message.text}_${message.timestamp.millisecondsSinceEpoch}';
      if ((message.id.isNotEmpty && _processedMessageKeys.contains(message.id)) ||
          _processedMessageKeys.contains(fingerprint) ||
          (message.id.isNotEmpty && chatHistory.any((m) => m.id == message.id))) {
        // Message already processed from another target node/polling cycle - silently drop duplicate
        debugPrint('⚠️ [DEDUP] Dropping duplicate message ${message.id} ("${message.text}")');
        return;
      }

      // Mark message key as processed
      if (message.id.isNotEmpty) _processedMessageKeys.add(message.id);
      _processedMessageKeys.add(fingerprint);
      if (_processedMessageKeys.length > 200) {
        _processedMessageKeys.remove(_processedMessageKeys.first);
      }

      // Whenever ANY message arrives from peer, they are DEFINITELY not typing anymore
      if (pairedProfile != null && (message.senderId == pairedProfile!.id || message.senderId.endsWith(pairedProfile!.pairCode))) {
        _typingTimeoutTimer?.cancel();
        isPeerTyping = false;
        _typingCooldownActive = true;
        _typingCooldownTimer?.cancel();
        _typingCooldownTimer = Timer(const Duration(seconds: 2), () {
          _typingCooldownActive = false;
        });
      }

      final isCurrentlyViewingChat = activeChatPartnerId != null && _isSameDevice(activeChatPartnerId!, message.senderId);
      
      final receivedMessage = message.copyWith(
        id: message.id.isNotEmpty ? message.id : 'msg_${DateTime.now().microsecondsSinceEpoch}',
        isDelivered: true,
        isRead: isCurrentlyViewingChat,
      );

      chatHistory.add(receivedMessage);
      await LocalStorageService.saveChatMessage(receivedMessage);

      // Auto-reply with status update to sender ('read' if chat active, 'delivered' if not)
      final statusToReply = isCurrentlyViewingChat ? 'read' : 'delivered';
      _signalingService.sendMessageStatusUpdate(receivedMessage.senderId, receivedMessage.id, statusToReply);

      if (receivedMessage.text.contains('🔔 YÜKSEK İKAZ')) {
        AudioRingtoneService().playAlarm();
      }

      // Show local system notification (iOS/Android/macOS) if not currently viewing this chat
      if (!isCurrentlyViewingChat) {
        final senderDevice = pairedDevicesList.firstWhere(
          (d) => _isSameDevice(d.id, receivedMessage.senderId) || d.id.endsWith(receivedMessage.senderId.split('_').last),
          orElse: () => UserProfile(
            id: receivedMessage.senderId,
            deviceName: 'Bilinmeyen Cihaz',
            pairCode: '',
            role: DeviceRole.parent,
            lastSeen: DateTime.now(),
          ),
        );

        NotificationService().showMessageNotification(
          senderName: senderDevice.deviceName,
          messageText: receivedMessage.text,
        );
      }
      notifyListeners();
    };

    _signalingService.onGroupChatMessageReceived = (message) async {
      // System Action: Clear Group Chat Signal from Admin
      if (message.text == '__SYSTEM_CLEAR_GROUP_CHAT__') {
        groupChatHistory.clear();
        groupUnreadCount = 0;
        await LocalStorageService.clearGroupChatHistory();
        notifyListeners();
        return;
      }

      final existingIndex = groupChatHistory.indexWhere((m) => m.id == message.id && message.id.isNotEmpty);
      if (existingIndex != -1) {
        groupChatHistory[existingIndex] = message;
        await LocalStorageService.saveGroupChatMessage(message);
        notifyListeners();
        return;
      }

      final fingerprint = 'group_${message.senderId}_${message.text}_${message.timestamp.millisecondsSinceEpoch}';
      if ((message.id.isNotEmpty && _processedMessageKeys.contains(message.id)) ||
          _processedMessageKeys.contains(fingerprint)) {
        return;
      }

      if (myProfile != null && (message.senderId == myProfile!.id || _isSameDevice(message.senderId, myProfile!.id))) {
        return;
      }

      if (message.id.isNotEmpty) _processedMessageKeys.add(message.id);
      _processedMessageKeys.add(fingerprint);

      final receivedMessage = message.copyWith(
        id: message.id.isNotEmpty ? message.id : 'group_msg_${DateTime.now().microsecondsSinceEpoch}',
        isDelivered: true,
        isRead: isGroupChatActive,
      );

      groupChatHistory.add(receivedMessage);
      await LocalStorageService.saveGroupChatMessage(receivedMessage);

      if (receivedMessage.text.contains('🔔 YÜKSEK İKAZ')) {
        AudioRingtoneService().playAlarm();
      }

      if (!isGroupChatActive) {
        groupUnreadCount++;
        final author = receivedMessage.senderName ?? 'Aile Üyesi';
        NotificationService().showMessageNotification(
          senderName: '👨‍👩‍👧‍👦 Aile Odası ($author)',
          messageText: receivedMessage.text,
        );
      }
      notifyListeners();
    };

    _signalingService.onMessageStatusUpdated = (messageId, status) async {
      final idx = chatHistory.indexWhere((m) => m.id == messageId);
      if (idx != -1) {
        final currentMsg = chatHistory[idx];
        final updatedMsg = currentMsg.copyWith(
          isDelivered: (status == 'delivered' || status == 'read') ? true : currentMsg.isDelivered,
          isRead: status == 'read' ? true : currentMsg.isRead,
        );
        chatHistory[idx] = updatedMsg;
        await LocalStorageService.saveChatMessage(updatedMsg);
        notifyListeners();
      }
    };

    _signalingService.onTypingStatusChanged = (senderId, isTyping, timestampMs) {
      // Ignore empty senderId (comes from null/deleted nodes)
      if (senderId.isEmpty) return;
      // Ignore own typing events
      if (myProfile != null && (senderId == myProfile!.id || senderId.endsWith(myProfile!.pairCode))) return;

      final now = DateTime.now().millisecondsSinceEpoch;

      // Drop stale packets (>3500ms old)
      if (now - timestampMs > 3500) {
        isTyping = false;
      }

      // Deduplicate: if we already processed this exact timestamp, skip
      if (timestampMs > 0 && timestampMs == _lastTypingTimestamp && isTyping) {
        return;
      }

      // If cooldown is active (message just arrived), block any "true" signals
      if (_typingCooldownActive && isTyping) {
        return;
      }

      _typingTimeoutTimer?.cancel();

      if (isTyping) {
        _lastTypingTimestamp = timestampMs;
        if (!isPeerTyping) {
          isPeerTyping = true;
          notifyListeners();
        }
        _typingTimeoutTimer = Timer(const Duration(milliseconds: 2500), () {
          if (isPeerTyping) {
            isPeerTyping = false;
            _lastTypingTimestamp = 0;
            notifyListeners();
          }
        });
      } else {
        if (isPeerTyping) {
          isPeerTyping = false;
          _lastTypingTimestamp = 0;
          notifyListeners();
        }
      }
    };

    if (myProfile != null) {
      final codesToListen = <String>{};
      if (myProfile!.pairCode.isNotEmpty) codesToListen.add(myProfile!.pairCode);
      if (myProfile!.phoneNumber?.isNotEmpty == true) codesToListen.add(myProfile!.phoneNumber!.replaceAll(' ', ''));
      if (myProfile!.email?.isNotEmpty == true) codesToListen.add(myProfile!.email!.trim());

      for (final codeToListen in codesToListen) {
        _signalingService.listenTabletPairing(
          codeToListen,
          onPendingApproval: (data) {
            final parentId = data['parentId'] ?? 'omega_device_req';
            final rawName = data['parentName'] as String? ?? '';
            final parentPairCode = data['parentPairCode'] as String? ?? parentId.split('_').last;

            final String resolvedName = (rawName.trim().isNotEmpty && rawName != 'Yeni Ebeveyn Telefonu' && rawName != 'OMEGA Cihazı' && rawName != 'Ebeveyn Telefonu')
                ? rawName.trim()
                : 'Cihaz $parentPairCode';

            // Guard 1: Do not accept pair requests from your exact same device ID
            if (parentId == myProfile?.id) return;

            // Guard 2: Ignore if device is blocked
            if (blockedDeviceIds.contains(parentId) || blockedDeviceIds.contains(parentPairCode)) return;

            // Guard 3: If device is ALREADY PAIRED, update name if generic and clear pending
            final existingIndex = pairedDevicesList.indexWhere(
              (d) => d.id == parentId || (parentPairCode.isNotEmpty && d.pairCode == parentPairCode),
            );
            if (existingIndex != -1) {
              final existingDev = pairedDevicesList[existingIndex];
              if (existingDev.deviceName == 'Yeni Ebeveyn Telefonu' || existingDev.deviceName == 'OMEGA Cihazı' || existingDev.deviceName == 'Ebeveyn Telefonu') {
                pairedDevicesList[existingIndex] = existingDev.copyWith(deviceName: resolvedName);
                if (pairedProfile?.id == existingDev.id) {
                  pairedProfile = pairedDevicesList[existingIndex];
                }
                LocalStorageService.savePairedDevicesList(pairedDevicesList);
              }
              if (pendingPairRequest?.id == parentId || pendingPairRequest?.pairCode == parentPairCode) {
                pendingPairRequest = null;
              }
              notifyListeners();
              return;
            }

            pendingPairRequest = UserProfile(
              id: parentId,
              deviceName: resolvedName,
              role: DeviceRole.parent,
              pairCode: parentPairCode,
              pairedDeviceId: myProfile?.id ?? '',
              lastSeen: DateTime.now(),
            );
            notifyListeners();
          },
          onPaired: (data) {
            final parentId = data['parentId'] as String? ?? '';
            final rawName = data['parentName'] as String? ?? '';
            final senderRealName = data['senderRealName'] as String? ?? '';
            final parentPairCode = data['parentPairCode'] as String? ?? parentId.split('_').last;

            // Prefer senderRealName (approver's actual device name), then parentName, then fallback
            final String resolvedName;
            if (senderRealName.trim().isNotEmpty && senderRealName != 'Yeni Ebeveyn Telefonu' && senderRealName != 'OMEGA Cihazı' && senderRealName != 'Ebeveyn Telefonu') {
              resolvedName = senderRealName.trim();
            } else if (rawName.trim().isNotEmpty && rawName != 'Yeni Ebeveyn Telefonu' && rawName != 'OMEGA Cihazı' && rawName != 'Ebeveyn Telefonu') {
              resolvedName = rawName.trim();
            } else {
              resolvedName = 'Cihaz $parentPairCode';
            }

            if (parentId.isNotEmpty && parentId != myProfile?.id && !blockedDeviceIds.contains(parentId)) {
              if (pendingPairRequest?.id == parentId || pendingPairRequest?.pairCode == parentPairCode) {
                pendingPairRequest = null;
              }

              // Clean sentPairRequests when pairing is confirmed
              if (sentPairRequests.contains(parentPairCode) || sentPairRequests.contains(parentId)) {
                sentPairRequests.removeWhere((code) => code == parentPairCode || code == parentId);
                LocalStorageService.saveSentPairRequests(sentPairRequests);
              }

              final existingIndex = pairedDevicesList.indexWhere((d) => d.id == parentId || d.pairCode == parentPairCode);
              if (existingIndex == -1) {
                final pairedDev = UserProfile(
                  id: parentId,
                  deviceName: resolvedName,
                  role: DeviceRole.parent,
                  pairCode: parentPairCode,
                  pairedDeviceId: myProfile?.id ?? '',
                  isOnline: true,
                  lastSeen: DateTime.now(),
                );
                if (_addPairedDeviceSafe(pairedDev)) {
                  if (pairedProfile == null) {
                    pairedProfile = pairedDev;
                    LocalStorageService.savePairedDevice(pairedDev);
                  }
                  LocalStorageService.savePairedDevicesList(pairedDevicesList);
                }
              } else {
                final existingDev = pairedDevicesList[existingIndex];
                if (existingDev.deviceName == 'Yeni Ebeveyn Telefonu' || existingDev.deviceName == 'OMEGA Cihazı' || existingDev.deviceName == 'Ebeveyn Telefonu' || existingDev.deviceName.startsWith('Cihaz ')) {
                  pairedDevicesList[existingIndex] = existingDev.copyWith(deviceName: resolvedName);
                  if (pairedProfile?.id == existingDev.id) {
                    pairedProfile = pairedDevicesList[existingIndex];
                    LocalStorageService.savePairedDevice(pairedProfile!);
                  }
                  LocalStorageService.savePairedDevicesList(pairedDevicesList);
                }
              }
              notifyListeners();
            }
          },
          onUnpaired: (data) {
            final unpairedBy = data['unpairedBy'] as String? ?? '';
            if (unpairedBy.isNotEmpty && unpairedBy != myProfile?.id) {
              final unpairedPin = unpairedBy.split('_').last;
              pairedDevicesList.removeWhere((d) =>
                  d.id == unpairedBy ||
                  d.pairCode == unpairedBy ||
                  (unpairedPin.isNotEmpty && d.pairCode == unpairedPin) ||
                  (unpairedPin.isNotEmpty && d.id.endsWith('_$unpairedPin')));
              approvedPairHistory.removeWhere((d) =>
                  d.id == unpairedBy ||
                  d.pairCode == unpairedBy ||
                  (unpairedPin.isNotEmpty && d.pairCode == unpairedPin) ||
                  (unpairedPin.isNotEmpty && d.id.endsWith('_$unpairedPin')));
              if (pairedProfile != null &&
                  (pairedProfile!.id == unpairedBy ||
                   pairedProfile!.pairCode == unpairedPin ||
                   pairedProfile!.id.endsWith('_$unpairedPin'))) {
                pairedProfile = pairedDevicesList.isNotEmpty ? pairedDevicesList.first : null;
              }
              LocalStorageService.savePairedDevicesList(pairedDevicesList);
              lastNotificationMessage = 'Bağlantı sonlandırıldı: Karşı cihaz eşleşmeyi çıkardı.';
              notifyListeners();
            }
          },
          onCancelled: (data) {
            final cancelledBy = data['cancelledBy'] as String? ?? '';
            if (pendingPairRequest?.id == cancelledBy || pendingPairRequest?.pairCode == cancelledBy) {
              pendingPairRequest = null;
              notifyListeners();
            }
          },
        );
      }
    }
  }

  Future<PairRequestResult> sendPairRequest(
      String targetCodeOrPhoneOrEmail, String parentId, String parentName) async {
    final targetClean = targetCodeOrPhoneOrEmail.trim().replaceAll(' ', '');
    if (targetClean.isEmpty) return PairRequestResult.error;

    if (myProfile != null) {
      // 1. Self-pairing guard check
      if (targetClean == myProfile!.id ||
          targetClean == myProfile!.pairCode ||
          (myProfile!.phoneNumber != null && targetClean == myProfile!.phoneNumber!.replaceAll(' ', '')) ||
          (myProfile!.email != null && targetClean == myProfile!.email!.trim())) {
        debugPrint('ℹ️ [SELF PAIR PREVENTED] Cannot send pair request to your exact device identity ($targetClean)');
        return PairRequestResult.selfPair;
      }

      // 2. Blocked devices check
      if (blockedDeviceIds.contains(targetClean)) {
        return PairRequestResult.blocked;
      }

      // 3. Already paired check
      final isAlreadyPaired = pairedDevicesList.any((d) =>
          d.id == targetClean ||
          d.pairCode == targetClean ||
          (d.phoneNumber != null && d.phoneNumber!.replaceAll(' ', '') == targetClean) ||
          (d.email != null && d.email!.trim() == targetClean));
      if (isAlreadyPaired) {
        return PairRequestResult.alreadyPaired;
      }

      // 4. Already pending sent request check
      if (sentPairRequests.contains(targetClean)) {
        return PairRequestResult.alreadyPending;
      }
    }

    final String actualSenderName = (myProfile?.deviceName != null && myProfile!.deviceName.trim().isNotEmpty)
        ? myProfile!.deviceName
        : parentName;

    await _signalingService.sendPairRequest(
      targetClean,
      parentId,
      actualSenderName,
      senderPairCode: myProfile?.pairCode ?? myProfile?.phoneNumber ?? myProfile?.email,
    );

    if (!sentPairRequests.contains(targetClean)) {
      sentPairRequests.add(targetClean);
      await LocalStorageService.saveSentPairRequests(sentPairRequests);
    }

    // ⚡ CRITICAL FIX: Listen on TARGET channel for paired/cancelled response
    // Without this, the sender never learns when the request is accepted.
    _signalingService.listenTabletPairing(
      targetClean,
      onPendingApproval: (_) {
        // Our own request reflected back, ignore
      },
      onPaired: (data) {
        final approverDeviceId = data['tabletId'] as String? ?? data['parentId'] as String? ?? '';
        final senderRealName = data['senderRealName'] as String? ?? '';
        final tabletName = data['tabletName'] as String? ?? '';

        // Resolve the approver's display name: prefer their real profile name
        final String approverName;
        if (senderRealName.trim().isNotEmpty && senderRealName != 'Yeni Ebeveyn Telefonu' && senderRealName != 'OMEGA Cihazı') {
          approverName = senderRealName.trim();
        } else if (tabletName.trim().isNotEmpty && tabletName != 'Yeni Ebeveyn Telefonu' && tabletName != 'OMEGA Cihazı') {
          approverName = tabletName.trim();
        } else {
          approverName = 'Cihaz $targetClean';
        }

        if (approverDeviceId.isNotEmpty && approverDeviceId != myProfile?.id) {
          // Clean from sentPairRequests
          sentPairRequests.remove(targetClean);
          LocalStorageService.saveSentPairRequests(sentPairRequests);

          // Add to paired devices if not already there
          final existingIdx = pairedDevicesList.indexWhere(
              (d) => d.id == approverDeviceId || d.pairCode == targetClean);
          if (existingIdx == -1) {
            final newPaired = UserProfile(
              id: approverDeviceId,
              deviceName: approverName,
              role: DeviceRole.parent,
              pairCode: targetClean,
              pairedDeviceId: myProfile?.id ?? '',
              isOnline: true,
              lastSeen: DateTime.now(),
            );
            if (_addPairedDeviceSafe(newPaired)) {
              if (pairedProfile == null) {
                pairedProfile = newPaired;
                LocalStorageService.savePairedDevice(newPaired);
              }
              LocalStorageService.savePairedDevicesList(pairedDevicesList);
            }
          } else {
            // Update name if generic
            final existingDev = pairedDevicesList[existingIdx];
            if (existingDev.deviceName.startsWith('Cihaz ') || existingDev.deviceName == 'Yeni Ebeveyn Telefonu' || existingDev.deviceName == 'OMEGA Cihazı' || existingDev.deviceName == 'Ebeveyn Telefonu') {
              pairedDevicesList[existingIdx] = existingDev.copyWith(deviceName: approverName);
              if (pairedProfile?.id == existingDev.id) {
                pairedProfile = pairedDevicesList[existingIdx];
                LocalStorageService.savePairedDevice(pairedProfile!);
              }
              LocalStorageService.savePairedDevicesList(pairedDevicesList);
            }
          }

          debugPrint('✅ [SENT REQUEST PAIRED] $targetClean accepted by $approverDeviceId ($approverName)');
          lastNotificationMessage = '✅ $approverName eşleşme isteğinizi kabul etti!';
          _updateSignalingListenTargets();
          notifyListeners();
        }
      },
      onCancelled: (data) {
        sentPairRequests.remove(targetClean);
        LocalStorageService.saveSentPairRequests(sentPairRequests);
        lastNotificationMessage = 'Eşleşme isteği karşı tarafça reddedildi.';
        notifyListeners();
      },
    );

    notifyListeners();
    return PairRequestResult.success;
  }

  Future<void> cancelSentPairRequest(String targetCode) async {
    sentPairRequests.remove(targetCode);
    await LocalStorageService.saveSentPairRequests(sentPairRequests);
    if (myProfile != null) {
      await _signalingService.cancelPairRequest(targetCode, myProfile!.id);
    }
    lastNotificationMessage = 'Giden eşleşme isteği iptal edildi.';
    notifyListeners();
  }

  Future<void> blockDevice(String deviceId) async {
    if (!blockedDeviceIds.contains(deviceId)) {
      blockedDeviceIds.add(deviceId);
      await LocalStorageService.saveBlockedDevices(blockedDeviceIds);
    }
    await removePairedDevice(deviceId);
    lastNotificationMessage = 'Cihaz engellendi.';
    notifyListeners();
  }

  Future<void> unblockDevice(String deviceId) async {
    blockedDeviceIds.remove(deviceId);
    await LocalStorageService.saveBlockedDevices(blockedDeviceIds);
    lastNotificationMessage = 'Cihazın engeli kaldırıldı.';
    notifyListeners();
  }

  void _updateSignalingListenTargets() {
    final targets = <String>[];
    final fallbackPins = <String>[];
    if (myProfile != null) {
      targets.add(myProfile!.id);
      targets.add(myProfile!.pairCode);
      targets.add('omega_tablet_${myProfile!.pairCode}');
      targets.add('omega_parent_${myProfile!.pairCode}');
      fallbackPins.add(myProfile!.pairCode);
    }
    for (final d in pairedDevicesList) {
      targets.add(d.id);
      targets.add(d.pairCode);
      targets.add('omega_tablet_${d.pairCode}');
      targets.add('omega_parent_${d.pairCode}');
      fallbackPins.add(d.pairCode);
      _updatePhotoSubscription(d.id);
    }
    _signalingService.addListenTargets(targets);
    if (myProfile != null) {
      _signalingService.listenGroupMessages(myProfile!.id, fallbackPins: [familyGroupPin, ...fallbackPins]);
    }
    startListeningFamilyCameras();
  }

  // WhatsApp-style live device search wrapper
  Future<Map<String, dynamic>?> lookupTargetDevice(String input) async {
    return await _signalingService.lookupTargetDevice(input);
  }

  // Re-establish listeners on sent pair request target channels (called on startup)
  void _listenForSentPairRequestResponses() {
    for (final targetCode in List<String>.from(sentPairRequests)) {
      _signalingService.listenTabletPairing(
        targetCode,
        onPendingApproval: (_) {},
        onPaired: (data) {
          final approverDeviceId = data['tabletId'] as String? ?? data['parentId'] as String? ?? '';
          final senderRealName = data['senderRealName'] as String? ?? '';
          final tabletName = data['tabletName'] as String? ?? '';

          final String approverName;
          if (senderRealName.trim().isNotEmpty && senderRealName != 'Yeni Ebeveyn Telefonu' && senderRealName != 'OMEGA Cihazı') {
            approverName = senderRealName.trim();
          } else if (tabletName.trim().isNotEmpty && tabletName != 'Yeni Ebeveyn Telefonu' && tabletName != 'OMEGA Cihazı') {
            approverName = tabletName.trim();
          } else {
            approverName = 'Cihaz $targetCode';
          }

          if (approverDeviceId.isNotEmpty && approverDeviceId != myProfile?.id) {
            sentPairRequests.remove(targetCode);
            LocalStorageService.saveSentPairRequests(sentPairRequests);

            final existingIdx = pairedDevicesList.indexWhere(
                (d) => d.id == approverDeviceId || d.pairCode == targetCode);
            if (existingIdx == -1) {
              final newPaired = UserProfile(
                id: approverDeviceId,
                deviceName: approverName,
                role: DeviceRole.parent,
                pairCode: targetCode,
                pairedDeviceId: myProfile?.id ?? '',
                isOnline: true,
                lastSeen: DateTime.now(),
              );
              if (_addPairedDeviceSafe(newPaired)) {
                if (pairedProfile == null) {
                  pairedProfile = newPaired;
                  LocalStorageService.savePairedDevice(newPaired);
                }
                LocalStorageService.savePairedDevicesList(pairedDevicesList);
              }
            }

            debugPrint('✅ [STARTUP PAIR RESOLVED] $targetCode accepted by $approverDeviceId ($approverName)');
            lastNotificationMessage = '✅ $approverName eşleşme isteğinizi kabul etti!';
            _updateSignalingListenTargets();
            notifyListeners();
          }
        },
        onCancelled: (data) {
          sentPairRequests.remove(targetCode);
          LocalStorageService.saveSentPairRequests(sentPairRequests);
          notifyListeners();
        },
      );
    }
  }

  // Dynamically update device role, name, pairing method, phone or email without breaking paired links
  Future<void> updateMyProfileAndRole({
    DeviceRole? newRole,
    String? newName,
    String? newPhone,
    String? newEmail,
    String? newPin,
    String? newAvatarIcon,
  }) async {
    if (myProfile == null) return;

    final updatedRole = newRole ?? myProfile!.role;
    final updatedName = (newName != null && newName.trim().isNotEmpty)
        ? newName.trim()
        : myProfile!.deviceName;
    final updatedPhone = newPhone ?? myProfile!.phoneNumber;
    final updatedEmail = newEmail ?? myProfile!.email;
    final updatedPin = newPin ?? myProfile!.pairCode;
    final updatedAvatar = newAvatarIcon ?? myProfile!.avatarIcon;

    myProfile = myProfile!.copyWith(
      role: updatedRole,
      deviceName: updatedName,
      phoneNumber: updatedPhone,
      email: updatedEmail,
      pairCode: updatedPin,
      avatarIcon: updatedAvatar,
    );

    await LocalStorageService.saveUserProfile(myProfile!);

    await _signalingService.updateDeviceProfileAndPairing(
      deviceId: myProfile!.id,
      newName: updatedName,
      roleName: updatedRole.name,
      pairCode: updatedPin,
      email: updatedEmail,
      phoneNumber: updatedPhone,
    );

    notifyListeners();
  }

  /// Upload profile photo to Firebase as base64 (called when user picks a new photo)
  Future<void> uploadMyProfilePhoto(String filePath, {Uint8List? bytes}) async {
    if (myProfile == null) return;
    try {
      Uint8List? imageBytes = bytes;
      if (imageBytes == null && filePath.isNotEmpty && !kIsWeb) {
        try {
          final file = File(filePath);
          if (await file.exists()) {
            imageBytes = await file.readAsBytes();
          }
        } catch (e) {
          debugPrint('⚠️ [FILE READ ERROR]: $e');
        }
      }

      if (imageBytes == null || imageBytes.isEmpty) {
        debugPrint('⚠️ [PROFILE PHOTO] Photo bytes empty for path $filePath');
        return;
      }

      final b64 = base64Encode(imageBytes);

      // Update local profile
      myProfile = myProfile!.copyWith(
        avatarIcon: filePath,
        photoBase64: b64,
      );
      await LocalStorageService.saveUserProfile(myProfile!);

      // Upload to Firebase only if sharePhoto is enabled
      if (myProfile!.sharePhoto) {
        await _signalingService.uploadProfilePhoto(myProfile!.id, b64);
      }
      notifyListeners();
      debugPrint('🔥 [PROFILE PHOTO] Successfully uploaded photo (${b64.length} chars)');
    } catch (e) {
      debugPrint('⚠️ [PROFILE PHOTO ERROR]: $e');
    }
  }

  /// Remove local profile photo and delete from Firebase
  Future<void> removeMyProfilePhoto() async {
    if (myProfile == null) return;
    myProfile = myProfile!.copyWith(
      avatarIcon: '',
      photoBase64: null,
    );
    await LocalStorageService.saveUserProfile(myProfile!);
    await _signalingService.removeProfilePhoto(myProfile!.id);
    notifyListeners();
    debugPrint('🔥 [PROFILE PHOTO] Profile photo removed');
  }

  /// Toggle photo sharing privacy setting
  Future<void> toggleSharePhoto(bool share) async {
    if (myProfile == null) return;
    myProfile = myProfile!.copyWith(sharePhoto: share);
    await LocalStorageService.saveUserProfile(myProfile!);

    if (share && myProfile!.photoBase64 != null) {
      // Re-upload photo to Firebase
      await _signalingService.uploadProfilePhoto(myProfile!.id, myProfile!.photoBase64!);
    } else if (!share) {
      // Remove photo from Firebase for privacy
      await _signalingService.removeProfilePhoto(myProfile!.id);
    }
    notifyListeners();
  }

  final Map<String, StreamSubscription> _photoSubscriptions = {};

  void _updatePhotoSubscription(String deviceId) {
    if (_photoSubscriptions.containsKey(deviceId)) return;
    final sub = _signalingService.listenToDevicePhotoUpdates(deviceId, (newPhotoBase64) {
      bool changed = false;
      if (pairedProfile != null && _isSameDevice(pairedProfile!.id, deviceId)) {
        if (pairedProfile!.photoBase64 != newPhotoBase64) {
          pairedProfile = pairedProfile!.copyWith(photoBase64: newPhotoBase64);
          changed = true;
        }
      }
      for (int i = 0; i < pairedDevicesList.length; i++) {
        if (_isSameDevice(pairedDevicesList[i].id, deviceId)) {
          if (pairedDevicesList[i].photoBase64 != newPhotoBase64) {
            pairedDevicesList[i] = pairedDevicesList[i].copyWith(photoBase64: newPhotoBase64);
            changed = true;
          }
        }
      }
      if (changed) {
        notifyListeners();
        debugPrint('🔥 [REALTIME PHOTO UPDATE] Updated photo for $deviceId (hasPhoto=${newPhotoBase64 != null})');
      }
    });
    if (sub != null) {
      _photoSubscriptions[deviceId] = sub;
    }
  }

  /// Fetch paired device's profile photo from Firebase and cache locally
  Future<void> fetchPairedProfilePhoto(String deviceId) async {
    try {
      final b64 = await _signalingService.fetchProfilePhoto(deviceId);
      if (b64 != null && b64.isNotEmpty) {
        bool changed = false;
        // Update paired profile with photo
        if (pairedProfile != null && _isSameDevice(pairedProfile!.id, deviceId)) {
          if (pairedProfile!.photoBase64 != b64) {
            pairedProfile = pairedProfile!.copyWith(photoBase64: b64);
            changed = true;
          }
        }
        // Also update in pairedDevicesList
        for (int i = 0; i < pairedDevicesList.length; i++) {
          if (_isSameDevice(pairedDevicesList[i].id, deviceId)) {
            if (pairedDevicesList[i].photoBase64 != b64) {
              pairedDevicesList[i] = pairedDevicesList[i].copyWith(photoBase64: b64);
              changed = true;
            }
          }
        }
        if (changed) {
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('⚠️ [FETCH PAIRED PHOTO ERROR]: $e');
    }
  }

  /// Fetch all paired devices' photos & subscribe to real-time photo updates
  Future<void> fetchAllPairedPhotos() async {
    for (final device in pairedDevicesList) {
      await fetchPairedProfilePhoto(device.id);
      _updatePhotoSubscription(device.id);
    }
  }

  // --- Realtime Pairing Flow (Tablet Side Setup) ---

  Future<void> setupDeviceRole({
    required DeviceRole role,
    required String name,
    String? existingPin,
    String? customPin,
    String? email,
    String? phoneNumber,
    String avatarIcon = 'tablet',
    String? photoBase64,
  }) async {
    final String pairPin = customPin ?? existingPin ?? SecurityService.generatePairPin();
    final String myDeviceId = role == DeviceRole.tablet
        ? 'omega_tablet_$pairPin'
        : 'omega_parent_$pairPin';
    final String targetId = role == DeviceRole.tablet
        ? 'omega_parent_$pairPin'
        : 'omega_tablet_$pairPin';

    final profile = UserProfile(
      id: myDeviceId,
      deviceName: name,
      role: role,
      pairCode: pairPin,
      pairedDeviceId: targetId,
      avatarIcon: avatarIcon,
      photoBase64: photoBase64,
      isOnline: true,
      lastSeen: DateTime.now(),
      email: email,
      phoneNumber: phoneNumber,
    );

    myProfile = profile;
    pairedProfile = null;

    await LocalStorageService.saveUserProfile(profile);
    notifyListeners();

    _signalingService.init(myDeviceId).then((_) {
      _setupSignalingListeners();
      if (role == DeviceRole.tablet) {
        _signalingService.registerTabletPair(pairPin, myDeviceId, name);
        _signalingService.listenTabletPairing(
          pairPin,
          onPendingApproval: (parentData) async {
            final realParentId = parentData['parentId'] as String? ?? targetId;
            final rawParentName = parentData['parentName'] as String? ?? '';

            final String resolvedParentName = (rawParentName.trim().isNotEmpty && rawParentName != 'Yeni Ebeveyn Telefonu' && rawParentName != 'OMEGA Cihazı' && rawParentName != 'Ebeveyn Telefonu')
                ? rawParentName.trim()
                : 'Cihaz ${parentData['parentPairCode'] ?? pairPin}';

            final incomingParentProfile = UserProfile(
              id: realParentId,
              deviceName: resolvedParentName,
              role: DeviceRole.parent,
              pairCode: pairPin,
              pairedDeviceId: myDeviceId,
              avatarIcon: 'parent',
              isOnline: true,
              lastSeen: DateTime.now(),
            );

            pendingPairRequest = incomingParentProfile;
            notifyListeners();
          },
          onPaired: (parentData) async {
            final realParentId = parentData['parentId'] as String? ?? targetId;
            final rawParentName = parentData['parentName'] as String? ?? '';
            final senderRealName = parentData['senderRealName'] as String? ?? '';

            final String resolvedParentName;
            if (senderRealName.trim().isNotEmpty && senderRealName != 'Yeni Ebeveyn Telefonu') {
              resolvedParentName = senderRealName.trim();
            } else if (rawParentName.trim().isNotEmpty && rawParentName != 'Yeni Ebeveyn Telefonu' && rawParentName != 'OMEGA Cihazı' && rawParentName != 'Ebeveyn Telefonu') {
              resolvedParentName = rawParentName.trim();
            } else {
              resolvedParentName = 'Cihaz ${parentData['parentPairCode'] ?? pairPin}';
            }

            final incomingParentProfile = UserProfile(
              id: realParentId,
              deviceName: resolvedParentName,
              role: DeviceRole.parent,
              pairCode: pairPin,
              pairedDeviceId: myDeviceId,
              avatarIcon: 'parent',
              isOnline: true,
              lastSeen: DateTime.now(),
            );

            pairedProfile = incomingParentProfile;
            _addPairedDeviceSafe(incomingParentProfile);
            await LocalStorageService.savePairedDevice(incomingParentProfile);
            await LocalStorageService.savePairedDevicesList(pairedDevicesList);
            notifyListeners();
          },
        );
      }
    });
  }

  // Parent enters PIN on phone + enters custom name for child e.g. "Ömer'in Tableti"
  Future<bool> pairWithDevice(String pairCodeOrQr, {String? customName}) async {
    final cleanPin = pairCodeOrQr.trim().replaceAll(' ', '');
    if (cleanPin.isEmpty) return false;

    final String myId = myProfile?.id ?? 'omega_parent_$cleanPin';
    final String targetTabletId = 'omega_tablet_$cleanPin';

    final String childLabel = (customName != null && customName.trim().isNotEmpty)
        ? customName.trim()
        : 'Ömer\'in Tableti';

    final parentProfile = UserProfile(
      id: myId,
      deviceName: myProfile?.deviceName ?? 'Ebeveyn Telefonu',
      role: DeviceRole.parent,
      pairCode: cleanPin,
      pairedDeviceId: targetTabletId,
      avatarIcon: 'parent',
      isOnline: true,
      lastSeen: DateTime.now(),
    );

    final tabletProfile = UserProfile(
      id: targetTabletId,
      deviceName: childLabel,
      role: DeviceRole.tablet,
      pairCode: cleanPin,
      pairedDeviceId: myId,
      avatarIcon: 'tablet',
      isOnline: true,
      lastSeen: DateTime.now(),
    );

    myProfile = parentProfile;
    pairedProfile = tabletProfile;

    _addPairedDeviceSafe(tabletProfile);

    await LocalStorageService.saveUserProfile(myProfile!);
    await LocalStorageService.savePairedDevice(pairedProfile!);
    await LocalStorageService.savePairedDevicesList(pairedDevicesList);

    await _signalingService.init(myId);
    _setupSignalingListeners();

    // 1. Parent sends pair request with parent's custom name for child e.g. "Ömer'in Tableti"
    await _signalingService.sendPairRequest(cleanPin, myId, childLabel);

    // 2. Listen until Tablet approves pairing
    _signalingService.listenTabletPairing(
      cleanPin,
      onPendingApproval: (_) {},
      onPaired: (data) async {
        final tabletNameFromData = data['tabletName'] ?? childLabel;
        pairedProfile = tabletProfile.copyWith(deviceName: tabletNameFromData);
        await LocalStorageService.savePairedDevice(pairedProfile!);
        notifyListeners();
      },
    );

    notifyListeners();
    return true;
  }

  Future<void> unpairAndReset() async {
    await LocalStorageService.clearAll();
    myProfile = null;
    pairedProfile = null;
    pairedDevicesList = [];
    pendingPairRequest = null;
    generatedPairPin = null;
    createdContactName = null;
    isPhoneEnteredCode = false;
    activeCall = null;
    chatHistory = [];
    notifyListeners();
  }

  // --- Calling Flow ---

  Future<void> startCall(CallType type) async {
    if (pairedProfile == null || myProfile == null) return;

    final isTargetPaired = pairedDevicesList.any((d) => d.id == pairedProfile!.id);
    if (!isTargetPaired) {
      lastNotificationMessage = 'Bu kullanıcı ile eşleşmeniz sonlandırıldığı için arama gerçekleştirilemedi.';
      notifyListeners();
      return;
    }

    final callId = 'call_${DateTime.now().millisecondsSinceEpoch}';

    // ⚡ INSTANT UI: Show call screen immediately (0ms)
    final pendingSession = CallSession(
      callId: callId,
      callerId: myProfile!.id,
      callerName: myProfile!.deviceName,
      receiverId: pairedProfile!.id,
      type: type,
      status: CallStatus.calling,
      createdAt: DateTime.now(),
    );

    activeCall = pendingSession;
    AudioRingtoneService().playRingback();
    notifyListeners();

    // 30-Second Call Timeout Guard
    _callTimeoutTimer?.cancel();
    _callTimeoutTimer = Timer(const Duration(seconds: 30), () async {
      if (activeCall != null &&
          (activeCall!.status == CallStatus.calling || activeCall!.status == CallStatus.ringing)) {
        lastNotificationMessage = '⌛ Cevapsız Arama: Karşı taraf 30 saniye yanıt vermedi.';
        
        // Update status so CallScreen shows "Yanıtsız" text
        activeCall = activeCall!.copyWith(status: CallStatus.rejected);
        notifyListeners();

        // Play unanswered sound and WAIT for it to finish
        await AudioRingtoneService().playUnansweredSound();

        // Now dismiss the call screen
        await endCall(skipEndedSound: true);
      }
    });

    // Network ops run AFTER UI is already showing
    try {
      // 1. Create WebRTC offer (camera/mic + SDP)
      final offerSdp = await webRTCService.createOffer(pairedProfile!.id, type);
      final fullSession = pendingSession.copyWith(sdpOffer: offerSdp);

      // 2. Verify call is still active (user might have cancelled)
      if (activeCall != null && activeCall!.callId == callId) {
        activeCall = fullSession;
        await _signalingService.sendCallOffer(fullSession);
        await _signalingService.saveCallRecordToFirebase(pairedProfile!.pairCode, fullSession);
      }
    } catch (e) {
      debugPrint('❌ [START CALL ERROR]: $e');
      await endCall();
    }
  }

  Future<void> _recordCallLog({
    required CallDirection direction,
    int? customDurationSeconds,
  }) async {
    if (activeCall == null || pairedProfile == null) return;

    final session = activeCall!;
    final contact = pairedProfile!;
    int duration = customDurationSeconds ?? 0;

    if (customDurationSeconds == null && _callConnectedTime != null) {
      duration = DateTime.now().difference(_callConnectedTime!).inSeconds;
    }

    final log = CallLog(
      id: 'call_${DateTime.now().millisecondsSinceEpoch}',
      deviceId: contact.id,
      deviceName: contact.deviceName,
      role: contact.role,
      callType: session.type,
      direction: direction,
      timestamp: DateTime.now(),
      durationSeconds: duration < 0 ? 0 : duration,
    );

    callHistory.insert(0, log);
    await LocalStorageService.saveCallLog(log);
    _callConnectedTime = null;
  }

  Future<void> _recordMissedCallLogFromSession(CallSession session) async {
    final callerPin = session.callerId.split('_').last;
    final contact = pairedDevicesList.firstWhere(
      (d) => d.id == session.callerId || d.pairCode == callerPin,
      orElse: () => UserProfile(
        id: session.callerId,
        deviceName: session.callerName,
        role: DeviceRole.parent,
        pairCode: callerPin,
        pairedDeviceId: myProfile?.id ?? '',
        lastSeen: DateTime.now(),
      ),
    );
    final log = CallLog(
      id: 'call_${DateTime.now().millisecondsSinceEpoch}',
      deviceId: contact.id,
      deviceName: contact.deviceName,
      role: contact.role,
      callType: session.type,
      direction: CallDirection.missed,
      timestamp: DateTime.now(),
      durationSeconds: 0,
    );
    callHistory.insert(0, log);
    await LocalStorageService.saveCallLog(log);
  }

  Future<void> acceptCall() async {
    _callTimeoutTimer?.cancel();
    final callToAccept = activeCall;
    if (callToAccept == null || callToAccept.sdpOffer == null) return;

    AudioRingtoneService().stopAll();
    final answerSdp = await webRTCService.createAnswer(
      callToAccept.callerId,
      callToAccept.sdpOffer!,
      callToAccept.type,
    );

    if (activeCall == null || activeCall!.callId != callToAccept.callId) return;

    _callConnectedTime = DateTime.now();
    final connectedCall = callToAccept.copyWith(status: CallStatus.connected);
    activeCall = connectedCall;
    notifyListeners();

    await _signalingService.sendCallAnswer(callToAccept.callerId, answerSdp, callToAccept.callId);
    if (pairedProfile != null) {
      await _signalingService.saveCallRecordToFirebase(pairedProfile!.pairCode, connectedCall);
    }
  }

  Future<void> rejectCall() async {
    _callTimeoutTimer?.cancel();
    AudioRingtoneService().stopAll();
    NotificationService().stopIncomingCallUI();
    
    if (activeCall != null && pairedProfile != null) {
      _recordCallLog(direction: CallDirection.missed, customDurationSeconds: 0);
    }

    String? targetId;
    if (activeCall != null && myProfile != null) {
      targetId = (activeCall!.callerId == myProfile!.id)
          ? activeCall!.receiverId
          : activeCall!.callerId;
    } else {
      targetId = pairedProfile?.id;
    }
    final currentCall = activeCall;

    // ⚡ INSTANT UI DISMISSAL (0ms response time)
    activeCall = null;
    notifyListeners();

    // Async background cleanup (non-blocking)
    if (currentCall != null && pairedProfile != null) {
      _signalingService.saveCallRecordToFirebase(
        pairedProfile!.pairCode,
        currentCall.copyWith(status: CallStatus.rejected),
      );
    }
    
    // CRITICAL FIX: Tell the caller that we rejected
    if (myProfile != null && targetId != null && targetId.isNotEmpty) {
      await _signalingService.rejectCall(targetId, currentCall?.callId);
      Future.delayed(const Duration(milliseconds: 1200), () {
        if (myProfile != null) {
          _signalingService.cleanStaleCalls(myProfile!.id, targetId);
        }
      });
    }

    webRTCService.dispose();
  }

  Future<void> endCall({bool skipEndedSound = true}) async {
    _callTimeoutTimer?.cancel();
    NotificationService().stopIncomingCallUI();

    final isConnected = activeCall != null && activeCall!.status == CallStatus.connected;

    if (activeCall != null && pairedProfile != null) {
      final isCallerMe = myProfile != null && activeCall!.callerId == myProfile!.id;
      final direction = isConnected
          ? (isCallerMe ? CallDirection.outgoing : CallDirection.incoming)
          : (isCallerMe ? CallDirection.outgoing : CallDirection.missed);
      _recordCallLog(direction: direction);
    }

    String? targetId;
    if (activeCall != null && myProfile != null) {
      targetId = (activeCall!.callerId == myProfile!.id)
          ? activeCall!.receiverId
          : activeCall!.callerId;
    } else {
      targetId = pairedProfile?.id;
    }
    final currentCall = activeCall;

    // Async background cleanup (non-blocking)
    if (currentCall != null && pairedProfile != null) {
      _signalingService.saveCallRecordToFirebase(
        pairedProfile!.pairCode,
        currentCall.copyWith(status: CallStatus.ended),
      );
    }
    if (myProfile != null) {
      _signalingService.endCall(myProfile!.id, targetId ?? '', currentCall?.callId);
    }

    // Normal end call: NO MP3 sound plays on either side (like a standard phone call).
    await AudioRingtoneService().stopAll();

    activeCall = null;
    webRTCService.dispose();
    notifyListeners();
  }

  // --- Realtime Messaging Flow ---

  Future<void> sendMessage(String text) async {
    if (pairedProfile == null || myProfile == null || text.trim().isEmpty) return;

    final isTargetPaired = pairedDevicesList.any((d) => d.id == pairedProfile!.id);
    if (!isTargetPaired) {
      lastNotificationMessage = 'Bu kullanıcı ile eşleşmeniz sonlandırıldığı için mesaj gönderilemedi.';
      notifyListeners();
      return;
    }

    final message = ChatMessage(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      senderId: myProfile!.id,
      receiverId: pairedProfile!.id,
      text: text.trim(),
      timestamp: DateTime.now(),
    );

    chatHistory.add(message);
    await LocalStorageService.saveChatMessage(message);

    if (text.contains('🔔 YÜKSEK İKAZ')) {
      AudioRingtoneService().playAlarm();
    }

    notifyListeners();

    await _signalingService.sendMessage(message);
    await _signalingService.saveChatMessageToFirebase(pairedProfile!.pairCode, message);
  }

  Future<void> sendMediaMessage(String text, MessageType type, {String? mediaUrl}) async {
    if (pairedProfile == null || myProfile == null) return;

    final isTargetPaired = pairedDevicesList.any((d) => d.id == pairedProfile!.id);
    if (!isTargetPaired) {
      lastNotificationMessage = 'Bu kullanıcı ile eşleşmeniz sonlandırıldığı için mesaj gönderilemedi.';
      notifyListeners();
      return;
    }

    final message = ChatMessage(
      id: 'msg_${DateTime.now().millisecondsSinceEpoch}',
      senderId: myProfile!.id,
      receiverId: pairedProfile!.id,
      text: text.trim(),
      type: type,
      mediaUrl: mediaUrl,
      timestamp: DateTime.now(),
    );

    chatHistory.add(message);
    await LocalStorageService.saveChatMessage(message);

    notifyListeners();

    await _signalingService.sendMessage(message);
    await _signalingService.saveChatMessageToFirebase(pairedProfile!.pairCode, message);
  }

  Future<void> markMessagesAsRead(String senderId) async {
    bool hasChanges = false;
    for (int i = 0; i < chatHistory.length; i++) {
      final msg = chatHistory[i];
      if (_isSameDevice(msg.senderId, senderId) && !msg.isRead) {
        final updated = msg.copyWith(isDelivered: true, isRead: true);
        chatHistory[i] = updated;
        await LocalStorageService.saveChatMessage(updated);
        _signalingService.sendMessageStatusUpdate(msg.senderId, msg.id, 'read');
        hasChanges = true;
      }
    }
    if (hasChanges) {
      notifyListeners();
    }
  }

  // --- Family Group Chat Methods ---

  void setGroupChatActive(bool active) {
    isGroupChatActive = active;
    if (active) {
      groupUnreadCount = 0;
      notifyListeners();
    }
  }

  Future<void> sendGroupChatMessage(String text) async {
    if (myProfile == null) return;
    final familyPin = familyGroupPin;

    final message = ChatMessage(
      id: 'group_msg_${DateTime.now().millisecondsSinceEpoch}',
      senderId: myProfile!.id,
      senderName: myProfile!.deviceName,
      receiverId: 'family_group_$familyPin',
      text: text.trim(),
      timestamp: DateTime.now(),
      isDelivered: true,
      isRead: true,
    );

    _processedMessageKeys.add(message.id);
    groupChatHistory.add(message);
    await LocalStorageService.saveGroupChatMessage(message);

    if (text.contains('🔔 YÜKSEK İKAZ')) {
      AudioRingtoneService().playAlarm();
    }

    notifyListeners();

    final targetDeviceIds = pairedDevicesList.map((d) => d.id).toList();
    await _signalingService.sendGroupChatMessage(familyPin, targetDeviceIds, message);
  }

  Future<void> sendGroupMediaMessage(String text, MessageType type, {String? mediaUrl}) async {
    if (myProfile == null) return;
    final familyPin = familyGroupPin;

    final message = ChatMessage(
      id: 'group_msg_${DateTime.now().millisecondsSinceEpoch}',
      senderId: myProfile!.id,
      senderName: myProfile!.deviceName,
      receiverId: 'family_group_$familyPin',
      text: text.trim(),
      type: type,
      mediaUrl: mediaUrl,
      timestamp: DateTime.now(),
      isDelivered: true,
      isRead: true,
    );

    _processedMessageKeys.add(message.id);
    groupChatHistory.add(message);
    await LocalStorageService.saveGroupChatMessage(message);

    notifyListeners();

    final targetDeviceIds = pairedDevicesList.map((d) => d.id).toList();
    await _signalingService.sendGroupChatMessage(familyPin, targetDeviceIds, message);
  }

  Future<void> editGroupChatMessage(String messageId, String newText) async {
    final idx = groupChatHistory.indexWhere((m) => m.id == messageId);
    if (idx != -1) {
      final updated = groupChatHistory[idx].copyWith(
        text: newText.trim(),
        isEdited: true,
      );
      groupChatHistory[idx] = updated;
      await LocalStorageService.saveGroupChatMessage(updated);
      notifyListeners();
      final targetDeviceIds = pairedDevicesList.map((d) => d.id).toList();
      await _signalingService.sendGroupChatMessage(familyGroupPin, targetDeviceIds, updated);
    }
  }

  Future<void> deleteGroupChatMessage(String messageId) async {
    final idx = groupChatHistory.indexWhere((m) => m.id == messageId);
    if (idx != -1) {
      final updated = groupChatHistory[idx].copyWith(
        text: '🚫 Bu mesaj silindi',
        isDeleted: true,
      );
      groupChatHistory[idx] = updated;
      await LocalStorageService.saveGroupChatMessage(updated);
      notifyListeners();
      final targetDeviceIds = pairedDevicesList.map((d) => d.id).toList();
      await _signalingService.sendGroupChatMessage(familyGroupPin, targetDeviceIds, updated);
    }
  }

  Future<void> editChatMessage(String messageId, String newText) async {
    final idx = chatHistory.indexWhere((m) => m.id == messageId);
    if (idx != -1) {
      final updated = chatHistory[idx].copyWith(
        text: newText.trim(),
        isEdited: true,
      );
      chatHistory[idx] = updated;
      await LocalStorageService.saveChatMessage(updated);
      notifyListeners();
      if (pairedProfile != null) {
        await _signalingService.sendMessage(updated);
      }
    }
  }

  Future<void> deleteChatMessage(String messageId) async {
    final idx = chatHistory.indexWhere((m) => m.id == messageId);
    if (idx != -1) {
      final updated = chatHistory[idx].copyWith(
        text: '🚫 Bu mesaj silindi',
        isDeleted: true,
      );
      chatHistory[idx] = updated;
      await LocalStorageService.saveChatMessage(updated);
      notifyListeners();
      if (pairedProfile != null) {
        await _signalingService.sendMessage(updated);
      }
    }
  }

  Future<void> deleteGroupMessageForMe(String messageId) async {
    groupChatHistory.removeWhere((m) => m.id == messageId);
    await LocalStorageService.deleteGroupChatMessage(messageId);
    notifyListeners();
  }

  Future<void> deleteChatMessageForMe(String messageId) async {
    chatHistory.removeWhere((m) => m.id == messageId);
    await LocalStorageService.deleteChatMessage(messageId);
    notifyListeners();
  }

  /// Completely delete all 1-on-1 chat history with a specific paired device (both locally and from Firebase)
  Future<void> deleteEntireChatWithDevice(String targetDeviceId) async {
    final targetPin = targetDeviceId.split('_').last;
    final myPin = myProfile?.id.split('_').last ?? '';

    // 1. Remove from local Hive storage
    await LocalStorageService.clearChatHistoryForContact(targetDeviceId, targetPin);

    // 2. Remove from local memory
    chatHistory.removeWhere((m) {
      final sPin = m.senderId.split('_').last;
      final rPin = m.receiverId.split('_').last;
      return m.senderId == targetDeviceId ||
          m.receiverId == targetDeviceId ||
          (targetPin.isNotEmpty && (sPin == targetPin || rPin == targetPin));
    });

    // 3. Remove from Firebase RTDB
    if (myPin.isNotEmpty) {
      await _signalingService.deleteEntireChatFromFirebase(myPin, targetPin);
    }

    notifyListeners();
  }

  /// Completely wipe family group chat messages across all connected devices (Network Admin only)
  Future<void> resetFamilyGroupChatForAllDevices() async {
    // 1. Clear local memory and storage
    groupChatHistory.clear();
    groupUnreadCount = 0;
    await LocalStorageService.clearGroupChatHistory();
    notifyListeners();

    // 2. Clear from Firebase RTDB
    await _signalingService.clearGroupChatFromFirebase(familyGroupPin);

    // 3. Broadcast system message so all other devices clear their local storage too
    final clearMsg = ChatMessage(
      id: 'clear_${DateTime.now().millisecondsSinceEpoch}',
      senderId: myProfile?.id ?? 'admin',
      senderName: myProfile?.deviceName ?? 'Yönetici',
      receiverId: 'group',
      text: '__SYSTEM_CLEAR_GROUP_CHAT__',
      timestamp: DateTime.now(),
      type: MessageType.text,
    );

    final targetDeviceIds = pairedDevicesList.map((d) => d.id).toList();
    await _signalingService.sendGroupChatMessage(familyGroupPin, targetDeviceIds, clearMsg);
  }

  // --- SECURITY CAMERA MODE MANAGEMENT ---
  List<Map<String, dynamic>> activeFamilyCameras = [];
  bool isCameraHostMode = false;

  List<String> _getAllFamilyPins() {
    final pins = <String>{'global'};
    if (familyGroupPin.isNotEmpty) pins.add(familyGroupPin);
    if (myProfile != null) {
      final myPin = myProfile!.pairCode.isNotEmpty ? myProfile!.pairCode : myProfile!.id.split('_').last;
      if (myPin.isNotEmpty) pins.add(myPin);
    }
    for (final d in pairedDevicesList) {
      final pPin = d.pairCode.isNotEmpty ? d.pairCode : d.id.split('_').last;
      if (pPin.isNotEmpty) pins.add(pPin);
    }
    return pins.toList();
  }

  List<String> get allFamilyPins => _getAllFamilyPins();

  void startListeningFamilyCameras() {
    final pins = _getAllFamilyPins();
    if (pins.isNotEmpty) {
      _signalingService.listenFamilyCameras(pins, (cameras) {
        activeFamilyCameras = cameras;
        notifyListeners();
      });
    }
    startListeningCameraMotionAlerts();
  }

  Map<String, dynamic>? lastMotionAlert;

  void startListeningCameraMotionAlerts() {
    final pins = _getAllFamilyPins();
    if (pins.isEmpty) return;

    _signalingService.listenCameraMotionAlerts(
      pins: pins,
      onMotionAlert: (data) {
        final cameraDeviceId = data['cameraDeviceId'] as String? ?? '';
        final cameraDeviceName = data['cameraDeviceName'] as String? ?? 'Ev Kamerası';
        final timestamp = data['timestamp'] as int? ?? 0;
        final snapshotBase64 = data['snapshotBase64'] as String?;

        // Skip if event originated from MY device (the broadcasting camera station)
        if (myProfile != null && (cameraDeviceId == myProfile!.id || _isSameDevice(cameraDeviceId, myProfile!.id))) {
          return;
        }

        final alertKey = 'motion_${cameraDeviceId}_$timestamp';
        if (_processedMessageKeys.contains(alertKey)) return;
        _processedMessageKeys.add(alertKey);

        final nowMs = DateTime.now().millisecondsSinceEpoch;
        // 🛡️ TIME FILTER (Tazelik Kontrolü):
        // If alert is older than 45 seconds (e.g. historical data from DB / hot restart), ignore it!
        if (timestamp <= 0 || (nowMs - timestamp).abs() > 45000) {
          debugPrint('⏳ [MOTION ALERT IGNORED] Stale alert from ${DateTime.fromMillisecondsSinceEpoch(timestamp)} (${((nowMs - timestamp) / 1000).toStringAsFixed(1)}s old)');
          return;
        }

        lastMotionAlert = data;
        debugPrint('🚨 [CAMERA MOTION ALERT] From $cameraDeviceName ($cameraDeviceId). Triggering direct native notification!');

        // Trigger DIRECT NATIVE NOTIFICATION ONLY (No chat history / chat message creation!)
        NotificationService().showCameraMotionNotification(
          cameraName: cameraDeviceName,
          snapshotBase64: snapshotBase64,
          notificationId: cameraDeviceId.isNotEmpty ? (cameraDeviceId.hashCode.abs() % 2147483647) : null,
        );

        notifyListeners();
      },
    );
  }

  Future<void> startCameraHostMode(Map<String, dynamic> settings) async {
    if (myProfile == null) return;
    isCameraHostMode = true;
    notifyListeners();
    final fallbackPins = _getAllFamilyPins();
    await _signalingService.publishCameraStatus(
      familyPin: familyGroupPin,
      deviceId: myProfile!.id,
      deviceName: myProfile!.deviceName,
      isActive: true,
      fallbackPins: fallbackPins,
      settings: settings,
    );
  }

  Future<void> stopCameraHostMode() async {
    if (myProfile == null) return;
    isCameraHostMode = false;
    notifyListeners();
    final fallbackPins = _getAllFamilyPins();
    await _signalingService.publishCameraStatus(
      familyPin: familyGroupPin,
      deviceId: myProfile!.id,
      deviceName: myProfile!.deviceName,
      isActive: false,
      fallbackPins: fallbackPins,
    );
  }

  Future<void> setCameraTalkLock(String cameraDeviceId, bool isLocking) async {
    if (myProfile == null) return;
    await _signalingService.updateCameraTalkLock(
      familyPin: familyGroupPin,
      cameraDeviceId: cameraDeviceId,
      talkerDeviceId: isLocking ? myProfile!.id : null,
      talkerDeviceName: isLocking ? myProfile!.deviceName : null,
    );
  }
}
