import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thmr_app/core/models/models.dart';
import 'package:thmr_app/core/player/playback_controller.dart';
import 'package:thmr_app/core/platform/window_presentation.dart';
import 'package:thmr_app/core/state/settings_provider.dart';
import 'package:thmr_app/core/state/station_provider.dart';
import 'package:thmr_app/features/mini/mini_player.dart';
import 'package:thmr_app/shared/widgets/track_cover.dart';
import 'package:window_manager/window_manager.dart';

import 'fixtures/mini_window_mock.dart';

void main() {
  testWidgets('a mixed-DPI seam stays open and the outer edge still tucks',
      (tester) async {
    final harness = _EdgeHarness(tester)..position = const Offset(1928, 180);
    await harness.mount(dpi: 144, displays: const [
      primaryMiniDisplay,
      (
        bounds: Rect.fromLTWH(1920, 0, 2560, 1440),
        workArea: Rect.fromLTWH(1920, 0, 2560, 1380),
      ),
    ]);
    final body = find.text('暂无播放');

    harness.listener.onWindowMoved();
    await harness.advance(420);
    expect(harness.movePositions, isEmpty);
    expect(body, findsOneWidget);

    // 距右边缘 24 个物理像素，在 18 个逻辑像素的阈值内。
    harness.position = const Offset(3940, 180);
    harness.listener.onWindowMoved();
    await harness.advance(420);
    expect(harness.position, const Offset(4444, 180));
    expect(body, findsOneWidget);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(8, 55));
    await harness.advance(220);
    expect(harness.position, const Offset(3964, 180));
    expect(body, findsOneWidget);
    await mouse.removePointer();
  });

  for (final dpi in [96, 120, 168, 192]) {
    testWidgets('compact summary meets the desktop edge at DPI $dpi',
        (tester) async {
      final harness = _EdgeHarness(tester)..position = const Offset(100, 5);
      await harness.mount(dpi: dpi);
      harness.listener.onWindowMoved();
      await harness.advance(420);

      final summary = find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_MiniCompactSummary',
      );
      expect(summary, findsOneWidget);
      final logicalTop = tester.getTopLeft(summary).dy;
      final desktopTop = harness.position.dy + logicalTop * (dpi / 96);
      expect(desktopTop, closeTo(0, 1e-6));
    });
  }

  for (final edge in [MiniEdge.left, MiniEdge.right]) {
    testWidgets('compact $edge keeps the actual player at the desktop edge',
        (tester) async {
      const dpi = 120;
      const scale = dpi / 96;
      final left = edge == MiniEdge.left;
      final desktopEdge = left
          ? primaryMiniDisplay.workArea.left
          : primaryMiniDisplay.workArea.right;
      final harness = _EdgeHarness(tester)
        ..position = Offset(
            left ? 8 : desktopEdge - kMiniWindowSize.width * scale - 8, 100);
      await harness.mount(dpi: dpi);
      final cover = find.byType(TrackCover);
      final close = find.byIcon(Icons.close_rounded);
      final coverElement = tester.element(cover);
      final coverRect = tester.getRect(cover);
      final closeRect = tester.getRect(close);
      harness.listener.onWindowMoved();
      await harness.advance(420);

      expect(tester.element(cover), same(coverElement));
      expect(tester.getRect(cover), coverRect);
      expect(tester.getRect(close), closeRect);
      expect(find.byKey(const ValueKey('mini-edge-tab')), findsNothing);
      final clip = tester.widget<ClipRect>(_peekClip);
      final strip = clip.clipper!.getClip(kMiniWindowSize);
      expect(strip.width, 24);
      expect(harness.position.dx + (left ? strip.left : strip.right) * scale,
          closeTo(desktopEdge, 1e-6));
      expect(strip.overlaps(coverRect), !left);
      expect(strip.overlaps(closeRect), left);
      expect(close.hitTestable(), findsNothing);
      final reveal = find.byWidgetPredicate(
        (widget) => widget is Semantics && widget.properties.label == '展开迷你播放器',
      );
      await tester.tap(reveal);
      await harness.advance(220);
      expect(_peekClip, findsNothing);
      expect(tester.element(cover), same(coverElement));
      expect(harness.position.dx,
          left ? 0 : desktopEdge - kMiniWindowSize.width * scale);
    });
  }

  testWidgets('blue edge tab fades in after tucking and can reverse mid-fade',
      (tester) async {
    final harness = _EdgeHarness(tester);
    await harness.mount(hideMode: MiniEdgeHideMode.tab);
    final body = find.byWidgetPredicate(
        (widget) => widget.runtimeType.toString() == '_MiniPlayerBody');
    final tabIcon = find.byIcon(Icons.chevron_right_rounded);
    double tabOpacity() => tester
        .widget<Opacity>(
            find.ancestor(of: tabIcon, matching: find.byType(Opacity)).first)
        .opacity;

    harness.listener.onWindowMoved();
    await tester.pump(const Duration(milliseconds: 180));
    for (var frame = 0; frame < 40 && body.evaluate().isNotEmpty; frame++) {
      await harness.advance(8);
    }
    expect(body, findsNothing);
    expect(tabOpacity(), lessThanOrEqualTo(0.05),
        reason: 'The blue tab should start fading in after the body tucks, '
            'rather than appear at full opacity.');
    await harness.advance(40);
    final fadingIn = tabOpacity();
    expect(fadingIn, allOf(greaterThan(0), lessThan(1)));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(340, 55));
    await tester.pump();
    expect(tabOpacity(), closeTo(fadingIn, 0.01),
        reason: 'Hover should reverse the current fade without a jump.');
    await harness.advance(48);
    expect(tabOpacity(), lessThan(fadingIn));
    await harness.advance(160);
    expect(tabOpacity(), 0);
    expect(harness.position, const Offset(0, 100));

    await mouse.moveTo(const Offset(500, 200));
    await tester.pump(const Duration(milliseconds: 450));
    await harness.advance(352);
    expect(tabOpacity(), 1);
    await mouse.removePointer();
  });

  for (final mode in MiniEdgeHideMode.values) {
    testWidgets(
        'top edge $mode slides the whole body off screen before removal',
        (tester) async {
      final harness = _EdgeHarness(tester)..position = const Offset(100, 5);
      await harness.mount(hideMode: mode);
      final body = find.byWidgetPredicate(
          (widget) => widget.runtimeType.toString() == '_MiniPlayerBody');
      harness.listener.onWindowMoved();
      await tester.pump(const Duration(milliseconds: 180));
      var previousVisibleHeight = kMiniWindowSize.height;
      var removed = false;
      for (var frame = 0; frame < 40; frame++) {
        await harness.advance(8);
        if (body.evaluate().isEmpty) {
          expect(previousVisibleHeight, lessThanOrEqualTo(1),
              reason: 'Do not remove the player body while a visible strip '
                  'is still on screen ($mode).');
          removed = true;
          break;
        }
        previousVisibleHeight =
            (tester.getBottomRight(body).dy + harness.position.dy)
                .clamp(0, kMiniWindowSize.height);
      }
      expect(removed, isTrue);
    });
  }

  testWidgets('edge motion follows frames without accumulating native latency',
      (tester) async {
    final harness =
        _EdgeHarness(tester, nativeLatency: const Duration(milliseconds: 8));
    await harness.mount();
    harness.listener.onWindowMoved();
    await tester.pump(const Duration(milliseconds: 180));
    await harness.advance(208);

    final gaps = [
      for (var i = 1; i < harness.moveTimes.length; i++)
        (harness.moveTimes[i] - harness.moveTimes[i - 1]).inMilliseconds,
    ];
    expect(gaps, isNotEmpty);
    expect(gaps.reduce((a, b) => a + b) / gaps.length, lessThanOrEqualTo(17),
        reason: 'An 8ms native reply must not add to the frame interval. '
            'Observed position update gaps: $gaps');
    expect(harness.position, const Offset(-320, 100));
    expect(harness.maxPendingMoves, 1,
        reason: 'Slow window calls must not build a queue of stale positions.');

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(340, 55));
    await harness.advance(208);
    expect(harness.position, const Offset(0, 100));
    await mouse.moveTo(const Offset(500, 200));
    await tester.pump(const Duration(milliseconds: 450));
    await harness.advance(208);
    expect(harness.position, const Offset(-320, 100));
    await mouse.removePointer();
  });

  testWidgets('hover reverses an unfinished tuck immediately', (tester) async {
    final harness = _EdgeHarness(tester);
    await harness.mount();
    harness.listener.onWindowMoved();
    await tester.pump(const Duration(milliseconds: 180));
    await harness.advance(48);
    expect(harness.position.dx, lessThan(0));
    expect(harness.position.dx, greaterThan(-320));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(340, 55));
    await harness.advance(208);
    expect(harness.position, const Offset(0, 100),
        reason: 'Entering while the window is tucking must reverse it, '
            'rather than leave it hidden under a stationary pointer.');
    await mouse.removePointer();
  });

  testWidgets('slow native moves coalesce and still finish on time',
      (tester) async {
    final harness =
        _EdgeHarness(tester, nativeLatency: const Duration(milliseconds: 40));
    await harness.mount();
    harness.listener.onWindowMoved();
    await tester.pump(const Duration(milliseconds: 180));
    await harness.advance(224);
    expect(harness.position, const Offset(-320, 100));
    expect(harness.maxPendingMoves, 1);
    final finishedMoves = harness.moveTimes.length;
    await harness.advance(200);
    expect(harness.moveTimes.length, finishedMoves,
        reason: 'Do not replay old positions after the animation ends. '
            '${harness.moveTimes} ${harness.movePositions}');

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(340, 55));
    await harness.advance(48);
    // 移开指针使窗口开始收起，在较慢的原生位置写入尚未返回时反转动画。
    await mouse.moveTo(const Offset(500, 200));
    await harness.advance(488);
    expect(harness.pendingMoves, 1);
    await mouse.moveTo(const Offset(340, 55));
    await harness.advance(272);
    expect(harness.position, const Offset(0, 100));
    expect(harness.maxPendingMoves, 1);
    await mouse.removePointer();
  });

  testWidgets('changing the edge mode retargets an unfinished tuck',
      (tester) async {
    final harness =
        _EdgeHarness(tester, nativeLatency: const Duration(milliseconds: 40));
    await harness.mount(hideMode: MiniEdgeHideMode.tab, dpi: 120);
    final settings =
        ProviderScope.containerOf(tester.element(find.byType(MiniPlayerWindow)))
            .read(settingsProvider.notifier);
    harness.listener.onWindowMoved();
    await tester.pump(const Duration(milliseconds: 180));
    await harness.advance(80);
    expect(harness.position.dx, inExclusiveRange(-410, 0));

    await settings.setMiniEdgeHideMode(MiniEdgeHideMode.compact);
    await harness.advance(272);
    expect(harness.position, const Offset(-400, 100));
    expect(tester.widget<ClipRect>(_peekClip).clipper!.getClip(kMiniWindowSize),
        const Rect.fromLTWH(320, 0, 24, 112));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(340, 55));
    await harness.advance(56);
    await settings.setMiniEdgeHideMode(MiniEdgeHideMode.hidden);
    await harness.advance(272);
    expect(harness.position, const Offset(0, 100));
    expect(harness.maxPendingMoves, 1);
    await mouse.removePointer();
  });

  testWidgets('the clipped subtitle stops rotating until the player expands',
      (tester) async {
    final harness = _EdgeHarness(tester);
    await harness.mount(
      stationState: const StationUiState(
        status: StationStatus(
          station: StationInfo(
              id: 'main',
              name: 'THMR',
              enabled: true,
              public: null,
              streamAuthEnabled: false,
              bitrates: []),
          listeners: 7,
          uniqueIps: 7,
          current: null,
          previous: null,
          queue: [],
        ),
      ),
    );
    final listeners = find.text('7 人在听');
    harness.listener.onWindowMoved();
    await harness.advance(420);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(_peekClip, findsOneWidget);
    expect(listeners, findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);

    harness.listener.onWindowEvent('show');
    await harness.advance(220);
    expect(harness.position, const Offset(0, 100));
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(listeners, findsOneWidget);
  });

  testWidgets('edge motion respects reduced motion', (tester) async {
    final harness = _EdgeHarness(tester);
    await harness.mount(reducedMotion: true);
    harness.listener.onWindowMoved();
    await tester.pump(const Duration(milliseconds: 180));
    await tester.pump();
    expect(harness.position, const Offset(-320, 100));
    expect(harness.moveTimes, hasLength(1));
    expect(tester.widget<ClipRect>(_peekClip).clipper!.getClip(kMiniWindowSize),
        const Rect.fromLTWH(320, 0, 24, 112));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(340, 55));
    await tester.pump();
    expect(harness.position, const Offset(0, 100));
    expect(harness.moveTimes, hasLength(2));
    await mouse.removePointer();
  });
}

