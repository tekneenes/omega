enum CallStatus { calling, ringing, connected, ended, rejected, busy }

enum CallType { audio, video }

class CallSession {
  final String callId;
  final String callerId;
  final String callerName;
  final String receiverId;
  final CallType type;
  final CallStatus status;
  final Map<String, dynamic>? sdpOffer;
  final Map<String, dynamic>? sdpAnswer;
  final DateTime createdAt;

  CallSession({
    required this.callId,
    required this.callerId,
    required this.callerName,
    required this.receiverId,
    required this.type,
    this.status = CallStatus.calling,
    this.sdpOffer,
    this.sdpAnswer,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() {
    return {
      'callId': callId,
      'callerId': callerId,
      'callerName': callerName,
      'receiverId': receiverId,
      'type': type.name,
      'status': status.name,
      'sdpOffer': sdpOffer,
      'sdpAnswer': sdpAnswer,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory CallSession.fromJson(Map<String, dynamic> json) {
    return CallSession(
      callId: json['callId'] ?? '',
      callerId: json['callerId'] ?? '',
      callerName: json['callerName'] ?? 'Bilinmeyen Arayan',
      receiverId: json['receiverId'] ?? '',
      type: json['type'] == 'audio' ? CallType.audio : CallType.video,
      status: CallStatus.values.firstWhere(
        (e) => e.name == json['status'],
        orElse: () => CallStatus.calling,
      ),
      sdpOffer: json['sdpOffer'] != null
          ? Map<String, dynamic>.from(json['sdpOffer'])
          : null,
      sdpAnswer: json['sdpAnswer'] != null
          ? Map<String, dynamic>.from(json['sdpAnswer'])
          : null,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'])
          : DateTime.now(),
    );
  }

  CallSession copyWith({
    String? callId,
    String? callerId,
    String? callerName,
    String? receiverId,
    CallType? type,
    CallStatus? status,
    Map<String, dynamic>? sdpOffer,
    Map<String, dynamic>? sdpAnswer,
    DateTime? createdAt,
  }) {
    return CallSession(
      callId: callId ?? this.callId,
      callerId: callerId ?? this.callerId,
      callerName: callerName ?? this.callerName,
      receiverId: receiverId ?? this.receiverId,
      type: type ?? this.type,
      status: status ?? this.status,
      sdpOffer: sdpOffer ?? this.sdpOffer,
      sdpAnswer: sdpAnswer ?? this.sdpAnswer,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
