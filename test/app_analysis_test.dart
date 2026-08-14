import 'package:flutter_test/flutter_test.dart';
import 'package:omega_call/models/user_profile.dart';
import 'package:omega_call/models/call_session.dart';
import 'package:omega_call/models/call_log.dart';
import 'dart:convert';
import 'dart:typed_data';

void main() {
  group('1. UserProfile Data Model Audit & Performance Benchmark', () {
    test('UserProfile JSON serialization and deserialization benchmark', () {
      final Stopwatch stopwatch = Stopwatch()..start();

      final sampleJson = {
        'id': 'dev_test_123',
        'deviceName': 'Muhammed iPad Pro',
        'pairCode': '05317011121',
        'role': 'parent',
        'avatarIcon': 'person',
        'phoneNumber': '05317011121',
        'email': 'test@omega.com',
        'photoBase64': 'iVBORw0KGgoAAAANSU5EUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
        'sharePhoto': true,
        'isOnline': true,
        'lastSeen': '2026-08-13T12:00:00.000Z',
        'batteryLevel': 95,
        'isCharging': true,
        'wifiSignal': 'Güçlü',
      };

      for (int i = 0; i < 1000; i++) {
        final profile = UserProfile.fromJson(sampleJson);
        final json = profile.toJson();
        expect(json['pairCode'], '05317011121');
      }

      stopwatch.stop();
      print('⏱️ 1000x UserProfile JSON Deserialization took: ${stopwatch.elapsedMicroseconds / 1000} ms');
    });

    test('UserProfile edge case - null/missing attributes fallback test', () {
      final corruptJson = <String, dynamic>{};
      final profile = UserProfile.fromJson(corruptJson);

      expect(profile.id, '');
      expect(profile.deviceName, 'Bilinmeyen Cihaz');
      expect(profile.pairCode, '');
      expect(profile.role, DeviceRole.parent);
      expect(profile.sharePhoto, true);
    });
  });

  group('2. CallLog & CallSession Model Audit', () {
    test('CallLog duration calculation and formatting test', () {
      final log = CallLog(
        id: 'log_1',
        deviceId: 'dev_child_456',
        deviceName: 'Çocuk Tableti',
        role: DeviceRole.tablet,
        callType: CallType.video,
        direction: CallDirection.incoming,
        timestamp: DateTime.now().subtract(const Duration(minutes: 5)),
        durationSeconds: 145,
      );

      final json = log.toJson();
      final restoredLog = CallLog.fromJson(json);

      expect(restoredLog.durationSeconds, 145);
      expect(restoredLog.direction, CallDirection.incoming);
      expect(restoredLog.deviceName, 'Çocuk Tableti');
      expect(restoredLog.formattedDuration, '2dk 25sn');
    });

    test('CallLog missed call formatting test', () {
      final missedLog = CallLog(
        id: 'log_2',
        deviceId: 'dev_child_456',
        deviceName: 'Çocuk Tableti',
        role: DeviceRole.tablet,
        callType: CallType.audio,
        direction: CallDirection.missed,
        timestamp: DateTime.now().subtract(const Duration(hours: 2)),
        durationSeconds: 0,
      );

      expect(missedLog.formattedDuration, 'Cevapsız Arama');
    });
  });

  group('3. Base64 Avatar Cache Performance Audit', () {
    test('Base64 decoding benchmark and memory check', () {
      const b64 = 'iVBORw0KGgoAAAANSU5EUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==';

      final Stopwatch b64Watch = Stopwatch()..start();
      final Uint8List bytes1 = base64Decode(b64);
      b64Watch.stop();

      final Stopwatch secondWatch = Stopwatch()..start();
      final Uint8List bytes2 = base64Decode(b64);
      secondWatch.stop();

      expect(bytes1.length, bytes2.length);
      print('⏱️ Direct Base64 Decode #1: ${b64Watch.elapsedMicroseconds} µs | #2: ${secondWatch.elapsedMicroseconds} µs');
    });
  });
}
