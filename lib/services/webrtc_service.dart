import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';
import '../models/call_session.dart';
import 'signaling_service.dart';

typedef OnPeerDisconnectedCallback = void Function();

class WebRTCService {
  OnPeerDisconnectedCallback? onPeerDisconnected;

  RTCPeerConnection? _peerConnection;
  MediaStream? _localStream;
  MediaStream? _remoteStream;

  MediaStream? get localStream => _localStream;
  MediaStream? get remoteStream => _remoteStream;

  final RTCVideoRenderer localRenderer = RTCVideoRenderer();
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();

  bool isMuted = false;
  bool isVideoEnabled = true;
  bool isFrontCamera = true;
  bool _isRenderersInitialized = false;

  bool _isPeerConnected = false;
  bool _isRemoteDescriptionSet = false;
  final List<RTCIceCandidate> _queuedRemoteCandidates = [];

  final Map<String, dynamic> _iceServers = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      {'urls': 'stun:stun2.l.google.com:19302'},
      {'urls': 'stun:stun3.l.google.com:19302'},
      {'urls': 'stun:stun4.l.google.com:19302'},
      {'urls': 'stun:global.stun.twilio.com:3478'},
    ],
    'sdpSemantics': 'unified-plan',
  };

  final Map<String, dynamic> _config = kIsWeb
      ? {}
      : {
          'mandatory': {},
          'optional': [
            {'DtlsSrtpKeyAgreement': true},
          ],
        };

  Future<void> initRenderers() async {
    if (!_isRenderersInitialized) {
      try {
        await localRenderer.initialize();
        await remoteRenderer.initialize();
        _isRenderersInitialized = true;
      } catch (e) {
        debugPrint('⚠️ [WEBRTC RENDERER WARN]: $e');
      }
    }
  }

  Future<void> ensureRenderersInitialized() async {
    await initRenderers();
  }

  Future<void> openUserMedia(CallType callType) async {
    await ensureRenderersInitialized();

    if (!kIsWeb) {
      try {
        final micStatus = await Permission.microphone.request();
        debugPrint('🎙️ [PERMISSION] Microphone status: $micStatus');
        if (callType == CallType.video) {
          final camStatus = await Permission.camera.request();
          debugPrint('📷 [PERMISSION] Camera status: $camStatus');
        }
      } catch (e) {
        debugPrint('⚠️ [PERMISSION WARN]: $e');
      }
    }

    try {
      if (callType == CallType.video) {
        final Map<String, dynamic> videoConstraints = kIsWeb
            ? {
                'audio': true,
                'video': true,
              }
            : {
                'audio': true,
                'video': {
                  'facingMode': 'user',
                  'width': {'ideal': 640},
                  'height': {'ideal': 480},
                },
              };
        _localStream = await navigator.mediaDevices.getUserMedia(videoConstraints);
      } else {
        _localStream = await navigator.mediaDevices.getUserMedia({'audio': true});
      }
    } catch (e) {
      debugPrint('⚠️ [WEBRTC MEDIA WARN] Primary getUserMedia failed: $e. Retrying basic media...');
      try {
        _localStream = await navigator.mediaDevices.getUserMedia({
          'audio': true,
          'video': callType == CallType.video,
        });
      } catch (e2) {
        debugPrint('⚠️ [WEBRTC MEDIA WARN] Basic getUserMedia failed: $e2. Falling back to audio-only...');
        try {
          _localStream = await navigator.mediaDevices.getUserMedia({'audio': true});
        } catch (e3) {
          debugPrint('❌ [WEBRTC MEDIA ERROR] Media stream allocation failed: $e3');
        }
      }
    }

    if (_localStream != null) {
      // Ensure all audio and video tracks are enabled
      _localStream!.getAudioTracks().forEach((track) {
        track.enabled = true;
      });
      _localStream!.getVideoTracks().forEach((track) {
        track.enabled = true;
      });

      try {
        localRenderer.srcObject = _localStream;
      } catch (_) {}
    }
  }

  VoidCallback? onTrackReceived;

  void _registerTrackHandler() {
    _peerConnection?.onTrack = (event) async {
      debugPrint('🎥 [WEBRTC ONTRACK] Received track: ${event.track.kind}');
      if (event.streams.isNotEmpty) {
        _remoteStream = event.streams[0];
      } else {
        _remoteStream ??= await createLocalMediaStream('remote_stream');
        _remoteStream!.addTrack(event.track);
      }

      _remoteStream!.getAudioTracks().forEach((track) {
        track.enabled = true;
      });
      _remoteStream!.getVideoTracks().forEach((track) {
        track.enabled = true;
      });

      try {
        remoteRenderer.srcObject = _remoteStream;
        if (onTrackReceived != null) {
          onTrackReceived!();
        }
      } catch (e) {
        debugPrint('⚠️ [WEBRTC ONTRACK ERROR]: $e');
      }
    };
  }

  Future<Map<String, dynamic>> createOffer(
      String targetDeviceId, CallType callType) async {
    _isRemoteDescriptionSet = false;
    _isPeerConnected = false;
    _queuedRemoteCandidates.clear();

    await openUserMedia(callType);
    _peerConnection = await createPeerConnection(_iceServers, _config);

    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) {
        _peerConnection?.addTrack(track, _localStream!);
      });
    }

    _peerConnection?.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        SignalingService().sendIceCandidate(targetDeviceId, candidate.toMap());
      }
    };

    _peerConnection?.onConnectionState = (state) {
      debugPrint('📶 [WEBRTC STATE]: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _isPeerConnected = true;
      } else if (_isPeerConnected &&
          (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
           state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
           state == RTCPeerConnectionState.RTCPeerConnectionStateClosed)) {
        _isPeerConnected = false;
        if (onPeerDisconnected != null) {
          onPeerDisconnected!();
        }
      }
    };

    _registerTrackHandler();

    RTCSessionDescription offer = await _peerConnection!.createOffer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': callType == CallType.video ? 1 : 0,
    });
    await _peerConnection!.setLocalDescription(offer);

    return offer.toMap();
  }

  Future<Map<String, dynamic>> createAnswer(
      String callerId, Map<String, dynamic> remoteOffer, CallType callType) async {
    _isRemoteDescriptionSet = false;
    _isPeerConnected = false;
    _queuedRemoteCandidates.clear();

    await openUserMedia(callType);
    _peerConnection = await createPeerConnection(_iceServers, _config);

    if (_localStream != null) {
      _localStream!.getTracks().forEach((track) {
        _peerConnection?.addTrack(track, _localStream!);
      });
    }

    _peerConnection?.onIceCandidate = (candidate) {
      if (candidate.candidate != null) {
        SignalingService().sendIceCandidate(callerId, candidate.toMap());
      }
    };

    _peerConnection?.onConnectionState = (state) {
      debugPrint('📶 [WEBRTC STATE]: $state');
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _isPeerConnected = true;
      } else if (_isPeerConnected &&
          (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected ||
           state == RTCPeerConnectionState.RTCPeerConnectionStateFailed ||
           state == RTCPeerConnectionState.RTCPeerConnectionStateClosed)) {
        _isPeerConnected = false;
        if (onPeerDisconnected != null) {
          onPeerDisconnected!();
        }
      }
    };

    _registerTrackHandler();

    final offerDesc = RTCSessionDescription(
      remoteOffer['sdp'],
      remoteOffer['type'],
    );
    await _peerConnection!.setRemoteDescription(offerDesc);
    await _flushIceCandidates();

    RTCSessionDescription answer = await _peerConnection!.createAnswer({
      'offerToReceiveAudio': 1,
      'offerToReceiveVideo': callType == CallType.video ? 1 : 0,
    });
    await _peerConnection!.setLocalDescription(answer);

    return answer.toMap();
  }

  Future<void> setRemoteAnswer(Map<String, dynamic> remoteAnswer) async {
    if (_peerConnection == null) return;
    try {
      final state = await _peerConnection!.getSignalingState();
      if (state == RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
        final answerDesc = RTCSessionDescription(
          remoteAnswer['sdp'],
          remoteAnswer['type'],
        );
        await _peerConnection!.setRemoteDescription(answerDesc);
        await _flushIceCandidates();
      } else {
        debugPrint('ℹ️ [WEBRTC SIGNALS] Skipping setRemoteAnswer because signalingState is already $state');
      }
    } catch (e) {
      debugPrint('⚠️ [WEBRTC ANSWER WARN]: $e');
    }
  }

  Future<void> addCandidate(Map<String, dynamic> candidateData) async {
    final candidate = RTCIceCandidate(
      candidateData['candidate'],
      candidateData['sdpMid'],
      candidateData['sdpMLineIndex'],
    );

    if (_peerConnection != null && _isRemoteDescriptionSet) {
      try {
        await _peerConnection!.addCandidate(candidate);
      } catch (e) {
        debugPrint('⚠️ [WEBRTC ICE WARN]: $e');
      }
    } else {
      debugPrint('📦 [WEBRTC ICE QUEUE] Queued candidate until remote description is set');
      _queuedRemoteCandidates.add(candidate);
    }
  }

  Future<void> _flushIceCandidates() async {
    _isRemoteDescriptionSet = true;
    if (_peerConnection == null) return;
    for (final candidate in List<RTCIceCandidate>.from(_queuedRemoteCandidates)) {
      try {
        await _peerConnection!.addCandidate(candidate);
        debugPrint('✅ [WEBRTC ICE QUEUE] Flushed queued ICE candidate');
      } catch (e) {
        debugPrint('⚠️ [WEBRTC ICE FLUSH WARN]: $e');
      }
    }
    _queuedRemoteCandidates.clear();
  }

  void toggleMute() {
    if (_localStream != null) {
      final audioTracks = _localStream!.getAudioTracks();
      if (audioTracks.isNotEmpty) {
        isMuted = !isMuted;
        audioTracks[0].enabled = !isMuted;
      }
    }
  }

  void toggleVideo() {
    if (_localStream != null) {
      final videoTracks = _localStream!.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        isVideoEnabled = !isVideoEnabled;
        videoTracks[0].enabled = isVideoEnabled;
      }
    }
  }

  Future<void> switchCamera() async {
    if (_localStream != null) {
      final videoTracks = _localStream!.getVideoTracks();
      if (videoTracks.isNotEmpty) {
        try {
          await Helper.switchCamera(videoTracks[0]);
          isFrontCamera = !isFrontCamera;
        } catch (_) {}
      }
    }
  }

  bool isSpeakerphoneOn = false;

  void toggleSpeakerphone() {
    isSpeakerphoneOn = !isSpeakerphoneOn;
    try {
      Helper.setSpeakerphoneOn(isSpeakerphoneOn);
    } catch (e) {
      debugPrint('⚠️ [WEBRTC SPEAKERPHONE WARN]: $e');
    }
  }

  Future<void> dispose() async {
    _isPeerConnected = false;
    _isRemoteDescriptionSet = false;
    _queuedRemoteCandidates.clear();

    try {
      _peerConnection?.onConnectionState = null;
      _peerConnection?.onIceCandidate = null;
    } catch (_) {}

    try {
      localRenderer.srcObject = null;
      remoteRenderer.srcObject = null;
    } catch (_) {}

    _localStream?.getTracks().forEach((track) {
      try {
        track.stop();
      } catch (_) {}
    });
    _remoteStream?.getTracks().forEach((track) {
      try {
        track.stop();
      } catch (_) {}
    });

    try {
      await _localStream?.dispose();
      await _remoteStream?.dispose();
    } catch (_) {}

    _localStream = null;
    _remoteStream = null;

    try {
      await _peerConnection?.close();
    } catch (_) {}
    _peerConnection = null;
  }
}
