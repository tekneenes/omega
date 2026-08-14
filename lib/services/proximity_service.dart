import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:proximity_sensor/proximity_sensor.dart';

class ProximityService {
  static final ProximityService _instance = ProximityService._internal();
  factory ProximityService() => _instance;
  ProximityService._internal();

  StreamSubscription<dynamic>? _subscription;
  final StreamController<bool> _isNearController = StreamController<bool>.broadcast();

  bool _isNear = false;
  bool get isNear => _isNear;
  Stream<bool> get isNearStream => _isNearController.stream;

  bool _isListening = false;
  bool get isListening => _isListening;

  /// Start listening to proximity sensor events (for audio calls when speaker is OFF)
  void startListening() {
    if (_isListening) return;
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) {
      // Proximity sensor not supported on web/desktop
      return;
    }

    try {
      _isListening = true;
      _subscription = ProximitySensor.events.listen(
        (int event) {
          // Event > 0 indicates near (e.g. 1 on Android/iOS)
          final isNearNow = event > 0;
          if (_isNear != isNearNow) {
            _isNear = isNearNow;
            _isNearController.add(_isNear);
            if (kDebugMode) {
              print('👂 [PROXIMITY] Near state changed: $_isNear');
            }
          }
        },
        onError: (e) {
          if (kDebugMode) {
            print('⚠️ [PROXIMITY SENSOR ERROR]: $e');
          }
          _isNear = false;
          _isNearController.add(false);
        },
        cancelOnError: false,
      );
      if (kDebugMode) {
        print('👂 [PROXIMITY] Started listening to proximity sensor.');
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ [PROXIMITY START ERROR]: $e');
      }
      _isListening = false;
    }
  }

  /// Stop listening to proximity sensor events (when call ends or speakerphone is ON)
  void stopListening() {
    if (!_isListening) return;
    try {
      _subscription?.cancel();
      _subscription = null;
      _isListening = false;
      _isNear = false;
      _isNearController.add(false);
      if (kDebugMode) {
        print('👂 [PROXIMITY] Stopped listening to proximity sensor.');
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ [PROXIMITY STOP ERROR]: $e');
      }
    }
  }
}
