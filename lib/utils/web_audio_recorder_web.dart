// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:js' as js;
import 'dart:js_util' as js_util;
import 'package:flutter/foundation.dart';

/// Records audio via the browser's native MediaRecorder API.
/// Outputs WAV format for universal playback compatibility (macOS, iOS, web, Android).
class WebAudioRecorder {
  html.MediaStream? _stream;
  bool _isRecording = false;

  // JS interop handles
  dynamic _audioContext;
  dynamic _sourceNode;
  dynamic _processorNode;
  final List<Float32List> _audioChunks = [];
  int _sampleRate = 44100;

  Future<bool> start() async {
    try {
      _audioChunks.clear();
      _stream = await html.window.navigator.mediaDevices?.getUserMedia({'audio': true});
      if (_stream == null) return false;

      // Create AudioContext via JS interop
      _audioContext = js_util.callConstructor(
        js_util.getProperty(html.window, 'AudioContext') ?? js_util.getProperty(html.window, 'webkitAudioContext'),
        [],
      );
      _sampleRate = (js_util.getProperty(_audioContext, 'sampleRate') as num).toInt();

      // Create MediaStreamSource
      _sourceNode = js_util.callMethod(_audioContext, 'createMediaStreamSource', [_stream]);

      // Create ScriptProcessorNode (buffer=4096, in=1, out=1)
      _processorNode = js_util.callMethod(_audioContext, 'createScriptProcessor', [4096, 1, 1]);

      // Set onaudioprocess callback
      js_util.setProperty(_processorNode, 'onaudioprocess', js.allowInterop((dynamic event) {
        try {
          final inputBuffer = js_util.getProperty(event, 'inputBuffer');
          final channelData = js_util.callMethod(inputBuffer, 'getChannelData', [0]);
          // channelData is a Float32Array JS object
          final length = js_util.getProperty(channelData, 'length') as int;
          final chunk = Float32List(length);
          for (int i = 0; i < length; i++) {
            final val = js_util.getProperty(channelData, i);
            chunk[i] = (val is num) ? val.toDouble() : 0.0;
          }
          _audioChunks.add(chunk);
        } catch (e) {
          debugPrint('⚠️ [AUDIO PROCESS ERROR]: $e');
        }
      }));

      // Connect: source -> processor -> destination
      final destination = js_util.getProperty(_audioContext, 'destination');
      js_util.callMethod(_sourceNode, 'connect', [_processorNode]);
      js_util.callMethod(_processorNode, 'connect', [destination]);

      _isRecording = true;
      return true;
    } catch (e) {
      debugPrint('⚠️ [WEB MEDIA RECORDER START ERROR]: $e');
      return false;
    }
  }

  Future<Uint8List?> stop() async {
    if (!_isRecording) return null;
    _isRecording = false;

    try {
      if (_processorNode != null) js_util.callMethod(_processorNode, 'disconnect', []);
      if (_sourceNode != null) js_util.callMethod(_sourceNode, 'disconnect', []);
      _stream?.getTracks().forEach((t) => t.stop());
      if (_audioContext != null) js_util.callMethod(_audioContext, 'close', []);
    } catch (_) {}

    if (_audioChunks.isEmpty) return null;

    // Merge all chunks into a single PCM buffer
    int totalSamples = 0;
    for (final chunk in _audioChunks) {
      totalSamples += chunk.length;
    }
    final pcmData = Float32List(totalSamples);
    int offset = 0;
    for (final chunk in _audioChunks) {
      pcmData.setAll(offset, chunk);
      offset += chunk.length;
    }

    return _encodeWav(pcmData, _sampleRate);
  }

  /// Encodes raw PCM Float32 samples into a WAV file (16-bit, mono).
  Uint8List _encodeWav(Float32List samples, int sampleRate) {
    const int numChannels = 1;
    const int bitsPerSample = 16;
    final int byteRate = sampleRate * numChannels * (bitsPerSample ~/ 8);
    const int blockAlign = numChannels * (bitsPerSample ~/ 8);
    final int dataSize = samples.length * (bitsPerSample ~/ 8);
    final int fileSize = 44 + dataSize;

    final buffer = ByteData(fileSize);
    int pos = 0;

    void writeString(String s) {
      for (int i = 0; i < s.length; i++) {
        buffer.setUint8(pos++, s.codeUnitAt(i));
      }
    }

    void writeUint32(int value) {
      buffer.setUint32(pos, value, Endian.little);
      pos += 4;
    }

    void writeUint16(int value) {
      buffer.setUint16(pos, value, Endian.little);
      pos += 2;
    }

    writeString('RIFF');
    writeUint32(fileSize - 8);
    writeString('WAVE');
    writeString('fmt ');
    writeUint32(16);
    writeUint16(1);  // PCM format
    writeUint16(numChannels);
    writeUint32(sampleRate);
    writeUint32(byteRate);
    writeUint16(blockAlign);
    writeUint16(bitsPerSample);
    writeString('data');
    writeUint32(dataSize);

    // Float32 -> Int16
    for (int i = 0; i < samples.length; i++) {
      double sample = samples[i].clamp(-1.0, 1.0);
      buffer.setInt16(pos, (sample * 32767).toInt(), Endian.little);
      pos += 2;
    }

    return Uint8List.view(buffer.buffer);
  }
}
