import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../services/camera_recording_service.dart';
import '../services/signaling_service.dart';
import 'recordings_gallery_screen.dart';

/// Shared ICE server config with TURN fallback for NAT traversal
final Map<String, dynamic> kCameraIceServers = {
  'iceServers': [
    {'urls': 'stun:stun.l.google.com:19302'},
    {'urls': 'stun:stun1.l.google.com:19302'},
    {'urls': 'stun:stun2.l.google.com:19302'},
    {'urls': 'stun:global.stun.twilio.com:3478'},
    // Free TURN servers for NAT traversal (relay fallback)
    {
      'urls': [
        'turn:openrelay.metered.ca:80',
        'turn:openrelay.metered.ca:80?transport=tcp',
        'turn:openrelay.metered.ca:443',
        'turns:openrelay.metered.ca:443',
      ],
      'username': 'openrelayproject',
      'credential': 'openrelayproject',
    },
  ],
  'sdpSemantics': 'unified-plan',
  'iceCandidatePoolSize': 2,
};

class CameraStationScreen extends StatefulWidget {
  final Map<String, dynamic> settings;
  const CameraStationScreen({required this.settings, super.key});

  @override
  State<CameraStationScreen> createState() => _CameraStationScreenState();
}

class _CameraStationScreenState extends State<CameraStationScreen> {
  final RTCVideoRenderer _localRenderer = RTCVideoRenderer();
  MediaStream? _localStream;
  bool _isInitialized = false;
  bool _isDimmed = false;

  // Continuous Recording Service
  final CameraRecordingService _recordingService = CameraRecordingService();

  // Automatic Battery Saver (Screen Dimming) Inactivity Timer
  Timer? _inactivityTimer;

  // Real Motion Detection State
  Timer? _motionAnalysisTimer;
  Timer? _motionBannerTimer;
  bool _showMotionBanner = false;
  DateTime? _lastMotionNotificationTime;
  List<int>? _previousFrameSamples;

  // WebRTC peer connections for each viewer
  final Map<String, RTCPeerConnection> _viewerPeers = {};
  StreamSubscription? _viewerListenerSub;
  final Map<String, StreamSubscription> _viewerIceSubs = {};

  // Debounce: track last processed offer timestamp per viewer
  final Map<String, int> _lastProcessedTimestamp = {};

  // Queued viewer requests that arrived before camera was ready
  final List<Map<String, dynamic>> _pendingViewerRequests = [];

