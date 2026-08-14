import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

/// Manages continuous video recording of camera stream in 5-minute segments.
/// Automatically cleans up recordings older than 7 days.
/// Stores recording metadata in Hive for fast lookup.
class CameraRecordingService {
  static const String _boxName = 'camera_recordings_box';
  static const int _segmentDurationSeconds = 300; // 5 minutes per segment
  static const int _maxAgeDays = 7;

  MediaRecorder? _mediaRecorder;
  MediaStream? _stream;
  Timer? _segmentTimer;
  Timer? _cleanupTimer;
  String? _currentSegmentPath;
  DateTime? _currentSegmentStart;
  bool _isRecording = false;
  String _cameraDeviceId = '';

  // Motion detection timestamps (seconds since recording start)
  final List<DateTime> motionTimestamps = [];
  DateTime? recordingStartedAt;

  /// Initialize Hive box for recording metadata
  static Future<void> init() async {
    try {
      if (!Hive.isBoxOpen(_boxName)) {
        await Hive.openBox<String>(_boxName);
      }
    } catch (e) {
      debugPrint('⚠️ [RECORDING SERVICE] Hive init error: $e');
    }
  }

  /// Get the recordings directory
  Future<Directory> _getRecordingsDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final recordingsDir = Directory('${appDir.path}/camera_records');
    if (!await recordingsDir.exists()) {
      await recordingsDir.create(recursive: true);
    }
    return recordingsDir;
  }

  /// Start continuous recording of the given MediaStream
  Future<void> startRecording(MediaStream stream, {required String cameraDeviceId}) async {
    if (_isRecording) return;
    if (kIsWeb) {
      debugPrint('⚠️ [RECORDING] Web recording not supported in continuous mode');
      return;
    }

    _stream = stream;
    _cameraDeviceId = cameraDeviceId;
    _isRecording = true;
    recordingStartedAt = DateTime.now();

    debugPrint('🔴 [RECORDING] Starting continuous recording service');

    // Clean up old recordings first
    await cleanupOldRecords();

    // Start first segment
    await _startNewSegment();

    // Schedule segment rotation every 5 minutes
    _segmentTimer = Timer.periodic(
      const Duration(seconds: _segmentDurationSeconds),
      (_) => _rotateSegment(),
    );

    // Schedule daily cleanup check
    _cleanupTimer = Timer.periodic(
      const Duration(hours: 1),
      (_) => cleanupOldRecords(),
    );
  }

  /// Stop all recording
  Future<void> stopRecording() async {
    _isRecording = false;
    _segmentTimer?.cancel();
    _cleanupTimer?.cancel();

    try {
      await _mediaRecorder?.stop();
    } catch (e) {
      debugPrint('⚠️ [RECORDING] Stop error: $e');
    }

    // Save final segment metadata
    if (_currentSegmentPath != null && _currentSegmentStart != null) {
      await _saveSegmentMetadata(
        path: _currentSegmentPath!,
        startTime: _currentSegmentStart!,
        endTime: DateTime.now(),
      );
    }

    _mediaRecorder = null;
    _currentSegmentPath = null;
    _currentSegmentStart = null;

    debugPrint('⏹ [RECORDING] Recording service stopped');
  }

  /// Start recording a new segment
  Future<void> _startNewSegment() async {
    if (_stream == null || !_isRecording) return;

    final videoTracks = _stream!.getVideoTracks();
    if (videoTracks.isEmpty) {
      debugPrint('⚠️ [RECORDING] No video tracks available');
      return;
    }

    final now = DateTime.now();
    final recordingsDir = await _getRecordingsDir();

    // Create date subdirectory
    final dateStr = '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final dateDir = Directory('${recordingsDir.path}/$dateStr');
    if (!await dateDir.exists()) {
      await dateDir.create(recursive: true);
    }

    final timeStr = '${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}-${now.second.toString().padLeft(2, '0')}';
    final filePath = '${dateDir.path}/$timeStr.mp4';

    try {
      _mediaRecorder = MediaRecorder();
      await _mediaRecorder!.start(
        filePath,
        videoTrack: videoTracks.first,
        audioChannel: RecorderAudioChannel.INPUT,
      );

      _currentSegmentPath = filePath;
      _currentSegmentStart = now;

      debugPrint('🎬 [RECORDING] New segment started: $filePath');
    } catch (e) {
      debugPrint('❌ [RECORDING] Failed to start segment: $e');
    }
  }

  /// Rotate to a new segment (stop current, save metadata, start new)
  Future<void> _rotateSegment() async {
    if (!_isRecording) return;

    debugPrint('🔄 [RECORDING] Rotating segment...');

    // Stop current segment
    try {
      await _mediaRecorder?.stop();
    } catch (e) {
      debugPrint('⚠️ [RECORDING] Segment stop error: $e');
    }

    // Save metadata for completed segment
    if (_currentSegmentPath != null && _currentSegmentStart != null) {
      await _saveSegmentMetadata(
        path: _currentSegmentPath!,
        startTime: _currentSegmentStart!,
        endTime: DateTime.now(),
      );
    }

    // Start new segment
    await _startNewSegment();
  }

  /// Save segment metadata to Hive
  Future<void> _saveSegmentMetadata({
    required String path,
    required DateTime startTime,
    required DateTime endTime,
  }) async {
    try {
      if (!Hive.isBoxOpen(_boxName)) return;
      final box = Hive.box<String>(_boxName);

      final metadata = {
        'path': path,
        'startTime': startTime.toIso8601String(),
        'endTime': endTime.toIso8601String(),
        'cameraDeviceId': _cameraDeviceId,
        'motionEvents': motionTimestamps
            .where((t) => t.isAfter(startTime) && t.isBefore(endTime))
            .map((t) => t.toIso8601String())
            .toList(),
      };

      final key = 'seg_${startTime.millisecondsSinceEpoch}';
      await box.put(key, jsonEncode(metadata));

      debugPrint('💾 [RECORDING] Segment metadata saved: $key');
    } catch (e) {
      debugPrint('⚠️ [RECORDING] Metadata save error: $e');
    }
  }

  /// Add a motion detection timestamp
  void addMotionTimestamp() {
    motionTimestamps.add(DateTime.now());
  }

  /// Get all saved recording segments, newest first
  static List<Map<String, dynamic>> getAllRecordings() {
    try {
      if (!Hive.isBoxOpen(_boxName)) return [];
      final box = Hive.box<String>(_boxName);
      final List<Map<String, dynamic>> recordings = [];

      for (final key in box.keys) {
        final jsonStr = box.get(key);
        if (jsonStr != null) {
          try {
            recordings.add(jsonDecode(jsonStr) as Map<String, dynamic>);
          } catch (_) {}
        }
      }

      // Sort newest first
      recordings.sort((a, b) {
        final aTime = DateTime.parse(a['startTime'] as String);
        final bTime = DateTime.parse(b['startTime'] as String);
        return bTime.compareTo(aTime);
      });

      return recordings;
    } catch (e) {
      debugPrint('⚠️ [RECORDING] Get recordings error: $e');
      return [];
    }
  }

  /// Get recordings grouped by date
  static Map<String, List<Map<String, dynamic>>> getRecordingsGroupedByDate() {
    final all = getAllRecordings();
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final rec in all) {
      final startTime = DateTime.parse(rec['startTime'] as String);
      final dateKey = '${startTime.year}-${startTime.month.toString().padLeft(2, '0')}-${startTime.day.toString().padLeft(2, '0')}';
      grouped.putIfAbsent(dateKey, () => []).add(rec);
    }

    return grouped;
  }

  /// Clean up recordings older than 7 days
  Future<void> cleanupOldRecords() async {
    final cutoff = DateTime.now().subtract(const Duration(days: _maxAgeDays));

    try {
      if (!Hive.isBoxOpen(_boxName)) return;
      final box = Hive.box<String>(_boxName);
      final keysToDelete = <dynamic>[];

      for (final key in box.keys) {
        final jsonStr = box.get(key);
        if (jsonStr == null) continue;

        try {
          final meta = jsonDecode(jsonStr) as Map<String, dynamic>;
          final startTime = DateTime.parse(meta['startTime'] as String);

          if (startTime.isBefore(cutoff)) {
            // Delete file from disk
            final filePath = meta['path'] as String?;
            if (filePath != null) {
              final file = File(filePath);
              if (await file.exists()) {
                await file.delete();
                debugPrint('🗑 [RECORDING CLEANUP] Deleted old file: $filePath');
              }
            }
            keysToDelete.add(key);
          }
        } catch (_) {}
      }

      for (final key in keysToDelete) {
        await box.delete(key);
      }

      if (keysToDelete.isNotEmpty) {
        debugPrint('🗑 [RECORDING CLEANUP] Removed ${keysToDelete.length} old recordings (>$_maxAgeDays days)');
      }

      // Also clean empty date directories
      final recordingsDir = await _getRecordingsDir();
      if (await recordingsDir.exists()) {
        await for (final entity in recordingsDir.list()) {
          if (entity is Directory) {
            final children = await entity.list().toList();
            if (children.isEmpty) {
              await entity.delete();
            }
          }
        }
      }
    } catch (e) {
      debugPrint('⚠️ [RECORDING CLEANUP] Error: $e');
    }
  }
}
