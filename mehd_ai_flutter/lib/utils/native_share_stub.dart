import 'dart:io';
import 'dart:typed_data';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

Future<void> nativeSharePng(
    Uint8List pngBytes, String filename, int stage, int protectionScore) async {
  final tempDir = await getTemporaryDirectory();
  final file = await File('${tempDir.path}/$filename').create();
  await file.writeAsBytes(pngBytes);
  final xFile = XFile(file.path);
  await SharePlus.instance.share(
    ShareParams(
      text:
          'I unlocked Stage $stage on Mehd AI! Verification: Protection Score $protectionScore | Certified Alpha 🚀',
      files: [xFile],
    ),
  );
}