  final Map<String, dynamic> _pcConfig = kIsWeb
      ? {}
      : {
          'mandatory': {},
          'optional': [
            {'DtlsSrtpKeyAgreement': true},
          ],
        };

  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _resetInactivityTimer();
    _init();
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    if (_isDimmed && mounted) {
      setState(() => _isDimmed = false);
    }
    // Automatically dim screen after 10 minutes of inactivity
    _inactivityTimer = Timer(const Duration(minutes: 10), () {
      if (mounted) {
        setState(() => _isDimmed = true);
        debugPrint('🌙 [BATTERY SAVER] 10 minutes of inactivity reached. Screen dimmed automatically.');
      }
    });
  }

  Future<void> _init() async {
    final appState = Provider.of<AppStateProvider>(context, listen: false);
    final myId = appState.myProfile?.id ?? '';

    // STEP 1: Clean up old signaling data first so onChildAdded fires fresh
    if (myId.isNotEmpty) {
      await SignalingService().cleanupCameraSignaling(cameraDeviceId: myId);
    }

    // STEP 2: Initialize camera FIRST so _localStream is ready
    await _initCamera();

    // STEP 3: Now start listening for viewers (camera is ready)
    _startListeningForViewers();

    // STEP 4: Process any queued requests
    if (_pendingViewerRequests.isNotEmpty) {
      for (final req in _pendingViewerRequests) {
        await _handleViewerRequest(req, myId);
      }
      _pendingViewerRequests.clear();
    }

    // STEP 5: Start continuous video recording
    if (_localStream != null && !kIsWeb && widget.settings['enableRecording'] != false) {
      await CameraRecordingService.init();
      await _recordingService.startRecording(
        _localStream!,
        cameraDeviceId: myId,
      );
    }

    // STEP 6: Start real motion detection monitor
    if (widget.settings['motionDetection'] == true) {
      _startMotionDetection();
    }
  }

  void _startMotionDetection() {
    final cooldownMinutes = widget.settings['cooldownMinutes'] as int? ?? 5;
    // Set initial last notification time to now so initial cooldown applies upon camera launch
    _lastMotionNotificationTime = DateTime.now();
    debugPrint('🏃 [CAMERA STATION] Real motion detection active. Initial $cooldownMinutes-minute cooldown started.');

    _motionAnalysisTimer?.cancel();
    // Analyze frame every 2.5 seconds for real luminance/pixel variance
    _motionAnalysisTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) {
      if (mounted && _isInitialized && _localStream != null) {
        _analyzeFrameForMotion();
      }
    });
  }

  Future<void> _analyzeFrameForMotion() async {
    try {
      final videoTracks = _localStream?.getVideoTracks();
      if (videoTracks == null || videoTracks.isEmpty) return;

      final track = videoTracks.first;
      final frameBuffer = await track.captureFrame();
      final bytes = frameBuffer.asUint8List();
      if (bytes.isEmpty) return;

      // Sample ~100 pixels across the frame for luminance comparison
      final currentSamples = <int>[];
      final step = (bytes.length / 100).floor();
      if (step <= 0) return;

      for (int i = 0; i < bytes.length; i += step) {
        currentSamples.add(bytes[i]);
      }

      if (_previousFrameSamples != null && _previousFrameSamples!.length == currentSamples.length) {
        double totalDelta = 0;
        for (int i = 0; i < currentSamples.length; i++) {
          totalDelta += (currentSamples[i] - _previousFrameSamples![i]).abs();
        }
        final avgDelta = totalDelta / currentSamples.length;

        final sensitivitySetting = widget.settings['sensitivity'] as String? ?? 'medium';
        final threshold = sensitivitySetting == 'high'
            ? 8.0
            : sensitivitySetting == 'low'
                ? 30.0
                : 16.0;

        if (avgDelta > threshold) {
          debugPrint('🚨 [REAL MOTION DETECTED] Frame delta=$avgDelta > threshold=$threshold');
          _triggerMotionDetected(frameBytes: bytes);
        }
      }

      _previousFrameSamples = currentSamples;
    } catch (e) {
      debugPrint('⚠️ [FRAME ANALYSIS NOTICE]: $e');
    }
  }

  Future<void> _triggerMotionDetected({bool isManual = false, Uint8List? frameBytes}) async {
    final now = DateTime.now();
    final cooldownMinutes = widget.settings['cooldownMinutes'] as int? ?? 5;
    final cooldownSeconds = cooldownMinutes * 60;

    // Smart Cooldown between automated motion alerts (prevents notification spam)
    if (!isManual &&
        _lastMotionNotificationTime != null &&
        now.difference(_lastMotionNotificationTime!).inSeconds < cooldownSeconds) {
      debugPrint('⏳ [MOTION COOLDOWN] Motion detected but in $cooldownMinutes-minute ($cooldownSeconds s) cooldown period, skipping alert');
      return;
    }
    _lastMotionNotificationTime = now;

    // Track motion timestamp in recording service
    _recordingService.addMotionTimestamp();

    // Capture snapshot if bytes provided or capture fresh frame
    String? snapshotBase64;
    try {
      Uint8List? snapBytes = frameBytes;
      if (snapBytes == null && _localStream != null && _localStream!.getVideoTracks().isNotEmpty) {
        final buf = await _localStream!.getVideoTracks().first.captureFrame();
        snapBytes = buf.asUint8List();
      }

      if (snapBytes != null && snapBytes.isNotEmpty) {
        snapshotBase64 = base64Encode(snapBytes);
        debugPrint('📸 [SNAPSHOT CAPTURED] Valid image size: ${snapBytes.length} bytes');
      }
    } catch (e) {
      debugPrint('⚠️ [SNAPSHOT CAPTURE ERROR]: $e');
    }

    // Show visual banner on broadcasting screen
    _motionBannerTimer?.cancel();
    if (mounted) {
      setState(() {
        _showMotionBanner = true;
      });
      _motionBannerTimer = Timer(const Duration(seconds: 6), () {
        if (mounted) {
          setState(() {
            _showMotionBanner = false;
          });
        }
      });
    }

    if (!mounted) return;
    final appState = Provider.of<AppStateProvider>(context, listen: false);
    final cameraName = appState.myProfile?.deviceName ?? 'Ev Kamerası';
    final fallbackPins = appState.allFamilyPins;

    debugPrint('🚨 [CAMERA STATION] Broadcasting motion alert with snapshot to family pins: $fallbackPins');

    try {
      await SignalingService().sendCameraMotionEvent(
        familyPin: appState.familyGroupPin,
        cameraDeviceId: appState.myProfile?.id ?? '',
        cameraDeviceName: cameraName,
        fallbackPins: fallbackPins,
        snapshotBase64: snapshotBase64,
      );
    } catch (e) {
      debugPrint('⚠️ [MOTION ALERT EVENT ERROR]: $e');
    }
  }

  Future<void> _initCamera() async {
    await _localRenderer.initialize();
    final isFront = widget.settings['useFrontCamera'] ?? false;

    final mediaConstraints = <String, dynamic>{
      'audio': true,
      'video': {
        'facingMode': isFront ? 'user' : 'environment',
        'width': {'ideal': 1280},
        'height': {'ideal': 720},
      },
    };

    try {
      _localStream = await navigator.mediaDevices.getUserMedia(mediaConstraints);
      _localRenderer.srcObject = _localStream;
      debugPrint('✅ [CAMERA STATION] Local stream ready: ${_localStream!.getTracks().length} tracks');
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    } catch (e) {
      debugPrint('⚠️ [CAMERA STATION INIT ERROR]: $e');
    }
  }

  void _startListeningForViewers() {
    if (!mounted) return;
    final appState = Provider.of<AppStateProvider>(context, listen: false);
    final myId = appState.myProfile?.id ?? '';

    if (myId.isEmpty) return;

    debugPrint('👂 [CAMERA STATION] Listening for viewers on camera_signaling/$myId/viewers');

    _viewerListenerSub = SignalingService().listenForCameraViewers(
      cameraDeviceId: myId,
      onViewerRequest: (viewerRequest) async {
        if (_localStream == null) {
          debugPrint('⏳ [CAMERA STATION] Stream not ready, queuing viewer request');
          _pendingViewerRequests.add(viewerRequest);
          return;
        }

        await _handleViewerRequest(viewerRequest, myId);
      },
    );
  }

  Future<void> _handleViewerRequest(Map<String, dynamic> viewerRequest, String myId) async {
    final viewerId = viewerRequest['viewerId'] as String? ?? '';
    final offerData = viewerRequest['offer'];
    final requestTimestamp = viewerRequest['timestamp'] as int? ?? 0;

    if (viewerId.isEmpty || offerData == null) {
      debugPrint('⚠️ [CAMERA STATION] Empty viewerId or null offer.');
      return;
    }

    // Debounce: skip if we already processed a newer or same timestamp
    final lastTs = _lastProcessedTimestamp[viewerId] ?? 0;
    if (requestTimestamp > 0 && requestTimestamp <= lastTs) {
      debugPrint('⏭️ [CAMERA STATION] Skipping stale request from $viewerId (ts=$requestTimestamp <= last=$lastTs)');
      return;
    }
    _lastProcessedTimestamp[viewerId] = requestTimestamp;

    debugPrint('📹 [CAMERA STATION] Processing viewer: $viewerId (ts=$requestTimestamp)');

    // Cancel old ICE listener first
    _viewerIceSubs[viewerId]?.cancel();
    _viewerIceSubs.remove(viewerId);

    // Close old peer if exists
    if (_viewerPeers.containsKey(viewerId)) {
      try {
        await _viewerPeers[viewerId]?.close();
      } catch (_) {}
      _viewerPeers.remove(viewerId);
    }

    // Create peer connection for this viewer
    final pc = await createPeerConnection(kCameraIceServers, _pcConfig);
    _viewerPeers[viewerId] = pc;

    // Add local stream tracks
    if (_localStream != null) {
      for (final track in _localStream!.getTracks()) {
        await pc.addTrack(track, _localStream!);
        debugPrint('📡 [CAMERA STATION] Added track: ${track.kind} to peer for $viewerId');
      }
    } else {
      debugPrint('❌ [CAMERA STATION] WARNING: _localStream is null!');
    }

    // Handle ICE candidates from station → viewer
    pc.onIceCandidate = (candidate) {
      if (candidate.candidate != null && candidate.candidate!.isNotEmpty) {
        SignalingService().sendCameraIceCandidate(
          cameraDeviceId: myId,
          senderDeviceId: myId,
          targetRole: 'viewer_$viewerId',
          candidate: candidate.toMap(),
        );
      }
    };

    pc.onConnectionState = (state) {
      debugPrint('📶 [CAMERA STATION → $viewerId] Connection: $state');
      if (mounted) setState(() {});
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
          state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _viewerIceSubs[viewerId]?.cancel();
        _viewerIceSubs.remove(viewerId);
        _viewerPeers.remove(viewerId);
        if (mounted) setState(() {});
      }
    };

    pc.onIceConnectionState = (state) {
      debugPrint('🧊 [CAMERA STATION → $viewerId] ICE: $state');
    };

    // Listen for ICE candidates from viewer → station (per-viewer path)
    final iceSub = SignalingService().listenCameraIceCandidates(
      cameraDeviceId: myId,
      role: 'station_$viewerId',
      onCandidate: (candidateData) async {
        if (!_viewerPeers.containsKey(viewerId)) return;
        try {
          final candidate = RTCIceCandidate(
            candidateData['candidate'],
            candidateData['sdpMid'],
            candidateData['sdpMLineIndex'],
          );
          await pc.addCandidate(candidate);
        } catch (e) {
          _viewerIceSubs[viewerId]?.cancel();
          _viewerIceSubs.remove(viewerId);
        }
      },
    );
    if (iceSub != null) _viewerIceSubs[viewerId] = iceSub;

    // Set remote offer and create answer
    try {
      final offer = Map<String, dynamic>.from(offerData as Map);
      final sdp = offer['sdp'] as String?;
      final type = offer['type'] as String?;

      if (sdp == null || type == null) {
        debugPrint('❌ [CAMERA STATION] Invalid offer SDP from $viewerId');
        return;
      }

      final offerDesc = RTCSessionDescription(sdp, type);
      await pc.setRemoteDescription(offerDesc);

      final answer = await pc.createAnswer({});
      await pc.setLocalDescription(answer);

      debugPrint('📋 [CAMERA STATION] Answer created for $viewerId');

      // Send answer back to viewer
      await SignalingService().sendCameraAnswer(
        cameraDeviceId: myId,
        viewerDeviceId: viewerId,
        answer: answer.toMap(),
      );

      debugPrint('✅ [CAMERA STATION] Answer sent to $viewerId');
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('❌ [CAMERA STATION ANSWER ERROR]: $e');
    }
  }

  @override
  void dispose() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    // Stop continuous recording
    _recordingService.stopRecording();

    _inactivityTimer?.cancel();
    _motionAnalysisTimer?.cancel();
    _motionBannerTimer?.cancel();

    _viewerListenerSub?.cancel();
    SignalingService().cancelViewerChangedSub();
    for (final sub in _viewerIceSubs.values) {
      sub.cancel();
    }
    _viewerIceSubs.clear();

    for (final pc in _viewerPeers.values) {
      try { pc.close(); } catch (_) {}
    }
    _viewerPeers.clear();

    try {
      _localRenderer.srcObject = null;
      _localStream?.getTracks().forEach((t) => t.stop());
      _localStream?.dispose();
      _localRenderer.dispose();
    } catch (_) {}

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewerCount = _viewerPeers.length;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Kamera yayını devam ediyor. Kapatmak için kırmızı butona basın.'),
            duration: Duration(seconds: 2),
          ),
        );
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onTap: _resetInactivityTimer,
          onPanDown: (_) => _resetInactivityTimer(),
          child: Stack(
            children: [
              if (_isInitialized)
                Positioned.fill(
                  child: RTCVideoView(
                    _localRenderer,
                    mirror: widget.settings['useFrontCamera'] ?? false,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                )
              else
                const Center(
                  child: CircularProgressIndicator(color: Color(0xFF00E676)),
                ),

              if (_isDimmed)
                Positioned.fill(
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.88),
                    child: const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.nightlight_round, color: Colors.amber, size: 48),
                          SizedBox(height: 12),
                          Text('Gece & Pil Koruma Modu Aktif',
                            style: TextStyle(color: Colors.white70, fontSize: 16, fontWeight: FontWeight.bold)),
                          SizedBox(height: 6),
                          Text('Aydınlatmak için ekrana dokunun',
                            style: TextStyle(color: Colors.white38, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
                ),

              // Top Info Status Bar
              Positioned(
                top: 40,
                left: 20,
                right: 20,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 10, height: 10,
                        decoration: const BoxDecoration(color: Color(0xFF00E676), shape: BoxShape.circle),
                      ),
                      const SizedBox(width: 8),
                      const Flexible(
                        child: Text('🔴 CANLI YAYINDA',
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const Spacer(),
                      if (viewerCount > 0)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFF00E676).withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.visibility_rounded, color: Color(0xFF00E676), size: 14),
                              const SizedBox(width: 4),
                              Text('$viewerCount İzleyici',
                                style: const TextStyle(color: Color(0xFF00E676), fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),

                      // Recording Active Badge
                      if (!kIsWeb && widget.settings['enableRecording'] != false) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.fiber_manual_record_rounded, color: Colors.redAccent, size: 12),
                              SizedBox(width: 4),
                              Text('REC', style: TextStyle(color: Colors.redAccent, fontSize: 11, fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              // Motion Alert Banner on Camera Station (visual only, no native notification on broadcasting device)
              if (_showMotionBanner)
                Positioned(
                  top: 95,
                  left: 20,
                  right: 20,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade900.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.amberAccent, width: 1.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.amber.withValues(alpha: 0.5),
                          blurRadius: 12,
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.directions_run_rounded, color: Colors.amberAccent, size: 20),
                        SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '🚨 HAREKET ALGILANDI! (Bildirim Gönderildi)',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

              // Bottom Control Panel
              Positioned(
                bottom: 30,
                left: 20,
                right: 20,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    // Recordings Gallery Button
                    FloatingActionButton.small(
                      heroTag: 'recordingsGalleryBtn',
                      backgroundColor: Colors.white24,
                      onPressed: () {
                        _resetInactivityTimer();
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const RecordingsGalleryScreen()),
                        );
                      },
                      tooltip: 'Kayıtları İzle',
                      child: const Icon(Icons.video_library_rounded, color: Colors.white),
                    ),
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.redAccent,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                      ),
                      icon: const Icon(Icons.stop_circle_rounded, color: Colors.white),
                      label: const Text('Yayını Kapat',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                      onPressed: () async {
                        final as2 = Provider.of<AppStateProvider>(context, listen: false);
                        await SignalingService().cleanupCameraSignaling(
                          cameraDeviceId: as2.myProfile?.id ?? '',
                        );
                        await as2.stopCameraHostMode();
                        if (context.mounted) Navigator.of(context).pop();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
