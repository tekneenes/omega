import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:audioplayers/audioplayers.dart';

class AudioRingtoneService {
  static final AudioRingtoneService _instance = AudioRingtoneService._internal();
  factory AudioRingtoneService() => _instance;
  AudioRingtoneService._internal();

  AudioPlayer? _ringtonePlayer;
  AudioPlayer? _ringbackPlayer;
  AudioPlayer? _alarmPlayer;
  AudioPlayer? _callUnansweredPlayer;
  AudioPlayer? _callEndedPlayer;
  AudioPlayer? _busyPlayer;

  bool _isPlayingRingtone = false;
  bool _isPlayingRingback = false;
  bool _isPlayingEndOfCallSound = false;

  static const String ringtoneAsset = 'audio/ringtone.mp3';
  static const String ringbackAsset = 'audio/ringback.mp3';
  static const String alarmAsset = 'audio/alarm.mp3';
  static const String callUnansweredAsset = 'audio/call_unanswered.mp3';
  static const String callEndedAsset = 'audio/call_ended.mp3';
  static const String baskaKisiAsset = 'audio/baska_kisi.mp3';
  static const String busyAsset = 'audio/busy.mp3';

  AudioPlayer? _getOrCreatePlayer(AudioPlayer? current) {
    if (current != null) return current;
    try {
      return AudioPlayer();
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ [AUDIO] AudioPlayer channel not registered yet (Hot reload fallback): $e');
      }
      return null;
    }
  }

  /// Stop only ringtone and ringback (NOT end-of-call sounds)
  Future<void> _stopRingtoneAndRingback() async {
    _isPlayingRingtone = false;
    _isPlayingRingback = false;
    try {
      if (_ringtonePlayer != null) {
        await _ringtonePlayer!.stop();
      }
      if (_ringbackPlayer != null) {
        await _ringbackPlayer!.stop();
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ [AUDIO] Stop ringtone/ringback handled gracefully: $e');
      }
    }
  }

  /// Play Incoming Call Ringtone in loop mode
  Future<void> playRingtone() async {
    if (_isPlayingRingtone) return;
    try {
      await stopAll();
      _isPlayingRingtone = true;
      _ringtonePlayer = _getOrCreatePlayer(_ringtonePlayer);
      if (_ringtonePlayer != null) {
        await _ringtonePlayer!.setReleaseMode(ReleaseMode.loop);
        await _ringtonePlayer!.setVolume(1.0);
        await _ringtonePlayer!.play(AssetSource(ringtoneAsset));
        // Gecikmeli yükleme sırasında kapatma geldiyse hemen sustur (Race Condition Koruması)
        if (!_isPlayingRingtone) {
          await _ringtonePlayer!.stop();
        }
      } else {
        // Fallback System Haptic/Click Sound
        SystemSound.play(SystemSoundType.click);
      }
      if (kDebugMode) {
        print('🔥 [AUDIO] Started playing incoming call ringtone...');
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ [AUDIO] Ringtone play handled gracefully: $e');
      }
    }
  }

  /// Play Outgoing Call Ringback Tone (bip... bip...) in loop mode
  Future<void> playRingback() async {
    if (_isPlayingRingback) return;
    try {
      await stopAll();
      _isPlayingRingback = true;
      _ringbackPlayer = _getOrCreatePlayer(_ringbackPlayer);
      if (_ringbackPlayer != null) {
        await _ringbackPlayer!.setReleaseMode(ReleaseMode.loop);
        await _ringbackPlayer!.setVolume(0.8);
        await _ringbackPlayer!.play(AssetSource(ringbackAsset));
        // Gecikmeli yükleme sırasında kapatma geldiyse hemen sustur (Race Condition Koruması)
        if (!_isPlayingRingback) {
          await _ringbackPlayer!.stop();
        }
      } else {
        SystemSound.play(SystemSoundType.click);
      }
      if (kDebugMode) {
        print('🔥 [AUDIO] Started playing outgoing ringback tone...');
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ [AUDIO] Ringback play handled gracefully: $e');
      }
    }
  }

  /// Play High Urgent Notification Alarm Chime
  Future<void> playAlarm() async {
    try {
      _alarmPlayer = _getOrCreatePlayer(_alarmPlayer);
      if (_alarmPlayer != null) {
        await _alarmPlayer!.stop();
        await _alarmPlayer!.setVolume(1.0);
        await _alarmPlayer!.play(AssetSource(alarmAsset));
      } else {
        SystemSound.play(SystemSoundType.alert);
      }
      if (kDebugMode) {
        print('🔥 [AUDIO] Played high urgent notification alarm tone.');
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ [AUDIO] Alarm play handled gracefully: $e');
      }
    }
  }

  /// Play sound when call is unanswered / timed out ("arama açmadığında")
  /// Returns a Future that completes when the sound finishes playing.
  Future<void> playUnansweredSound() async {
    try {
      // Only stop ringback/ringtone, do NOT stop end-of-call sounds
      await _stopRingtoneAndRingback();
      _isPlayingEndOfCallSound = true;
      _callUnansweredPlayer = _getOrCreatePlayer(_callUnansweredPlayer);
      if (_callUnansweredPlayer != null) {
        final completer = Completer<void>();
        late StreamSubscription sub;
        sub = _callUnansweredPlayer!.onPlayerComplete.listen((_) {
          _isPlayingEndOfCallSound = false;
          sub.cancel();
          if (!completer.isCompleted) completer.complete();
        });
        await _callUnansweredPlayer!.setReleaseMode(ReleaseMode.release);
        await _callUnansweredPlayer!.setVolume(1.0);
        await _callUnansweredPlayer!.play(AssetSource(callUnansweredAsset));
        if (kDebugMode) {
          print('🔥 [AUDIO] Playing call unanswered sound...');
        }
        // Wait for the sound to finish, but cap at 8 seconds max
        await completer.future.timeout(
          const Duration(seconds: 8),
          onTimeout: () {
            _isPlayingEndOfCallSound = false;
            sub.cancel();
          },
        );
        if (kDebugMode) {
          print('🔥 [AUDIO] Call unanswered sound finished.');
        }
      }
    } catch (e) {
      _isPlayingEndOfCallSound = false;
      if (kDebugMode) {
        print('⚠️ [AUDIO] Unanswered sound play handled gracefully: $e');
      }
    }
  }

  /// Play sound when call is ended / hung up by recipient ("arama kapattığında")
  /// Returns a Future that completes when the sound finishes playing.
  Future<void> playCallEndedSound() async {
    try {
      // Only stop ringback/ringtone, do NOT stop end-of-call sounds
      await _stopRingtoneAndRingback();
      _isPlayingEndOfCallSound = true;
      _callEndedPlayer = _getOrCreatePlayer(_callEndedPlayer);
      if (_callEndedPlayer != null) {
        final completer = Completer<void>();
        late StreamSubscription sub;
        sub = _callEndedPlayer!.onPlayerComplete.listen((_) {
          _isPlayingEndOfCallSound = false;
          sub.cancel();
          if (!completer.isCompleted) completer.complete();
        });
        await _callEndedPlayer!.setReleaseMode(ReleaseMode.release);
        await _callEndedPlayer!.setVolume(1.0);
        await _callEndedPlayer!.play(AssetSource(callEndedAsset));
        if (kDebugMode) {
          print('🔥 [AUDIO] Playing call ended sound...');
        }
        // Wait for the sound to finish, but cap at 8 seconds max
        await completer.future.timeout(
          const Duration(seconds: 8),
          onTimeout: () {
            _isPlayingEndOfCallSound = false;
            sub.cancel();
          },
        );
        if (kDebugMode) {
          print('🔥 [AUDIO] Call ended sound finished.');
        }
      }
    } catch (e) {
      _isPlayingEndOfCallSound = false;
      if (kDebugMode) {
        print('⚠️ [AUDIO] Call ended sound play handled gracefully: $e');
      }
    }
  }

  /// Play sound when recipient is busy in another call ("başka bir kişiyle görüşüyor")
  /// Returns a Future that completes when the announcement sound finishes playing.
  Future<void> playUserBusySound() async {
    try {
      await _stopRingtoneAndRingback();
      _isPlayingEndOfCallSound = true;
      _busyPlayer = _getOrCreatePlayer(_busyPlayer);
      if (_busyPlayer != null) {
        final completer = Completer<void>();
        late StreamSubscription sub;
        sub = _busyPlayer!.onPlayerComplete.listen((_) {
          _isPlayingEndOfCallSound = false;
          sub.cancel();
          if (!completer.isCompleted) completer.complete();
        });
        await _busyPlayer!.setReleaseMode(ReleaseMode.release);
        await _busyPlayer!.setVolume(1.0);
        try {
          await _busyPlayer!.play(AssetSource(baskaKisiAsset));
        } catch (_) {
          await _busyPlayer!.play(AssetSource(busyAsset));
        }
        if (kDebugMode) {
          print('🔥 [AUDIO] Playing user busy announcement sound...');
        }
        // Wait for the sound to finish, but cap at 8 seconds max
        await completer.future.timeout(
          const Duration(seconds: 8),
          onTimeout: () {
            _isPlayingEndOfCallSound = false;
            sub.cancel();
          },
        );
        if (kDebugMode) {
          print('🔥 [AUDIO] User busy announcement sound finished.');
        }
      }
    } catch (e) {
      _isPlayingEndOfCallSound = false;
      if (kDebugMode) {
        print('⚠️ [AUDIO] Busy sound play handled gracefully: $e');
      }
    }
  }

  /// Whether an end-of-call sound is currently playing
  bool get isPlayingEndOfCallSound => _isPlayingEndOfCallSound;

  /// Stop all playing sounds immediately
  Future<void> stopAll() async {
    _isPlayingRingtone = false;
    _isPlayingRingback = false;
    _isPlayingEndOfCallSound = false;
    try {
      if (_ringtonePlayer != null) {
        await _ringtonePlayer!.stop();
      }
      if (_ringbackPlayer != null) {
        await _ringbackPlayer!.stop();
      }
      if (_callUnansweredPlayer != null) {
        await _callUnansweredPlayer!.stop();
      }
      if (_callEndedPlayer != null) {
        await _callEndedPlayer!.stop();
      }
      if (_busyPlayer != null) {
        await _busyPlayer!.stop();
      }
      if (kDebugMode) {
        print('🔥 [AUDIO] Stopped all ringtones.');
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ [AUDIO] Ringtone stop handled gracefully: $e');
      }
    }
  }
}
