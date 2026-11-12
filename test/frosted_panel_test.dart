import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/theme/thmr_colors.dart';
import 'package:thmr_app/shared/widgets/persistent_tab_page.dart';
import 'package:thmr_app/shared/widgets/thmr_panel.dart';

class _Texture extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint();
    for (var x = 0; x < size.width; x += 4) {
      paint.color = x % 8 == 0
          ? Colors.black
          : x < size.width / 2
              ? Colors.red
              : Colors.blue;
      canvas.drawRect(Rect.fromLTWH(x.toDouble(), 0, 4, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_Texture oldDelegate) => false;
}

/// Blur anti-aliasing differs slightly between Windows, where the baselines
/// were captured, and the Linux CI renderer. A small allowance keeps the
/// pixel baseline useful without failing on cross-platform edge pixels.
class _TolerantGoldenComparator extends LocalFileComparator {
  _TolerantGoldenComparator(super.testFile);

  static const _tolerance = 0.01;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    final result = await GoldenFileComparator.compareLists(
      imageBytes,
      await getGoldenBytes(golden),
    );
    if (result.passed || result.diffPercent <= _tolerance) {
      result.dispose();
      return true;
    }
    final error = await generateFailureOutput(result, golden, basedir);
    result.dispose();
    throw FlutterError(error);
  }
}

void main() {
  goldenFileComparator = _TolerantGoldenComparator(
    Uri.parse('test/frosted_panel_test.dart'),
  );
  for (final brightness in Brightness.values) {
    testWidgets('frost keeps background colour and blurs detail in $brightness',
        (tester) async {
      tester.view.physicalSize = const Size(430, 300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
          theme: ThemeData(
              brightness: brightness,
              extensions: [ThmrTokens.resolve(AccentTheme.reimu, brightness)]),
          home: Scaffold(
            backgroundColor: Colors.transparent,
            body: Stack(fit: StackFit.expand, children: [
              RepaintBoundary(child: CustomPaint(painter: _Texture())),
              const Center(
                  child: SizedBox(
                      width: 380,
                      height: 200,
                      child: PersistentTabPage(
                          active: true,
                          child: ThmrPanel(child: SizedBox.expand())))),
            ]),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await expectLater(find.byKey(key),
          matchesGoldenFile('goldens/frost_${brightness.name}.png'));
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = (await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
      int channel(int x, int c) => bytes.getUint8((150 * 430 + x) * 4 + c);
      int difference(int a, int b) =>
          List.generate(3, (c) => (channel(a, c) - channel(b, c)).abs())
              .reduce((a, b) => a + b);
      expect(difference(125, 300),
          greaterThan(brightness == Brightness.light ? 75 : 25),
          reason:
              '$brightness panel must transmit enough of the blurred artwork');
      expect(difference(124, 128), lessThan(12),
          reason: 'Fine background detail must be blurred, not just tinted');
      image.dispose();
    });
  }
}
