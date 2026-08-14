import 'dart:io';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';
import '../services/camera_recording_service.dart';

class RecordingsGalleryScreen extends StatefulWidget {
  const RecordingsGalleryScreen({super.key});

  @override
  State<RecordingsGalleryScreen> createState() => _RecordingsGalleryScreenState();
}

class _RecordingsGalleryScreenState extends State<RecordingsGalleryScreen> {
  Map<String, List<Map<String, dynamic>>> _grouped = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRecordings();
  }

  void _loadRecordings() {
    setState(() => _isLoading = true);
    final grouped = CameraRecordingService.getRecordingsGroupedByDate();
    setState(() {
      _grouped = grouped;
      _isLoading = false;
    });
  }

  String _formatDate(String dateKey) {
    try {
      final date = DateTime.parse(dateKey);
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final yesterday = today.subtract(const Duration(days: 1));
      final recDate = DateTime(date.year, date.month, date.day);

      if (recDate == today) return 'Bugün';
      if (recDate == yesterday) return 'Dün';
      return DateFormat('dd MMMM yyyy, EEEE', 'tr').format(date);
    } catch (_) {
      return dateKey;
    }
  }

  String _formatTimeRange(Map<String, dynamic> rec) {
    try {
      final start = DateTime.parse(rec['startTime'] as String);
      final end = DateTime.parse(rec['endTime'] as String);
      final startStr = DateFormat('HH:mm:ss').format(start);
      final endStr = DateFormat('HH:mm:ss').format(end);
      final duration = end.difference(start);
      final durStr = '${duration.inMinutes} dk ${duration.inSeconds % 60} sn';
      return '$startStr → $endStr ($durStr)';
    } catch (_) {
      return 'Bilinmeyen zaman';
    }
  }

  int _getMotionCount(Map<String, dynamic> rec) {
    final events = rec['motionEvents'] as List<dynamic>?;
    return events?.length ?? 0;
  }

  Future<bool> _fileExists(String path) async {
    return await File(path).exists();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E21),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Row(
          children: [
            Icon(Icons.videocam_rounded, color: Colors.redAccent, size: 24),
            SizedBox(width: 8),
            Text('Kamera Kayıtları',
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          IconButton(
            onPressed: _loadRecordings,
            icon: const Icon(Icons.refresh_rounded, color: Colors.white70),
            tooltip: 'Yenile',
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.redAccent))
          : _grouped.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.videocam_off_rounded, size: 64, color: Colors.white24),
                      const SizedBox(height: 16),
                      const Text('Henüz kayıt yok',
                          style: TextStyle(color: Colors.white54, fontSize: 18)),
                      const SizedBox(height: 8),
                      const Text('Kamera modu açıldığında otomatik kayıt başlar',
                          style: TextStyle(color: Colors.white30, fontSize: 13)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _grouped.keys.length,
                  itemBuilder: (context, dateIndex) {
                    final dateKey = _grouped.keys.toList()[dateIndex];
                    final segments = _grouped[dateKey]!;

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Date Header
                        Container(
                          margin: EdgeInsets.only(bottom: 12, top: dateIndex > 0 ? 24 : 0),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today_rounded, color: Colors.white54, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                _formatDate(dateKey),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.redAccent.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${segments.length} segment',
                                  style: const TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Segment Cards
                        ...segments.map((rec) {
                          final motionCount = _getMotionCount(rec);
                          final filePath = rec['path'] as String? ?? '';

                          return FutureBuilder<bool>(
                            future: _fileExists(filePath),
                            builder: (context, snapshot) {
                              final exists = snapshot.data ?? false;

                              return Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                decoration: BoxDecoration(
                                  color: Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: motionCount > 0
                                        ? Colors.amber.withValues(alpha: 0.4)
                                        : Colors.white.withValues(alpha: 0.1),
                                  ),
                                ),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                  leading: Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                      color: motionCount > 0
                                          ? Colors.amber.withValues(alpha: 0.2)
                                          : Colors.redAccent.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(
                                      motionCount > 0
                                          ? Icons.warning_amber_rounded
                                          : Icons.videocam_rounded,
                                      color: motionCount > 0 ? Colors.amber : Colors.redAccent,
                                    ),
                                  ),
                                  title: Text(
                                    _formatTimeRange(rec),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      if (motionCount > 0)
                                        Row(
                                          children: [
                                            const Icon(Icons.directions_run_rounded, size: 14, color: Colors.amber),
                                            const SizedBox(width: 4),
                                            Text(
                                              '$motionCount hareket algılandı',
                                              style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                      if (!exists)
                                        const Text(
                                          'Dosya silinmiş',
                                          style: TextStyle(color: Colors.red, fontSize: 11),
                                        ),
                                    ],
                                  ),
                                  trailing: exists
                                      ? const Icon(Icons.play_circle_outline_rounded, color: Colors.white54, size: 32)
                                      : const Icon(Icons.broken_image_outlined, color: Colors.red, size: 28),
                                  onTap: exists
                                      ? () {
                                          Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) => _VideoPlayerScreen(
                                                filePath: filePath,
                                                title: _formatTimeRange(rec),
                                                motionEvents: (rec['motionEvents'] as List<dynamic>?)
                                                        ?.map((e) => DateTime.parse(e as String))
                                                        .toList() ??
                                                    [],
                                                segmentStart: DateTime.parse(rec['startTime'] as String),
                                              ),
                                            ),
                                          );
                                        }
                                      : null,
                                ),
                              );
                            },
                          );
                        }),
                      ],
                    );
                  },
                ),
    );
  }
}

