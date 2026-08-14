class MotionRecord {
  final String id;
  final String cameraDeviceId;
  final String cameraDeviceName;
  final DateTime timestamp;
  final String? videoPath;
  final String? snapshotBase64;
  final int durationSeconds;

  MotionRecord({
    required this.id,
    required this.cameraDeviceId,
    required this.cameraDeviceName,
    required this.timestamp,
    this.videoPath,
    this.snapshotBase64,
    this.durationSeconds = 10,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'cameraDeviceId': cameraDeviceId,
        'cameraDeviceName': cameraDeviceName,
        'timestamp': timestamp.toIso8601String(),
        'videoPath': videoPath,
        'snapshotBase64': snapshotBase64,
        'durationSeconds': durationSeconds,
      };

  factory MotionRecord.fromJson(Map<String, dynamic> json) => MotionRecord(
        id: json['id'] as String? ?? '',
        cameraDeviceId: json['cameraDeviceId'] as String? ?? '',
        cameraDeviceName: json['cameraDeviceName'] as String? ?? '',
        timestamp: DateTime.parse(json['timestamp'] as String? ?? DateTime.now().toIso8601String()),
        videoPath: json['videoPath'] as String?,
        snapshotBase64: json['snapshotBase64'] as String?,
        durationSeconds: json['durationSeconds'] as int? ?? 10,
      );
}
