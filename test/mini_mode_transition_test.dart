import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thmr_app/features/mini/mini_player.dart';
import 'package:thmr_app/features/mini/desktop_player_surface.dart';

void main() {
  for (final entering in [true, false]) {
    testWidgets(
        '${entering ? 'enter' : 'exit'} keeps native frame changes off screen',
        (tester) async {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      if (!entering) {
        container.read(miniPlayerProvider.notifier).state = true;
        container.read(miniSavedBoundsProvider.notifier).state =
            const Rect.fromLTWH(100, 100, 1180, 780);
      }
      var concealed = false;
      final exposedChanges = <String>[];
      const presentation = MethodChannel('thmr/window_presentation');
      const window = MethodChannel('window_manager');
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(presentation, (call) async {
        if (call.method == 'conceal') concealed = true;
        if (call.method == 'reveal') concealed = false;
        return null;
      });
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(window,
          (call) async {
        if (call.method == 'isMaximized' || call.method == 'isMinimized') {
          return false;
        }
        if (call.method == 'getBounds') {
          return {'x': 100.0, 'y': 100.0, 'width': 1180.0, 'height': 780.0};
        }
        if ({
              'unmaximize',
              'maximize',
              'setAsFrameless',
              'setHasShadow',
              'setTitleBarStyle',
              'setResizable',
              'setMinimumSize',
              'setBounds',
              'setAlwaysOnTop',
            }.contains(call.method) &&
            !concealed) {
          exposedChanges.add(call.method);
        }
        return null;
      });
      addTearDown(() {
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(presentation, null);
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(window, null);
      });
      late WidgetRef ref;
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: Consumer(builder: (context, widgetRef, child) {
          ref = widgetRef;
          return const SizedBox.shrink();
        }),
      ));
      var completed = false;
      final transition = entering
          ? enterMiniMode(ref, TextScaler.noScaling)
          : exitMiniMode(ref);
      transition.then((_) => completed = true);
      for (var i = 0; i < 100 && !completed; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      expect(exposedChanges, isEmpty,
          reason: 'DWM decorations and client geometry must never change '
              'while the old or transparent Flutter surface is visible.');
      expect(completed, isTrue);
      await transition;
    }, skip: !Platform.isWindows);
  }

  testWidgets(
      'target raster fence gates reveal and coalesces repeated requests',
      (tester) async {
    final harness = _Harness(tester);
    await harness.mount();
    final mainState = harness.mainKey.currentState;
    final oldSize = tester.getSize(find.byKey(harness.mainKey));
    final oldOrigin = tester.getTopLeft(find.byKey(harness.mainKey));
    harness.concealGate = Completer<void>();
    final entering = harness.transition.change(true, TextScaler.noScaling);
    expect(
        harness.transition.change(true, TextScaler.noScaling), same(entering));
    // Do not resize, hide or transform the main content before DWM's reply.
    await tester.pump(const Duration(milliseconds: 40));
    expect(tester.getSize(find.byKey(harness.mainKey)), oldSize);
    expect(tester.getTopLeft(find.byKey(harness.mainKey)), oldOrigin);
    expect(harness.container.read(miniPlayerProvider), isFalse);
    expect(harness.mutations, isEmpty);

    harness.frameGate = Completer<void>();
    harness.concealGate!.complete();
    await harness.advance(500);
    expect(harness.frameRequests, 1);
    expect(harness.concealed, isTrue);
    expect(harness.reveals, 0);
    expect(harness.container.read(miniTransitionBusyProvider), isTrue);
    expect(harness.rect.size, kMiniWindowSize);
    expect(tester.widget<FadeTransition>(harness.fade).opacity.value, 0);
    expect(tester.binding.hasScheduledFrame, isTrue,
        reason: 'A static transparent target still needs fresh frames while '
            'the native resize/raster fence is pending.');

    harness.frameGate!.complete();
    await harness.advance(300);
    await entering;
    expect(harness.concealed, isFalse);
    expect(harness.reveals, 1);
    expect(tester.widget<FadeTransition>(harness.fade).opacity.value, 1);
    expect(tester.getSize(find.byKey(harness.mainKey, skipOffstage: false)),
        oldSize,
        reason: 'The retained main tree must use its client extent, not the '
            'outer native bounds including decorations.');
    expect(tester.binding.hasScheduledFrame, isFalse,
        reason: 'Stop driving redraws once presentation has completed.');

    final leaving = harness.transition.change(false, TextScaler.noScaling);
    await harness.advance(80);
    expect(harness.concealed, isFalse,
        reason:
            'The existing mini fade must finish before changing decorations.');
    expect(tester.widget<FadeTransition>(harness.fade).opacity.value,
        allOf(greaterThan(0), lessThan(1)));
    await harness.advance(400);
    await leaving;
    expect(harness.rect, _Harness.normalBounds);
    expect(harness.mainKey.currentState, same(mainState));
    expect(tester.getSize(find.byKey(harness.mainKey)), oldSize);
    expect(tester.getTopLeft(find.byKey(harness.mainKey)), oldOrigin);
    expect(harness.exposedChanges, isEmpty);
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);

  testWidgets('maximized bounds restore inside the cloak with reduced motion',
      (tester) async {
    final harness = _Harness(tester)..maximized = true;
    await harness.mount(reducedMotion: true);
    final entering = harness.transition.change(true, TextScaler.noScaling);
    await harness.advance(200);
    await entering;
    expect(harness.maximized, isFalse);
    expect(
        harness.container.read(miniSavedBoundsProvider), _Harness.normalBounds);
    final leaving = harness.transition.change(false, TextScaler.noScaling);
    await harness.advance(200);
    await leaving;
    expect(harness.maximized, isTrue);
    expect(harness.rect, _Harness.maximizedBounds);
    expect(harness.exposedChanges, isEmpty);
    expect(tester.takeException(), isNull);
  }, skip: !Platform.isWindows);

  for (final failOnEntry in [true, false]) {
    testWidgets(
        '${failOnEntry ? 'entry' : 'exit'} raster failure rolls back and reveals',
        (tester) async {
      final harness = _Harness(tester);
      await harness.mount(reducedMotion: true);
      if (!failOnEntry) {
        final entering = harness.transition.change(true, TextScaler.noScaling);
        await harness.advance(200);
        await entering;
      }
      final previousBounds = harness.rect;
      harness.failNextFrame = true;
      final failed = expectLater(
        harness.transition.change(failOnEntry, TextScaler.noScaling),
        throwsA(isA<PlatformException>()),
      );
      await harness.advance(400);
      await failed;
      expect(harness.rect, previousBounds);
      expect(harness.container.read(miniPlayerProvider), !failOnEntry);
      expect(harness.container.read(miniTransitionBusyProvider), isFalse);
      expect(harness.concealed, isFalse);
      expect(harness.exposedChanges, isEmpty);
      expect(tester.takeException(), isNull);
    }, skip: !Platform.isWindows);
  }
}

