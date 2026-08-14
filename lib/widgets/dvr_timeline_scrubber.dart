import 'package:flutter/material.dart';

class DVRTimelineScrubber extends StatelessWidget {
  final bool isLive;
  final double secondsBehind; // e.g. 0.0 when LIVE, 10.0 when 10 seconds behind
  final double maxRewindSeconds; // e.g. 1800.0 (30 mins)
  final List<double> motionMarkerOffsets; // List of seconds behind live where motion occurred
  final ValueChanged<double> onSeek;
  final VoidCallback onGoLive;
  final VoidCallback onRewind10s;
  final VoidCallback onForward10s;

  const DVRTimelineScrubber({
    required this.isLive,
    required this.secondsBehind,
    required this.maxRewindSeconds,
    required this.motionMarkerOffsets,
    required this.onSeek,
    required this.onGoLive,
    required this.onRewind10s,
    required this.onForward10s,
    super.key,
  });

  String _formatOffset(double seconds) {
    if (seconds <= 1.0) return '🔴 CANLI';
    final int s = seconds.toInt();
    final int mins = s ~/ 60;
    final int secs = s % 60;
    final mStr = mins.toString().padLeft(2, '0');
    final sStr = secs.toString().padLeft(2, '0');
    return '-$mStr:$sStr';
  }

  @override
  Widget build(BuildContext context) {
    // Current slider value: 0.0 is maxRewind (far past), maxRewindSeconds is 0 (LIVE)
    final currentValue = (maxRewindSeconds - secondsBehind).clamp(0.0, maxRewindSeconds);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 16,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top Row: Status Time Offset & Go Live Button
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isLive ? Colors.red.withValues(alpha: 0.2) : Colors.amber.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: isLive ? Colors.redAccent : Colors.amber),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isLive ? Colors.redAccent : Colors.amber,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _formatOffset(secondsBehind),
                      style: TextStyle(
                        color: isLive ? Colors.redAccent : Colors.amber,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              if (!isLive)
                ElevatedButton.icon(
                  onPressed: onGoLive,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00E676),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: const Icon(Icons.fiber_manual_record, color: Colors.red, size: 12),
                  label: const Text('CANLI YAYINA DÖN', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11)),
                ),
            ],
          ),
          const SizedBox(height: 8),

          // Middle: Interactive YouTube DVR Timeline Scrubber with Motion Markers
          Stack(
            alignment: Alignment.center,
            children: [
              // Custom Track for Motion Markers (Amber/Red vertical lines)
              Positioned.fill(
                child: CustomPaint(
                  painter: _DVRTrackPainter(
                    motionMarkerOffsets: motionMarkerOffsets,
                    maxRewindSeconds: maxRewindSeconds,
                  ),
                ),
              ),

              // Slider
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 6,
                  activeTrackColor: isLive ? Colors.redAccent : Colors.amber,
                  inactiveTrackColor: Colors.white24,
                  thumbColor: isLive ? Colors.redAccent : Colors.amber,
                  overlayColor: (isLive ? Colors.red : Colors.amber).withValues(alpha: 0.2),
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                  trackShape: const RectangularSliderTrackShape(),
                ),
                child: Slider(
                  value: currentValue,
                  min: 0.0,
                  max: maxRewindSeconds,
                  onChanged: (val) {
                    final newBehind = (maxRewindSeconds - val).clamp(0.0, maxRewindSeconds);
                    onSeek(newBehind);
                  },
                ),
              ),
            ],
          ),

          // Bottom Controls: -10s | Play/Pause | +10s
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              IconButton(
                onPressed: onRewind10s,
                icon: const Icon(Icons.replay_10_rounded, color: Colors.white),
                tooltip: '10s Gerile',
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Text('DVR Timeline (Canlı Akış)',
                  style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
              ),
              IconButton(
                onPressed: onForward10s,
                icon: const Icon(Icons.forward_10_rounded, color: Colors.white),
                tooltip: '10s İleri',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DVRTrackPainter extends CustomPainter {
  final List<double> motionMarkerOffsets;
  final double maxRewindSeconds;

  _DVRTrackPainter({required this.motionMarkerOffsets, required this.maxRewindSeconds});

  @override
  void paint(Canvas canvas, Size size) {
    if (maxRewindSeconds <= 0) return;

    final paint = Paint()
      ..color = Colors.amberAccent
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final double padding = 16.0;
    final double availableWidth = size.width - (padding * 2);

    for (final offset in motionMarkerOffsets) {
      final floatPos = (maxRewindSeconds - offset) / maxRewindSeconds;
      if (floatPos >= 0.0 && floatPos <= 1.0) {
        final x = padding + (floatPos * availableWidth);
        canvas.drawLine(
          Offset(x, 2),
          Offset(x, size.height - 2),
          paint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DVRTrackPainter oldDelegate) {
    return oldDelegate.motionMarkerOffsets != motionMarkerOffsets ||
        oldDelegate.maxRewindSeconds != maxRewindSeconds;
  }
}