Finder get _peekClip => find.byWidgetPredicate(
    (widget) => widget is ClipRect && widget.clipper != null);

class _EdgeHarness {
  _EdgeHarness(this.tester, {this.nativeLatency = Duration.zero});

  final WidgetTester tester;
  final Duration nativeLatency;
  final moveTimes = <Duration>[];
  final movePositions = <Offset>[];
  late DateTime _clockOrigin;
  var position = const Offset(8, 100);
  var pendingMoves = 0;
  var maxPendingMoves = 0;

  WindowListener get listener =>
      tester.state(find.byType(MiniPlayerWindow)) as WindowListener;

  Future<void> mount({
    bool reducedMotion = false,
    MiniEdgeHideMode hideMode = MiniEdgeHideMode.compact,
    int dpi = 96,
    List<WindowDisplay> displays = const [primaryMiniDisplay],
    StationUiState stationState = const StationUiState(),
  }) async {
    _clockOrigin = tester.binding.clock.now();
    SharedPreferences.setMockInitialValues({'miniEdgeHideMode': hideMode.name});
    final scale = dpi / 96;
    final physicalSize = kMiniWindowSize * scale;
    tester.view.physicalSize = physicalSize;
    tester.view.devicePixelRatio = scale;
    mockMiniWindow(
      tester,
      bounds: () => position & physicalSize,
      dpi: dpi,
      displays: displays,
      move: (target) async {
        pendingMoves++;
        if (pendingMoves > maxPendingMoves) maxPendingMoves = pendingMoves;
        if (nativeLatency != Duration.zero) {
          await Future<void>.delayed(nativeLatency);
        }
        position = target;
        moveTimes.add(tester.binding.clock.now().difference(_clockOrigin));
        movePositions.add(position);
        pendingMoves--;
      },
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data:
              MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
          child: child!,
        ),
        home: MiniPlayerWindow(
          stationState: stationState,
          playbackState: const PlaybackState(),
        ),
      ),
    ));
  }

  Future<void> advance(int milliseconds) async {
    for (var elapsed = 0; elapsed < milliseconds; elapsed += 8) {
      await tester.pump(const Duration(milliseconds: 8));
    }
  }
}
