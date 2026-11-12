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

void main() {
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
      expect(difference(125, 300), greaterThan(25),
          reason: 'The artwork must remain visible through the panel');
      expect(difference(124, 128), lessThan(12),
          reason: 'Fine background detail must be blurred, not just tinted');
      image.dispose();
    });
  }
}
