import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mehd_ai_flutter/widgets/milestone_share_dialog.dart';

// Minimal valid 256-byte TTF container to bypass font engine parsing checks
final Uint8List _dummyFont = Uint8List.fromList([
  0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
  ...List.filled(240, 0),
]);

void main() {
  // Prevent GoogleFonts from attempting network fetching in the test sandbox
  GoogleFonts.config.allowRuntimeFetching = false;

  testWidgets('Render Real Gold Card', (WidgetTester tester) async {
    // 1. Intercept asset loading channel with full file system passthrough
    tester.binding.defaultBinaryMessenger.setMockMessageHandler(
      'flutter/assets',
      (ByteData? message) async {
        if (message == null) return null;
        
        // Decode requested asset key
        final String key = utf8.decode(message.buffer.asUint8List());
        
        if (key.startsWith('google_fonts/')) {
          // Return dummy font bytes
          return ByteData.sublistView(_dummyFont);
        }
        
        // Passthrough: Load real built assets directly from the build cache directory
        try {
          final file = File('build/flutter_assets/$key');
          if (await file.exists()) {
            final bytes = await file.readAsBytes();
            return ByteData.sublistView(bytes);
          }
        } catch (e) {
          debugPrint("Failed to load mock asset: $key -> $e");
        }
        return null;
      },
    );

    // 2. Set phone size for screenshot boundary
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3.0;

    await tester.pumpWidget(
      const MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Scaffold(
          backgroundColor: Color(0xFF000000),
          body: Center(
            child: MilestoneShareDialog(
              initialStage: 3,
              protectionScore: 92,
            ),
          ),
        ),
      ),
    );

    // Let the layout stabilize
    await tester.pumpAndSettle();

    // 3. Render and save the visual output to test/goldens/gold_card.png
    await expectLater(
      find.byType(MilestoneShareDialog),
      matchesGoldenFile('goldens/gold_card.png'),
    );
  });
}
