import 'package:intl/intl.dart';
import 'user_profile.dart';
import 'call_session.dart';

enum CallDirection { incoming, outgoing, missed }

class CallLog {
  final String id;
  final String deviceId;
  final String deviceName;
  final DeviceRole role;
  final CallType callType;
  final CallDirection direction;
  final DateTime timestamp;
  final int durationSeconds;

  CallLog({
    required this.id,
    required this.deviceId,
    required this.deviceName,
    required this.role,
    required this.callType,
    required this.direction,
    required this.timestamp,
    required this.durationSeconds,
  });

  /// Format timestamp to user-friendly Turkish string (e.g. "Bugün 17:42", "Dün 20:15", "04 Ağustos 19:10")
  String get formattedTime {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final logDate = DateTime(timestamp.year, timestamp.month, timestamp.day);

    final timeStr = DateFormat('HH:mm').format(timestamp);

    if (logDate == today) {
      return 'Bugün $timeStr';
    } else if (logDate == yesterday) {
      return 'Dün $timeStr';
    } else {
      try {
        return DateFormat('dd MMMM HH:mm', 'tr_TR').format(timestamp);
      } catch (_) {
        return '${timestamp.day}.${timestamp.month}.${timestamp.year} $timeStr';
      }
    }
  }

  /// Format duration to user-friendly Turkish string (e.g. "4dk 12sn", "45sn", "(Cevapsız Arama)")
  String get formattedDuration {
    if (direction == CallDirection.missed || durationSeconds <= 0) {
      return 'Cevapsız Arama';
    }

    final minutes = durationSeconds ~/ 60;
    final seconds = durationSeconds % 60;

    if (minutes > 0 && seconds > 0) {
      return '${minutes}dk ${seconds}sn';
    } else if (minutes > 0) {
      return '${minutes}dk';
    } else {
      return '${seconds}sn';
    }
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'deviceId': deviceId,
      'deviceName': deviceName,
      'role': role.name,
      'callType': callType.name,
      'direction': direction.name,
      'timestamp': timestamp.toIso8601String(),
      'durationSeconds': durationSeconds,
    };
  }

  factory CallLog.fromJson(Map<String, dynamic> json) {
    return CallLog(
      id: json['id'] ?? '',
      deviceId: json['deviceId'] ?? '',
      deviceName: json['deviceName'] ?? 'Cihaz',
      role: DeviceRole.values.firstWhere(
        (r) => r.name == json['role'],
        orElse: () => DeviceRole.parent,
      ),
      callType: CallType.values.firstWhere(
        (t) => t.name == json['callType'],
        orElse: () => CallType.audio,
      ),
      direction: CallDirection.values.firstWhere(
        (d) => d.name == json['direction'],
        orElse: () => CallDirection.outgoing,
      ),
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
      durationSeconds: json['durationSeconds'] ?? 0,
    );
  }
}
