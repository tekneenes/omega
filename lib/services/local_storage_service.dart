import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/user_profile.dart';
import '../models/chat_message.dart';
import '../models/call_log.dart';

class LocalStorageService {
  static const String _userBoxName = 'user_profile_box';
  static const String _chatBoxName = 'chat_messages_box';
  static const String _groupChatBoxName = 'group_chat_box';
  static const String _callLogBoxName = 'call_logs_box';

  static Future<void> init() async {
    try {
      await Hive.initFlutter();
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ [HIVE INIT WARN]: $e');
      }
      try {
        Hive.init('.');
      } catch (_) {}
    }
    try {
      if (!Hive.isBoxOpen(_userBoxName)) {
        await Hive.openBox<String>(_userBoxName);
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ [HIVE] User box open fallback: $e');
      }
    }
    try {
      if (!Hive.isBoxOpen(_chatBoxName)) {
        await Hive.openBox<String>(_chatBoxName);
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ [HIVE] Chat box open fallback: $e');
      }
    }
    try {
      if (!Hive.isBoxOpen(_groupChatBoxName)) {
        await Hive.openBox<String>(_groupChatBoxName);
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ [HIVE] Group chat box open fallback: $e');
      }
    }
    try {
      if (!Hive.isBoxOpen(_callLogBoxName)) {
        await Hive.openBox<String>(_callLogBoxName);
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ [HIVE] Call log box open fallback: $e');
      }
    }
  }

  // --- Profile Management ---
  static Future<void> saveUserProfile(UserProfile profile) async {
    if (!Hive.isBoxOpen(_userBoxName)) return;
    final box = Hive.box<String>(_userBoxName);
    await box.put('my_profile', jsonEncode(profile.toJson()));
  }

  static UserProfile? getUserProfile() {
    if (!Hive.isBoxOpen(_userBoxName)) return null;
    final box = Hive.box<String>(_userBoxName);
    final jsonStr = box.get('my_profile');
    if (jsonStr == null) return null;
    return UserProfile.fromJson(jsonDecode(jsonStr));
  }

  static Future<void> savePairedDevice(UserProfile pairedProfile) async {
    if (!Hive.isBoxOpen(_userBoxName)) return;
    final box = Hive.box<String>(_userBoxName);
    await box.put('paired_profile', jsonEncode(pairedProfile.toJson()));

    // Also update multiple devices list
    final list = getPairedDevicesList();
    list.removeWhere((d) => d.id == pairedProfile.id);
    list.add(pairedProfile);
    await savePairedDevicesList(list);
  }

  static UserProfile? getPairedDevice() {
    if (!Hive.isBoxOpen(_userBoxName)) return null;
    final box = Hive.box<String>(_userBoxName);
    final jsonStr = box.get('paired_profile');
    if (jsonStr == null) {
      final list = getPairedDevicesList();
      return list.isNotEmpty ? list.first : null;
    }
    return UserProfile.fromJson(jsonDecode(jsonStr));
  }

  static Future<void> savePairedDevicesList(List<UserProfile> devices) async {
    if (!Hive.isBoxOpen(_userBoxName)) return;
    final box = Hive.box<String>(_userBoxName);
    final jsonList = devices.map((d) => d.toJson()).toList();
    await box.put('paired_devices_list', jsonEncode(jsonList));
  }

  static List<UserProfile> getPairedDevicesList() {
    if (!Hive.isBoxOpen(_userBoxName)) return [];
    final box = Hive.box<String>(_userBoxName);
    final jsonStr = box.get('paired_devices_list');
    if (jsonStr == null) return [];
    try {
      final List list = jsonDecode(jsonStr);
      return list.map((item) => UserProfile.fromJson(item)).toList();
    } catch (_) {
      return [];
    }
  }

  // --- Blocked Devices & Sent Pair Requests ---
  static Future<void> saveBlockedDevices(List<String> blockedIds) async {
    if (!Hive.isBoxOpen(_userBoxName)) return;
    final box = Hive.box<String>(_userBoxName);
    await box.put('blocked_devices_list', jsonEncode(blockedIds));
  }

  static List<String> getBlockedDevices() {
    if (!Hive.isBoxOpen(_userBoxName)) return [];
    final box = Hive.box<String>(_userBoxName);
    final jsonStr = box.get('blocked_devices_list');
    if (jsonStr == null) return [];
    try {
      final List list = jsonDecode(jsonStr);
      return list.cast<String>();
    } catch (_) {
      return [];
    }
  }

  static Future<void> saveSentPairRequests(List<String> codes) async {
    if (!Hive.isBoxOpen(_userBoxName)) return;
    final box = Hive.box<String>(_userBoxName);
    await box.put('sent_pair_requests_list', jsonEncode(codes));
  }

  static List<String> getSentPairRequests() {
    if (!Hive.isBoxOpen(_userBoxName)) return [];
    final box = Hive.box<String>(_userBoxName);
    final jsonStr = box.get('sent_pair_requests_list');
    if (jsonStr == null) return [];
    try {
      final List list = jsonDecode(jsonStr);
      return list.cast<String>();
    } catch (_) {
      return [];
    }
  }

  // --- Approved Pair History (persistent) ---
  static Future<void> saveApprovedPairHistory(List<UserProfile> history) async {
    if (!Hive.isBoxOpen(_userBoxName)) return;
    final box = Hive.box<String>(_userBoxName);
    final jsonList = history.map((d) => d.toJson()).toList();
    await box.put('approved_pair_history', jsonEncode(jsonList));
  }

  static List<UserProfile> getApprovedPairHistory() {
    if (!Hive.isBoxOpen(_userBoxName)) return [];
    final box = Hive.box<String>(_userBoxName);
    final jsonStr = box.get('approved_pair_history');
    if (jsonStr == null) return [];
    try {
      final List list = jsonDecode(jsonStr);
      return list.map((item) => UserProfile.fromJson(item)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> clearAll() async {
    if (Hive.isBoxOpen(_userBoxName)) {
      await Hive.box<String>(_userBoxName).clear();
    }
    if (Hive.isBoxOpen(_chatBoxName)) {
      await Hive.box<String>(_chatBoxName).clear();
    }
  }

  // --- Local Encrypted Chat Storage ---
  static Future<void> saveChatMessage(ChatMessage message) async {
    if (!Hive.isBoxOpen(_chatBoxName)) return;
    final box = Hive.box<String>(_chatBoxName);
    await box.put(message.id, jsonEncode(message.toJson()));
  }

  static List<ChatMessage> getChatHistory() {
    if (!Hive.isBoxOpen(_chatBoxName)) return [];
    final box = Hive.box<String>(_chatBoxName);
    final cutoffDate = DateTime.now().subtract(const Duration(days: 90));
    final List<ChatMessage> messages = [];
    final List<dynamic> keysToDelete = [];

    for (var key in box.keys) {
      final jsonStr = box.get(key);
      if (jsonStr != null) {
        try {
          final msg = ChatMessage.fromJson(jsonDecode(jsonStr));
          // Delete messages older than 90 days or legacy motion alert test messages from chat storage
          if (msg.timestamp.isBefore(cutoffDate) || msg.text.contains('HAREKET ALGILANDI')) {
            keysToDelete.add(key);
          } else {
            messages.add(msg);
          }
        } catch (_) {}
      }
    }

    for (final key in keysToDelete) {
      box.delete(key);
    }

    messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return messages;
  }

  // --- Local Encrypted Group Chat Storage ---
  static Future<void> saveGroupChatMessage(ChatMessage message) async {
    if (!Hive.isBoxOpen(_groupChatBoxName)) return;
    final box = Hive.box<String>(_groupChatBoxName);
    await box.put(message.id, jsonEncode(message.toJson()));
  }

  static List<ChatMessage> getGroupChatHistory() {
    if (!Hive.isBoxOpen(_groupChatBoxName)) return [];
    final box = Hive.box<String>(_groupChatBoxName);
    final cutoffDate = DateTime.now().subtract(const Duration(days: 90));
    final List<ChatMessage> messages = [];
    final List<dynamic> keysToDelete = [];

    for (var key in box.keys) {
      final jsonStr = box.get(key);
      if (jsonStr != null) {
        try {
          final msg = ChatMessage.fromJson(jsonDecode(jsonStr));
          if (msg.timestamp.isBefore(cutoffDate) || msg.text == '__SYSTEM_CLEAR_GROUP_CHAT__') {
            keysToDelete.add(key);
          } else {
            messages.add(msg);
          }
        } catch (_) {}
      }
    }

    for (final key in keysToDelete) {
      box.delete(key);
    }

    messages.sort((a, b) => a.timestamp.compareTo(b.timestamp));
    return messages;
  }

  static Future<void> deleteChatMessage(String id) async {
    if (!Hive.isBoxOpen(_chatBoxName)) return;
    final box = Hive.box<String>(_chatBoxName);
    await box.delete(id);
  }

  static Future<void> deleteGroupChatMessage(String id) async {
    if (!Hive.isBoxOpen(_groupChatBoxName)) return;
    final box = Hive.box<String>(_groupChatBoxName);
    await box.delete(id);
  }

  static Future<void> clearGroupChatHistory() async {
    if (!Hive.isBoxOpen(_groupChatBoxName)) return;
    final box = Hive.box<String>(_groupChatBoxName);
    await box.clear();
  }

  static Future<void> clearChatHistoryForContact(String contactId, String contactPin) async {
    if (!Hive.isBoxOpen(_chatBoxName)) return;
    final box = Hive.box<String>(_chatBoxName);
    final cleanPin = contactPin.isNotEmpty ? contactPin : contactId.split('_').last;
    final List<dynamic> keysToDelete = [];

    for (var key in box.keys) {
      final jsonStr = box.get(key);
      if (jsonStr != null) {
        try {
          final msg = ChatMessage.fromJson(jsonDecode(jsonStr));
          final senderPin = msg.senderId.split('_').last;
          final receiverPin = msg.receiverId.split('_').last;
          final isMatch = msg.senderId == contactId ||
              msg.receiverId == contactId ||
              (cleanPin.isNotEmpty && (senderPin == cleanPin || receiverPin == cleanPin));
          if (isMatch) {
            keysToDelete.add(key);
          }
        } catch (_) {}
      }
    }

    for (final key in keysToDelete) {
      await box.delete(key);
    }
  }

  // --- Favorite Device ID Storage ---
  static Future<void> saveFavoriteDeviceId(String? id) async {
    if (!Hive.isBoxOpen(_userBoxName)) return;
    final box = Hive.box<String>(_userBoxName);
    if (id == null) {
      await box.delete('favorite_device_id');
    } else {
      await box.put('favorite_device_id', id);
    }
  }

  static String? getFavoriteDeviceId() {
    if (!Hive.isBoxOpen(_userBoxName)) return null;
    final box = Hive.box<String>(_userBoxName);
    return box.get('favorite_device_id');
  }

  // --- Local Persistent Call History Storage (2 Months Retention Rule) ---
  static Future<void> saveCallLog(CallLog log) async {
    if (!Hive.isBoxOpen(_callLogBoxName)) return;
    final box = Hive.box<String>(_callLogBoxName);
    await box.put(log.id, jsonEncode(log.toJson()));
  }

  static List<CallLog> getCallLogs() {
    if (!Hive.isBoxOpen(_callLogBoxName)) return [];
    final box = Hive.box<String>(_callLogBoxName);
    // 2-month retention rule (60 days)
    final cutoffDate = DateTime.now().subtract(const Duration(days: 60));
    final List<CallLog> logs = [];
    final List<dynamic> keysToDelete = [];

    for (var key in box.keys) {
      final jsonStr = box.get(key);
      if (jsonStr != null) {
        try {
          final log = CallLog.fromJson(jsonDecode(jsonStr));
          if (log.timestamp.isBefore(cutoffDate)) {
            keysToDelete.add(key);
          } else {
            logs.add(log);
          }
        } catch (_) {}
      }
    }

    for (final key in keysToDelete) {
      box.delete(key);
    }

    // Sort newest first
    logs.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return logs;
  }
}
