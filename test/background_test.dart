import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/theme/thmr_colors.dart';
import 'package:thmr_app/shared/widgets/thmr_background.dart';

void main() {
  testWidgets('shared illustration is visible through a transparent page',
      (tester) async {
    tester.view.physicalSize = const Size(430, 660);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        theme: ThemeData(extensions: [ThmrTokens.reimuLight]),
        builder: (context, child) => Stack(
          fit: StackFit.expand,
          children: [
            const ThmrBackground(child: SizedBox.expand()),
            child!,
          ],
        ),
        home: const Scaffold(
          backgroundColor: Colors.transparent,
        ),
      ),
    ));
    await tester.runAsync(() => precacheImage(
          const AssetImage('assets/brand/background_alt.png'),
          key.currentContext!,
        ));
    await tester.pumpAndSettle();
    expect(tester.getSize(find.byType(Image)).height, greaterThan(400));
    final image =
        await (key.currentContext!.findRenderObject()! as RenderRepaintBoundary)
            .toImage(pixelRatio: 1);
    final bytes = await tester
        .runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba));
    int channel(int x, int y, int c) => bytes!.getUint8((y * 430 + x) * 4 + c);
    final difference = List.generate(
            3, (c) => (channel(90, 450, c) - channel(420, 450, c)).abs())
        .reduce((a, b) => a + b);
    expect(difference, greaterThan(25));
  });
}