/// Full-screen video player for a single recording segment
class _VideoPlayerScreen extends StatefulWidget {
  final String filePath;
  final String title;
  final List<DateTime> motionEvents;
  final DateTime segmentStart;

  const _VideoPlayerScreen({
    required this.filePath,
    required this.title,
    required this.motionEvents,
    required this.segmentStart,
  });

  @override
  State<_VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<_VideoPlayerScreen> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.file(File(widget.filePath))
      ..initialize().then((_) {
        setState(() => _isInitialized = true);
        _controller.play();
      }).catchError((e) {
        debugPrint('❌ [VIDEO PLAYER] Init error: $e');
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final mins = d.inMinutes.toString().padLeft(2, '0');
    final secs = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(widget.title, style: const TextStyle(color: Colors.white, fontSize: 14)),
      ),
      body: Column(
        children: [
          // Video
          Expanded(
            child: _isInitialized
                ? Center(
                    child: AspectRatio(
                      aspectRatio: _controller.value.aspectRatio,
                      child: VideoPlayer(_controller),
                    ),
                  )
                : const Center(child: CircularProgressIndicator(color: Colors.redAccent)),
          ),

          // Controls
          if (_isInitialized)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.black,
              child: Column(
                children: [
                  // Progress bar with motion markers
                  Stack(
                    children: [
                      // Motion event markers
                      if (_controller.value.duration.inSeconds > 0)
                        ...widget.motionEvents.map((event) {
                          final offsetSeconds = event.difference(widget.segmentStart).inSeconds;
                          final fraction = offsetSeconds / _controller.value.duration.inSeconds;
                          if (fraction < 0 || fraction > 1) return const SizedBox.shrink();
                          return Positioned(
                            left: fraction * (MediaQuery.of(context).size.width - 32),
                            top: 0,
                            bottom: 0,
                            child: Container(
                              width: 3,
                              color: Colors.amber,
                            ),
                          );
                        }),

                      // Seek bar
                      VideoProgressIndicator(
                        _controller,
                        allowScrubbing: true,
                        colors: const VideoProgressColors(
                          playedColor: Colors.redAccent,
                          bufferedColor: Colors.white24,
                          backgroundColor: Colors.white12,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                    ],
                  ),

                  // Time + Play/Pause
                  ValueListenableBuilder(
                    valueListenable: _controller,
                    builder: (context, VideoPlayerValue value, child) {
                      return Row(
                        children: [
                          Text(
                            _formatDuration(value.position),
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '/ ${_formatDuration(value.duration)}',
                            style: const TextStyle(color: Colors.white38, fontSize: 12),
                          ),
                          const Spacer(),

                          // Rewind 10s
                          IconButton(
                            onPressed: () {
                              final pos = value.position - const Duration(seconds: 10);
                              _controller.seekTo(pos < Duration.zero ? Duration.zero : pos);
                            },
                            icon: const Icon(Icons.replay_10_rounded, color: Colors.white),
                          ),

                          // Play/Pause
                          IconButton(
                            onPressed: () {
                              value.isPlaying ? _controller.pause() : _controller.play();
                            },
                            icon: Icon(
                              value.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                              color: Colors.white,
                              size: 36,
                            ),
                          ),

                          // Forward 10s
                          IconButton(
                            onPressed: () {
                              final pos = value.position + const Duration(seconds: 10);
                              _controller.seekTo(pos > value.duration ? value.duration : pos);
                            },
                            icon: const Icon(Icons.forward_10_rounded, color: Colors.white),
                          ),
                        ],
                      );
                    },
                  ),

                  // Motion Events Summary
                  if (widget.motionEvents.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.directions_run_rounded, color: Colors.amber, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            '${widget.motionEvents.length} hareket algılandı bu segmentte',
                            style: const TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
