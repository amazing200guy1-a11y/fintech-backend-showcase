import 'dart:typed_data';

// Web doesn't need path_provider or share_plus — the web export uses
// dart:html Blob download (file_exporter_web.dart) instead.
Future<void> nativeSharePng(
    Uint8List pngBytes, String filename, int stage, int protectionScore) async {
  throw UnsupportedError('nativeSharePng is not available on web.');
}
