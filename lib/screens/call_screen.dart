import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../models/call_session.dart';
import '../providers/app_state_provider.dart';
import '../services/proximity_service.dart';
import '../widgets/profile_avatar.dart';

class CallScreen extends StatefulWidget {
  const CallScreen({super.key});

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> {
  Timer? _durationTimer;
  int _secondsElapsed = 0;
  StreamSubscription<bool>? _proximitySubscription;
  bool _isNearEar = false;
  bool _areControlsVisible = true;
  Timer? _autoHideTimer;

  void _resetAutoHideTimer() {
    _autoHideTimer?.cancel();
    _autoHideTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() {
          _areControlsVisible = false;
        });
      }
    });
  }

  void _toggleControlsVisibility() {
    setState(() {
      _areControlsVisible = !_areControlsVisible;
    });
    if (_areControlsVisible) {
      _resetAutoHideTimer();
    } else {
      _autoHideTimer?.cancel();
    }
  }

  @override
  void initState() {
    super.initState();
    _proximitySubscription = ProximityService().isNearStream.listen((isNear) {
      if (mounted) {
        setState(() {
          _isNearEar = isNear;
        });
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkTimer();
      _manageProximity();
      _resetAutoHideTimer();
    });
  }

  void _manageProximity() {
    final appState = Provider.of<AppStateProvider>(context, listen: false);
    final isSpeakerOn = appState.webRTCService.isSpeakerphoneOn;
    if (!isSpeakerOn) {
      ProximityService().startListening();
    } else {
      ProximityService().stopListening();
    }
  }

  void _checkTimer() {
    final appState = Provider.of<AppStateProvider>(context, listen: false);
    if (appState.activeCall?.status == CallStatus.connected) {
      _startTimer();
    }
  }

  void _startTimer() {
    if (_durationTimer != null) return;
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() {
          _secondsElapsed++;
        });
      }
    });
  }

  @override
  void dispose() {
    _durationTimer?.cancel();
    _autoHideTimer?.cancel();
    _proximitySubscription?.cancel();
    ProximityService().stopListening();
    super.dispose();
  }

  String _formatDuration(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final mStr = minutes.toString().padLeft(2, '0');
    final sStr = seconds.toString().padLeft(2, '0');
    return '$mStr:$sStr';
  }

  Widget _buildControlButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.15),
          shape: BoxShape.circle,
        ),
        child: Icon(
          icon,
          color: color,
          size: 30,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppStateProvider>(context);
    final session = appState.activeCall;
    final pairedName = appState.pairedProfile?.deviceName ?? 'Arama';
    final isVideo = session?.type == CallType.video;
    final isConnected = session?.status == CallStatus.connected;

    if (isConnected && _durationTimer == null) {
      _startTimer();
    }

    if (appState.webRTCService.remoteRenderer.srcObject == null &&
        appState.webRTCService.remoteStream != null) {
      appState.webRTCService.remoteRenderer.srcObject =
          appState.webRTCService.remoteStream;
    }
    if (appState.webRTCService.localRenderer.srcObject == null &&
        appState.webRTCService.localStream != null) {
      appState.webRTCService.localRenderer.srcObject =
          appState.webRTCService.localStream;
    }

    return Scaffold(
      backgroundColor: const Color(0xFF384353),
      body: SafeArea(
        child: Stack(
          children: [
            // --- ALWAYS-MOUNTED Remote Video / Audio Surface with Tap-to-Toggle Controls ---
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  if (isVideo && isConnected) {
                    _toggleControlsVisibility();
                  }
                },
                child: RTCVideoView(
                  appState.webRTCService.remoteRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
            ),

            // --- Overlay: shown during calling/audio, hidden when video connects ---
            if (!isVideo || !isConnected)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (isVideo && isConnected) {
                      _toggleControlsVisibility();
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF5B6578), Color(0xFF384353)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ProfileAvatar(
                          profile: appState.pairedProfile,
                          radius: 60,
                          borderWidth: 3,
                          borderColor: Colors.white.withValues(alpha: 0.4),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          pairedName,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (isConnected) ...[
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF00E676),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 8),
                              ],
                              Text(
                                isConnected
                                    ? 'Görüşme Devam Ediyor (${_formatDuration(_secondsElapsed)})'
                                    : (session?.status == CallStatus.ended
                                        ? 'Arama Sonlandırıldı'
                                        : (session?.status == CallStatus.busy
                                            ? '⚠️ Başka Bir Görüşmede (Meşgul)'
                                            : (session?.status == CallStatus.rejected
                                                ? '⚠️ Cihaz Meşgul / Yanıtsız'
                                                : 'Aranıyor...'))),
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                  color: isConnected
                                      ? const Color(0xFF00E676)
                                      : (session?.status == CallStatus.ended ||
                                              session?.status == CallStatus.rejected ||
                                              session?.status == CallStatus.busy
                                          ? Colors.redAccent
                                          : Colors.white70),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // --- Connected Video Call Top Duration Badge (ALWAYS VISIBLE) ---
            if (isVideo && isConnected)
              Positioned(
                top: 20,
                left: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Color(0xFF00E676),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatDuration(_secondsElapsed),
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // --- Local Video PIP Thumbnail (ALWAYS VISIBLE) ---
            if (isVideo)
              Positioned(
                top: 20,
                right: 20,
                width: 100,
                height: 140,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    color: Colors.black54,
                    child: RTCVideoView(
                      appState.webRTCService.localRenderer,
                      mirror: true,
                      objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
              ),

            // --- Glassmorphic Floating Control Bar with Animated Slide & Auto-Hide ---
            Positioned(
              bottom: 30,
              left: 20,
              right: 20,
              child: AnimatedSlide(
                offset: (isVideo && isConnected && !_areControlsVisible)
                    ? const Offset(0, 2.5)
                    : Offset.zero,
                duration: const Duration(milliseconds: 350),
                curve: Curves.easeInOutCubic,
                child: AnimatedOpacity(
                  opacity: (isVideo && isConnected && !_areControlsVisible) ? 0.0 : 1.0,
                  duration: const Duration(milliseconds: 300),
                  child: Center(
                    child: Container(
                      constraints: BoxConstraints(maxWidth: isVideo ? 440 : 340),
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 18),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1E293B).withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(36),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.35), width: 1.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 20,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          // Mute Audio
                          _buildControlButton(
                            icon: appState.webRTCService.isMuted
                                ? Icons.mic_off_rounded
                                : Icons.mic_rounded,
                            color: appState.webRTCService.isMuted
                                ? Colors.redAccent
                                : Colors.white,
                            onTap: () {
                              _resetAutoHideTimer();
                              setState(() {
                                appState.webRTCService.toggleMute();
                              });
                            },
                          ),

                          // Toggle Speakerphone
                          _buildControlButton(
                            icon: appState.webRTCService.isSpeakerphoneOn
                                ? Icons.volume_up_rounded
                                : Icons.volume_down_rounded,
                            color: appState.webRTCService.isSpeakerphoneOn
                                ? const Color(0xFF00E676)
                                : Colors.white,
                            onTap: () {
                              _resetAutoHideTimer();
                              setState(() {
                                appState.webRTCService.toggleSpeakerphone();
                                _manageProximity();
                              });
                            },
                          ),

                          // Toggle Video
                          if (isVideo)
                            _buildControlButton(
                              icon: appState.webRTCService.isVideoEnabled
                                  ? Icons.videocam_rounded
                                  : Icons.videocam_off_rounded,
                              color: appState.webRTCService.isVideoEnabled
                                  ? Colors.white
                                  : Colors.redAccent,
                              onTap: () {
                                _resetAutoHideTimer();
                                setState(() {
                                  appState.webRTCService.toggleVideo();
                                });
                              },
                            ),

                          // Switch Camera
                          if (isVideo)
                            _buildControlButton(
                              icon: Icons.cameraswitch_rounded,
                              color: Colors.white,
                              onTap: () async {
                                _resetAutoHideTimer();
                                await appState.webRTCService.switchCamera();
                                setState(() {});
                              },
                            ),

                          // End Call (Red Button)
                          GestureDetector(
                            onTap: () async {
                              await appState.endCall();
                            },
                            child: Container(
                              width: 62,
                              height: 62,
                              decoration: const BoxDecoration(
                                color: Colors.redAccent,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.red,
                                    blurRadius: 14,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.call_end_rounded,
                                color: Colors.white,
                                size: 32,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // --- PROXIMITY EAR BLACKOUT OVERLAY ---
            if (_isNearEar && !appState.webRTCService.isSpeakerphoneOn)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: Container(
                    color: Colors.black,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