class _Harness {
  _Harness(this.tester);

  static const normalBounds = Rect.fromLTWH(100, 100, 1180, 780);
  static const maximizedBounds = Rect.fromLTWH(0, 0, 1920, 1040);
  final WidgetTester tester;
  final container = ProviderContainer();
  final mainKey = GlobalKey();
  final exposedChanges = <String>[];
  final mutations = <String>[];
  var rect = normalBounds;
  var maximized = false;
  var concealed = false;
  var reveals = 0;
  var frameRequests = 0;
  var failNextFrame = false;
  Completer<void>? concealGate;
  Completer<void>? frameGate;

  MiniModeTransition get transition =>
      container.read(miniModeTransitionProvider);
  Finder get fade => find.descendant(
      of: find.byType(MiniPlayerTransition),
      matching: find.byType(FadeTransition));

  Future<void> mount({bool reducedMotion = false}) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    rect = maximized ? maximizedBounds : normalBounds;
    tester.view.physicalSize = rect.size;
    const presentation = MethodChannel('thmr/window_presentation');
    const window = MethodChannel('window_manager');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(presentation,
        (call) async {
      if (call.method == 'conceal') {
        await concealGate?.future;
        concealed = true;
      } else if (call.method == 'setMaximized') {
        _mutation(call.method);
        maximized = call.arguments as bool;
        rect = maximized ? maximizedBounds : normalBounds;
        tester.view.physicalSize = rect.size;
      } else if (call.method == 'waitForFrame') {
        frameRequests++;
        expectSync(concealed, isTrue);
        expectSync(find.byType(MiniPlayerTransition),
            container.read(miniPlayerProvider) ? findsOneWidget : findsNothing);
        if (failNextFrame) {
          failNextFrame = false;
          throw PlatformException(code: 'frame_timeout');
        }
        await frameGate?.future;
      } else if (call.method == 'reveal') {
        reveals++;
        concealed = false;
      }
      return null;
    });
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(window,
        (call) async {
      if (call.method == 'isMaximized') return maximized;
      if (call.method == 'isMinimized') return false;
      if (call.method == 'getBounds') {
        return {
          'x': rect.left,
          'y': rect.top,
          'width': rect.width,
          'height': rect.height
        };
      }
      if (call.method.startsWith('set')) _mutation(call.method);
      if (call.method == 'setBounds') {
        final args = call.arguments as Map;
        rect = Rect.fromLTWH(
          (args['x'] as num?)?.toDouble() ?? rect.left,
          (args['y'] as num?)?.toDouble() ?? rect.top,
          (args['width'] as num?)?.toDouble() ?? rect.width,
          (args['height'] as num?)?.toDouble() ?? rect.height,
        );
        tester.view.physicalSize = rect.size;
      }
      return null;
    });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(presentation, null);
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(window, null);
    });
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data:
              MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
          child: DesktopPlayerSurface(
            miniPlayer: const ColoredBox(color: Colors.blue),
            child: _RetainedMain(key: mainKey),
          ),
        ),
        home: const SizedBox.shrink(),
      ),
    ));
  }

  void _mutation(String method) {
    mutations.add(method);
    if (!concealed) exposedChanges.add(method);
  }

  Future<void> advance(int milliseconds) async {
    for (var elapsed = 0; elapsed < milliseconds; elapsed += 20) {
      await tester.pump(const Duration(milliseconds: 20));
    }
  }
}

class _RetainedMain extends StatefulWidget {
  const _RetainedMain({super.key});

  @override
  State<_RetainedMain> createState() => _RetainedMainState();
}

class _RetainedMainState extends State<_RetainedMain> {
  @override
  Widget build(BuildContext context) => const ColoredBox(color: Colors.red);
}
