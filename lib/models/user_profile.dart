enum DeviceRole { tablet, parent }
enum PairingMethod { pinCode, phoneNumber, email }
enum PairRequestResult { success, alreadyPaired, alreadyPending, selfPair, blocked, error }

class UserProfile {
  final String id;
  final String deviceName;
  final DeviceRole role;
  final String pairCode;
  final String? pairedDeviceId;
  final String? fcmToken;
  final String avatarIcon;
  final String? photoBase64; // Profile photo as base64 string (shared via Firebase)
  final bool sharePhoto; // Privacy: whether to share photo with paired devices
  final bool isOnline;
  final DateTime lastSeen;
  final int batteryLevel;
  final bool isCharging;
  final String wifiSignal;
  final String? email;
  final String? phoneNumber;

  UserProfile({
    required this.id,
    required this.deviceName,
    required this.role,
    required this.pairCode,
    this.pairedDeviceId,
    this.fcmToken,
    this.avatarIcon = 'tablet',
    this.photoBase64,
    this.sharePhoto = true,
    this.isOnline = true,
    required this.lastSeen,
    this.batteryLevel = 100,
    this.isCharging = false,
    this.wifiSignal = 'Güçlü',
    this.email,
    this.phoneNumber,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'deviceName': deviceName,
      'role': role.name,
      'pairCode': pairCode,
      'pairedDeviceId': pairedDeviceId,
      'fcmToken': fcmToken,
      'avatarIcon': avatarIcon,
      'photoBase64': photoBase64,
      'sharePhoto': sharePhoto,
      'isOnline': isOnline,
      'lastSeen': lastSeen.toIso8601String(),
      'batteryLevel': batteryLevel,
      'isCharging': isCharging,
      'wifiSignal': wifiSignal,
      'email': email,
      'phoneNumber': phoneNumber,
    };
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['id'] ?? '',
      deviceName: json['deviceName'] ?? 'Bilinmeyen Cihaz',
      role: json['role'] == 'tablet' ? DeviceRole.tablet : DeviceRole.parent,
      pairCode: json['pairCode'] ?? '',
      pairedDeviceId: json['pairedDeviceId'],
      fcmToken: json['fcmToken'],
      avatarIcon: json['avatarIcon'] ?? 'tablet',
      photoBase64: json['photoBase64'],
      sharePhoto: json['sharePhoto'] ?? true,
      isOnline: json['isOnline'] ?? true,
      lastSeen: json['lastSeen'] != null
          ? DateTime.parse(json['lastSeen'])
          : DateTime.now(),
      batteryLevel: json['batteryLevel'] ?? 100,
      isCharging: json['isCharging'] ?? false,
      wifiSignal: json['wifiSignal'] ?? 'Güçlü',
      email: json['email'],
      phoneNumber: json['phoneNumber'],
    );
  }

  UserProfile copyWith({
    String? id,
    String? deviceName,
    DeviceRole? role,
    String? pairCode,
    String? pairedDeviceId,
    String? fcmToken,
    String? avatarIcon,
    String? photoBase64,
    bool? sharePhoto,
    bool? isOnline,
    DateTime? lastSeen,
    int? batteryLevel,
    bool? isCharging,
    String? wifiSignal,
    String? email,
    String? phoneNumber,
  }) {
    return UserProfile(
      id: id ?? this.id,
      deviceName: deviceName ?? this.deviceName,
      role: role ?? this.role,
      pairCode: pairCode ?? this.pairCode,
      pairedDeviceId: pairedDeviceId ?? this.pairedDeviceId,
      fcmToken: fcmToken ?? this.fcmToken,
      avatarIcon: avatarIcon ?? this.avatarIcon,
      photoBase64: photoBase64 ?? this.photoBase64,
      sharePhoto: sharePhoto ?? this.sharePhoto,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      isCharging: isCharging ?? this.isCharging,
      wifiSignal: wifiSignal ?? this.wifiSignal,
      email: email ?? this.email,
      phoneNumber: phoneNumber ?? this.phoneNumber,
    );
  }
}
