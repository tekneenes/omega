// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:async';
import 'dart:html' as html;
import 'dart:typed_data';
import 'package:flutter/foundation.dart';

Future<Uint8List?> fetchBlobBytes(String blobUrl) async {
  try {
    final xhr = html.HttpRequest();
    xhr.open('GET', blobUrl);
    xhr.responseType = 'arraybuffer';
    final completer = Completer<Uint8List?>();
    xhr.onLoad.listen((_) {
      if (xhr.status == 200 || xhr.status == 0) {
        final buffer = (xhr.response as ByteBuffer);
        completer.complete(Uint8List.view(buffer));
      } else {
        completer.complete(null);
      }
    });
    xhr.onError.listen((_) => completer.complete(null));
    xhr.send();
    return await completer.future;
  } catch (e) {
    debugPrint('⚠️ [WEB BLOB FETCH ERROR]: $e');
    return null;
  }
}
