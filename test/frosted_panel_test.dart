import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/theme/thmr_colors.dart';
import 'package:thmr_app/shared/widgets/persistent_tab_page.dart';
import 'package:thmr_app/shared/widgets/thmr_panel.dart';
import 'package:thmr_app/shared/widgets/thmr_wallpaper.dart';

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

/// 基准图在 Windows 上生成。Linux CI 的模糊抗锯齿略有不同，因此允许少量边缘像素差异。
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
  testWidgets('静态毛玻璃共享底图，卡片移动时仍与壁纸对齐', (tester) async {
    tester.view.physicalSize = const Size(430, 300);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    final card = GlobalKey();
    final left = ValueNotifier(32.0);
    addTearDown(left.dispose);
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        theme: ThemeData(extensions: [ThmrTokens.reimuLight]),
        home: ThmrWallpaper(
          textureKey: 'test-wallpaper',
          background: CustomPaint(painter: _Texture()),
          child: ValueListenableBuilder(
            valueListenable: left,
            builder: (context, position, child) => Stack(children: [
              Positioned(
                  left: position,
                  top: 20,
                  width: 150,
                  height: 80,
                  child: child!),
              const Positioned(
                  left: 32,
                  top: 140,
                  width: 150,
                  height: 80,
                  child: ThmrPanel(child: SizedBox.expand())),
            ]),
            child: RepaintBoundary(
              key: card,
              child: const ThmrPanel(child: SizedBox.expand()),
            ),
          ),
        ),
      ),
    ));

    final frost = find.byType(RawImage);
    Future<void> waitForTexture() async {
      for (var i = 0; i < 50 && frost.evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 10));
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 4)));
      }
      expect(frost, findsNWidgets(2));
    }

    expect(find.byType(BackdropFilter), findsNWidgets(2));
    await waitForTexture();
    expect(find.byType(BackdropFilter), findsNothing);
    final normalTexture = tester.widget<RawImage>(frost.first).image;
    expect(tester.widget<RawImage>(frost.last).image, same(normalTexture));
    final cardLayer =
        card.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final snapshot = await cardLayer.toImage();
    expect(snapshot.width, 150);
    snapshot.dispose();

    left.value = 240;
    await tester.pump();
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = (await tester
        .runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
    image.dispose();
    int pixel(int x, int y, int c) => bytes.getUint8((y * 430 + x) * 4 + c);
    expect(pixel(300, 60, 2), greaterThan(pixel(300, 60, 0) + 25));
    expect((pixel(300, 60, 2) - pixel(304, 60, 2)).abs(), lessThan(12));
    expect(pixel(80, 180, 0), greaterThan(pixel(80, 180, 2) + 25));

    tester.view.physicalSize = const Size(500, 300);
    await tester.pump();
    await waitForTexture();
    tester.view.physicalSize = const Size(430, 300);
    await tester.pump();
    expect(tester.widget<RawImage>(frost.first).image, same(normalTexture));
  });

  for (final brightness in Brightness.values) {
    testWidgets(
        'tab entry draws full frost from its first frame in $brightness',
        (tester) async {
      tester.view.physicalSize = const Size(430, 300);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final key = GlobalKey();
      final active = ValueNotifier(false);
      addTearDown(active.dispose);
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
              Center(
                child: SizedBox(
                  width: 380,
                  height: 200,
                  child: ValueListenableBuilder(
                    valueListenable: active,
                    builder: (context, value, child) => PersistentTabPage(
                        active: value,
                        child: const ThmrPanel(child: SizedBox.expand())),
                  ),
                ),
              ),
            ]),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      for (var entry = 0; entry < 2; entry++) {
        active.value = true;
        await tester.pump();
        for (final milliseconds in [0, 16, 32, 64, 96, 48]) {
          await tester.pump(Duration(milliseconds: milliseconds));
          final boundary =
              key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = (await tester.runAsync(
              () => image.toByteData(format: ui.ImageByteFormat.rawRgba)))!;
          image.dispose();
          int pixel(int x, int y, int c) =>
              bytes.getUint8((y * 430 + x) * 4 + c);
          int difference(int a, int b) => List.generate(
                  3, (c) => (pixel(a, 150, c) - pixel(b, 150, c)).abs())
              .reduce((a, b) => a + b);
          expect(difference(124, 128), lessThan(12));
          expect(difference(125, 300),
              greaterThan(brightness == Brightness.light ? 75 : 25));
          for (var y = 0; y < 300; y += 10) {
            for (var x = 0; x < 430; x += 10) {
              expect(pixel(x, y, 3), 255,
                  reason: 'Frosted cards must not punch through the opaque '
                      'window background during tab entry $entry at ($x, $y)');
            }
          }
        }
        active.value = false;
        await tester.pumpAndSettle();
      }
    });

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
