import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:provider/provider.dart';
import '../providers/app_state_provider.dart';
import '../services/signaling_service.dart';
import 'camera_station_screen.dart' show kCameraIceServers;

class LiveCameraViewerScreen extends StatefulWidget {
  final Map<String, dynamic> cameraData;
  const LiveCameraViewerScreen({required this.cameraData, super.key});

  @override
  State<LiveCameraViewerScreen> createState() => _LiveCameraViewerScreenState();
}

class _LiveCameraViewerScreenState extends State<LiveCameraViewerScreen> {
  final RTCVideoRenderer _remoteRenderer = RTCVideoRenderer();
  RTCPeerConnection? _peerConnection;
  MediaStream? _remoteStream;

  bool _isConnecting = true;
  bool _isTalking = false;
  bool _isMuted = false;
  bool _hasReceivedTrack = false;
  String _connectionStatus = 'Bağlanılıyor...';
  Map<String, dynamic>? _activeTalkLock;

  StreamSubscription? _lockSub;
  StreamSubscription? _answerSub;
  StreamSubscription? _iceSub;
  Timer? _retryTimer;

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
    _initWebRTCAndConnect();
    _listenTalkLock();
  }

  Future<void> _initWebRTCAndConnect() async {
    await _remoteRenderer.initialize();
    if (!mounted) return;

    final appState = Provider.of<AppStateProvider>(context, listen: false);
    final myId = appState.myProfile?.id ?? '';
    final cameraDeviceId = widget.cameraData['deviceId'] ?? '';

    if (myId.isEmpty || cameraDeviceId.isEmpty) {
      debugPrint('❌ [CAMERA VIEWER] Missing IDs: myId=$myId, cameraDeviceId=$cameraDeviceId');
      return;
    }

    debugPrint('🚀 [CAMERA VIEWER] Starting connection to camera $cameraDeviceId as viewer $myId');

    // Clean viewer-specific signaling data first (old answers and ICE)
    await SignalingService().cleanupViewerSignaling(
      cameraDeviceId: cameraDeviceId,
      viewerDeviceId: myId,
    );

    try {
      _peerConnection = await createPeerConnection(kCameraIceServers, _pcConfig);
      debugPrint('✅ [CAMERA VIEWER] PeerConnection created');

      // Add transceivers so WebRTC knows we want to receive audio and video
      try {
        await _peerConnection!.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeVideo,
          init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
        );
        await _peerConnection!.addTransceiver(
          kind: RTCRtpMediaType.RTCRtpMediaTypeAudio,
          init: RTCRtpTransceiverInit(direction: TransceiverDirection.RecvOnly),
        );
        debugPrint('✅ [CAMERA VIEWER] Transceivers added (video+audio RecvOnly)');
      } catch (e) {
        debugPrint('⚠️ [CAMERA VIEWER] Transceiver notice: $e');
      }

      // Register remote track handler
      _peerConnection!.onTrack = (event) async {
        debugPrint('📹 [CAMERA VIEWER] onTrack: kind=${event.track.kind}, streams=${event.streams.length}');
        if (event.streams.isNotEmpty) {
          _remoteStream = event.streams[0];
        } else {
          _remoteStream ??= await createLocalMediaStream('remote_cam_stream');
          _remoteStream!.addTrack(event.track);
        }

        _remoteStream!.getAudioTracks().forEach((t) => t.enabled = true);
        _remoteStream!.getVideoTracks().forEach((t) => t.enabled = true);

        try {
          _remoteRenderer.srcObject = _remoteStream;
          _hasReceivedTrack = true;
          if (mounted) {
            setState(() {
              _isConnecting = false;
              _connectionStatus = 'Bağlandı';
            });
          }
          debugPrint('✅ [CAMERA VIEWER] Remote stream assigned to renderer');
        } catch (e) {
          debugPrint('⚠️ [CAMERA VIEWER RENDER ERROR]: $e');
        }
      };

      // Handle ICE candidates viewer → station
      _peerConnection!.onIceCandidate = (candidate) {
        if (candidate.candidate != null && candidate.candidate!.isNotEmpty) {
          SignalingService().sendCameraIceCandidate(
            cameraDeviceId: cameraDeviceId,
            senderDeviceId: myId,
            targetRole: 'station_$myId',
            candidate: candidate.toMap(),
          );
        }
      };

      _peerConnection!.onConnectionState = (state) {
        debugPrint('📶 [CAMERA VIEWER] Connection State: $state');
        if (mounted) {
          setState(() {
            _connectionStatus = _stateToString(state);
          });
        }
      };

      _peerConnection!.onIceConnectionState = (state) {
        debugPrint('🧊 [CAMERA VIEWER] ICE State: $state');
      };

      // STEP 1: Create Offer FIRST and set local description
      // This puts peer in "have-local-offer" state so it can accept answers
      final offer = await _peerConnection!.createOffer({
        'offerToReceiveAudio': 1,
        'offerToReceiveVideo': 1,
      });
      await _peerConnection!.setLocalDescription(offer);
      debugPrint('📋 [CAMERA VIEWER] Offer created and local desc set: type=${offer.type}');

      // STEP 2: NOW set up answer listener (peer is in "have-local-offer" state)
      bool answerApplied = false;
      _answerSub = SignalingService().listenForCameraAnswer(
        cameraDeviceId: cameraDeviceId,
        viewerDeviceId: myId,
        onAnswer: (answerData) async {
          if (answerApplied) return; // Only apply once
          answerApplied = true;
          try {
            debugPrint('📩 [CAMERA VIEWER] Received answer: type=${answerData['type']}');
            final answerDesc = RTCSessionDescription(answerData['sdp'], answerData['type']);
            await _peerConnection?.setRemoteDescription(answerDesc);
            debugPrint('✅ [CAMERA VIEWER] Remote answer set from camera station!');
          } catch (e) {
            debugPrint('⚠️ [CAMERA VIEWER ANSWER ERROR]: $e');
          }
        },
      );

      // STEP 3: Set up ICE listener
      _iceSub = SignalingService().listenCameraIceCandidates(
        cameraDeviceId: cameraDeviceId,
        role: 'viewer_$myId',
        onCandidate: (candidateData) async {
          try {
            final candidate = RTCIceCandidate(
              candidateData['candidate'],
              candidateData['sdpMid'],
              candidateData['sdpMLineIndex'],
            );
            await _peerConnection?.addCandidate(candidate);
          } catch (e) {
            debugPrint('⚠️ [CAMERA VIEWER ICE ERROR]: $e');
          }
        },
      );

      // STEP 4: Send Offer to camera station
      await SignalingService().sendCameraOffer(
        cameraDeviceId: cameraDeviceId,
        viewerDeviceId: myId,
        offer: offer.toMap(),
      );

      debugPrint('🚀 [CAMERA VIEWER] Offer sent to camera station $cameraDeviceId');

      // Set up a retry timer - if no track received in 15 seconds, retry
      _retryTimer?.cancel();
      _retryTimer = Timer(const Duration(seconds: 15), () {
        if (mounted && _isConnecting && !_hasReceivedTrack) {
          debugPrint('⏰ [CAMERA VIEWER] Connection timeout, retrying...');
          _retryConnection();
        }
      });
    } catch (e) {
      debugPrint('❌ [CAMERA VIEWER WEBRTC INIT ERROR]: $e');
      if (mounted) {
        setState(() {
          _connectionStatus = 'Bağlantı hatası';
        });
      }
    }
  }

  void _retryConnection() async {
    debugPrint('🔄 [CAMERA VIEWER] Retrying connection...');
    _retryTimer?.cancel();
    _answerSub?.cancel();
    _iceSub?.cancel();
    _hasReceivedTrack = false;
    try { await _peerConnection?.close(); } catch (_) {}
    _peerConnection = null;

    if (mounted) {
      setState(() {
        _isConnecting = true;
        _connectionStatus = 'Yeniden bağlanılıyor...';
      });
      _initWebRTCAndConnect();
    }
  }

  String _stateToString(RTCPeerConnectionState state) {
    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateNew:
        return 'Yeni';
      case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        return 'Bağlanıyor...';
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        return 'Bağlandı';
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        return 'Bağlantı kesildi';
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        return 'Başarısız';
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        return 'Kapatıldı';
    }
  }

  void _listenTalkLock() {
    final appState = Provider.of<AppStateProvider>(context, listen: false);
    final cameraDeviceId = widget.cameraData['deviceId'] ?? '';
    _lockSub = SignalingService().listenCameraTalkLock(
      appState.familyGroupPin,
      cameraDeviceId,
      (lockData) {
        if (mounted) {
          setState(() {
            _activeTalkLock = lockData;
          });
        }
      },
    );
  }

  void _releaseTalkLock() {
    if (!_isTalking) return; // Already released
    setState(() => _isTalking = false);

    final appState = Provider.of<AppStateProvider>(context, listen: false);
    final cameraDeviceId = widget.cameraData['deviceId'] ?? '';

    SignalingService().updateCameraTalkLock(
      familyPin: appState.familyGroupPin,
      cameraDeviceId: cameraDeviceId,
      talkerDeviceId: null,
      talkerDeviceName: null,
    );
    debugPrint('🔓 [CAMERA VIEWER] Talk lock released');
  }

  void _toggleMute() {
    setState(() => _isMuted = !_isMuted);
    if (_remoteStream != null) {
      for (final track in _remoteStream!.getAudioTracks()) {
        track.enabled = !_isMuted;
      }
    }
  }

  @override
  void dispose() {
    _retryTimer?.cancel();
    _lockSub?.cancel();
    _answerSub?.cancel();
    _iceSub?.cancel();

    // Safety: release talk lock if still held when leaving screen
    if (_isTalking) {
      try {
        final appState = Provider.of<AppStateProvider>(context, listen: false);
        final cameraDeviceId = widget.cameraData['deviceId'] ?? '';
        SignalingService().updateCameraTalkLock(
          familyPin: appState.familyGroupPin,
          cameraDeviceId: cameraDeviceId,
          talkerDeviceId: null,
          talkerDeviceName: null,
        );
      } catch (_) {}
    }

    try {
      _remoteRenderer.srcObject = null;
      _remoteRenderer.dispose();
      _peerConnection?.close();
    } catch (_) {}

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppStateProvider>(context);
    final cameraName = widget.cameraData['deviceName'] ?? 'Ev Kamerası';
    final cameraDeviceId = widget.cameraData['deviceId'] ?? '';

    // Determine Talk Lock status
    final talkerId = _activeTalkLock?['talkerDeviceId'];
    final talkerName = _activeTalkLock?['talkerDeviceName'] ?? 'Biri';
    final myId = appState.myProfile?.id;
    final isLockedByOther = talkerId != null && talkerId != myId;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: const Color(0xFF1E293B),
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: _isConnecting ? Colors.amber : const Color(0xFF00E676),
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '$cameraName • $_connectionStatus',
                style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: [
          // Retry button
          IconButton(
            icon: const Icon(Icons.refresh, color: Colors.white70),
            onPressed: _retryConnection,
          ),
        ],
      ),
      body: Stack(
        children: [
          // Remote Live Video Renderer
          Positioned.fill(
            child: _hasReceivedTrack && _remoteRenderer.srcObject != null
                ? RTCVideoView(
                    _remoteRenderer,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  )
                : Container(
                    color: Colors.black,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isConnecting) ...[
                            const SizedBox(
                              width: 56,
                              height: 56,
                              child: CircularProgressIndicator(
                                color: Color(0xFF00E676),
                                strokeWidth: 3,
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                          Text(
                            _connectionStatus,
                            style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Kamera: $cameraName',
                            style: const TextStyle(color: Colors.white54, fontSize: 14),
                          ),
                          const SizedBox(height: 24),
                          if (!_isConnecting)
                            ElevatedButton.icon(
                              onPressed: _retryConnection,
                              icon: const Icon(Icons.refresh),
                              label: const Text('Tekrar Dene'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF00E676),
                                foregroundColor: Colors.black,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
          ),

          // Talk Lock Banner
          if (_activeTalkLock != null)
            Positioned(
              top: 8,
              left: 12,
              right: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isLockedByOther
                      ? Colors.orange.withValues(alpha: 0.9)
                      : const Color(0xFF00E676).withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    Icon(
                      isLockedByOther ? Icons.mic_off_rounded : Icons.mic_rounded,
                      color: isLockedByOther ? Colors.white : Colors.black,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      isLockedByOther
                          ? '$talkerName konuşuyor...'
                          : 'Siz konuşuyorsunuz',
                      style: TextStyle(
                        color: isLockedByOther ? Colors.white : Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // Talk Control Panel + LIVE Badge
          Positioned(
            bottom: 24,
            left: 16,
            right: 16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // LIVE Badge
                if (_hasReceivedTrack)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.7),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.5)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: Colors.redAccent,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text('🔴 CANLI YAYIN',
                          style: TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),

                // Talk Button + Close Row
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Mute / Unmute Speaker Button
                      FloatingActionButton.small(
                        heroTag: 'muteCamAudioBtn',
                        backgroundColor: _isMuted ? Colors.redAccent : Colors.white24,
                        onPressed: _toggleMute,
                        tooltip: _isMuted ? 'Sesi Aç' : 'Sesi Kapat',
                        child: Icon(
                          _isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                          color: Colors.white,
                        ),
                      ),

                      // Talk Button
                      GestureDetector(
                        onLongPressStart: isLockedByOther
                            ? null
                            : (_) async {
                                setState(() => _isTalking = true);
                                await SignalingService().updateCameraTalkLock(
                                  familyPin: appState.familyGroupPin,
                                  cameraDeviceId: cameraDeviceId,
                                  talkerDeviceId: myId,
                                  talkerDeviceName: appState.myProfile?.deviceName ?? 'Biri',
                                );
                              },
                        onLongPressEnd: isLockedByOther ? null : (_) => _releaseTalkLock(),
                        onLongPressCancel: isLockedByOther ? null : () => _releaseTalkLock(),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                          decoration: BoxDecoration(
                            color: _isTalking
                                ? const Color(0xFF00E676)
                                : isLockedByOther
                                    ? Colors.grey
                                    : Colors.white24,
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _isTalking ? Icons.mic : Icons.mic_none,
                                color: _isTalking ? Colors.black : Colors.white,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                isLockedByOther
                                    ? 'Meşgul'
                                    : _isTalking
                                        ? 'Konuşuyor...'
                                        : 'Basılı Tut & Konuş',
                                style: TextStyle(
                                  color: _isTalking ? Colors.black : Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Close Button
                      FloatingActionButton.small(
                        heroTag: 'closeCamViewerBtn',
                        backgroundColor: Colors.redAccent,
                        onPressed: () {
                          Navigator.of(context).pop();
                        },
                        child: const Icon(Icons.close, color: Colors.white),
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
