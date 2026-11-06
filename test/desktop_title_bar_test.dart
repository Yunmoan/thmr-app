import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/shared/widgets/desktop_title_bar.dart';

void main() {
  const channel = MethodChannel('window_manager');
  final calls = <String>[];
  var maximized = false;

  setUp(() {
    calls.clear();
    maximized = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      if (call.method == 'isFullScreen') return false;
      if (call.method == 'isMaximized') return maximized;
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  Future<void> mountTitleBar(
    WidgetTester tester, {
    double width = 1000,
    VoidCallback? onMini,
  }) async {
    tester.view.physicalSize = Size(width, 660);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Match the app's builder: the title bar is outside Navigator/Overlay.
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => Align(
        alignment: Alignment.topCenter,
        child: DesktopTitleBar(onMini: onMini),
      ),
      home: const SizedBox.shrink(),
    ));
    await tester.pumpAndSettle();
  }

  for (final width in [430.0, 1000.0]) {
    for (final withMini in [false, true]) {
      testWidgets('all non-button title areas drag at $width, mini=$withMini',
          (tester) async {
        await mountTitleBar(tester,
            width: width, onMini: withMini ? () {} : null);
        final bar = tester.getRect(find.byType(DesktopTitleBar));
        final buttons = tester.getRect(find.byType(InkWell).first).left;
        final title = tester.getRect(find.text('东方音乐电台 THMR'));
        final logo = tester.getRect(find.byType(Image));
        final points = <Offset>[
          Offset(bar.left + 2, bar.center.dy),
          logo.center,
          title.center,
          Offset(title.right + (buttons - title.right) * 0.25, bar.center.dy),
          Offset((title.right + buttons) / 2, bar.center.dy),
          Offset(title.right + (buttons - title.right) * 0.75, bar.center.dy),
          Offset(buttons - 2, bar.center.dy),
          Offset(logo.center.dx, bar.top + 2),
          Offset(title.center.dx, bar.bottom - 2),
        ];
        final dragCounts = <int>[];
        for (final point in points) {
          calls.clear();
          await tester.dragFrom(point, const Offset(0, 40),
              kind: PointerDeviceKind.mouse);
          await tester.pumpAndSettle();
          dragCounts.add(calls.where((m) => m == 'startDragging').length);
        }
        expect(dragCounts, everyElement(1),
            reason: 'Each title-bar point must start a window drag: $points');
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('caption buttons keep their actions and do not start dragging',
      (tester) async {
    var miniCalls = 0;
    await mountTitleBar(tester, onMini: () => miniCalls++);
    for (final icon in [
      Icons.picture_in_picture_alt_rounded,
      Icons.remove_rounded,
      Icons.crop_square_rounded,
      Icons.close_rounded,
    ]) {
      calls.clear();
      final point = tester.getCenter(find.byIcon(icon));
      await tester.dragFrom(point, const Offset(0, 40),
          kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(calls, isEmpty);
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(calls, isNot(contains('startDragging')));
      switch (icon) {
        case Icons.picture_in_picture_alt_rounded:
          expect(miniCalls, 1);
        case Icons.remove_rounded:
          expect(calls, ['minimize']);
        case Icons.crop_square_rounded:
          expect(calls, ['isMaximized', 'maximize']);
        case Icons.close_rounded:
          expect(calls, ['close']);
      }
    }
    maximized = true;
    calls.clear();
    await tester.tap(find.byIcon(Icons.crop_square_rounded));
    await tester.pumpAndSettle();
    expect(calls, ['isMaximized', 'unmaximize']);
  });

  testWidgets('double-clicking the title toggles maximization', (tester) async {
    await mountTitleBar(tester);
    final point = tester.getCenter(find.text('东方音乐电台 THMR'));
    for (final isMaximized in [false, true]) {
      maximized = isMaximized;
      calls.clear();
      await tester.tapAt(point);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tapAt(point);
      await tester.pumpAndSettle();
      expect(calls, ['isMaximized', isMaximized ? 'unmaximize' : 'maximize']);
    }
  });
}
