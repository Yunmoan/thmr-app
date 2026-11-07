import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thmr_app/core/player/playback_controller.dart';
import 'package:thmr_app/core/state/settings_provider.dart';
import 'package:thmr_app/core/state/station_provider.dart';
import 'package:thmr_app/features/mini/mini_player.dart';
import 'package:window_manager/window_manager.dart';

void main() {
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
    expect(harness.position, const Offset(-328, 100));
    expect(harness.maxPendingMoves, 1,
        reason: 'Slow window calls must not build a queue of stale positions.');

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(340, 55));
    await harness.advance(208);
    expect(harness.position, const Offset(0, 100));
    await mouse.moveTo(const Offset(500, 200));
    await tester.pump(const Duration(milliseconds: 450));
    await harness.advance(208);
    expect(harness.position, const Offset(-328, 100));
    await mouse.removePointer();
  });

  testWidgets('hover reverses an unfinished tuck immediately', (tester) async {
    final harness = _EdgeHarness(tester);
    await harness.mount();
    harness.listener.onWindowMoved();
    await tester.pump(const Duration(milliseconds: 180));
    await harness.advance(48);
    expect(harness.position.dx, lessThan(0));
    expect(harness.position.dx, greaterThan(-328));

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
    expect(harness.position, const Offset(-328, 100));
    expect(harness.maxPendingMoves, 1);
    final finishedMoves = harness.moveTimes.length;
    await harness.advance(200);
    expect(harness.moveTimes.length, finishedMoves,
        reason: 'Do not replay old positions after the animation ends. '
            '${harness.moveTimes} ${harness.movePositions}');

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(340, 55));
    await harness.advance(48);
    // Leave, allow a tuck to start, then reverse it while a slow native
    // position write is still in flight.
    await mouse.moveTo(const Offset(500, 200));
    await harness.advance(488);
    expect(harness.pendingMoves, 1);
    await mouse.moveTo(const Offset(340, 55));
    await harness.advance(272);
    expect(harness.position, const Offset(0, 100));
    expect(harness.maxPendingMoves, 1);
    await mouse.removePointer();
  });

  testWidgets('edge motion respects reduced motion', (tester) async {
    final harness = _EdgeHarness(tester);
    await harness.mount(reducedMotion: true);
    harness.listener.onWindowMoved();
    await tester.pump(const Duration(milliseconds: 180));
    await tester.pump();
    expect(harness.position, const Offset(-328, 100));
    expect(harness.moveTimes, hasLength(1));
    final tab = find.byKey(const ValueKey('mini-edge-tab'));
    expect(
        tester
            .widget<Opacity>(
                find.descendant(of: tab, matching: find.byType(Opacity)))
            .opacity,
        1,
        reason: 'Reduced motion must also skip the blue tab fade.');

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(340, 55));
    await tester.pump();
    expect(harness.position, const Offset(0, 100));
    expect(harness.moveTimes, hasLength(2));
    await mouse.removePointer();
  });
}

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
  }) async {
    _clockOrigin = tester.binding.clock.now();
    SharedPreferences.setMockInitialValues({'miniEdgeHideMode': hideMode.name});
    tester.view.physicalSize = kMiniWindowSize;
    tester.view.devicePixelRatio = 1;
    const window = MethodChannel('window_manager');
    const screen = MethodChannel('dev.leanflutter.plugins/screen_retriever');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(window,
        (call) async {
      if (call.method == 'getBounds') {
        return {
          'x': position.dx,
          'y': position.dy,
          'width': kMiniWindowSize.width,
          'height': kMiniWindowSize.height,
        };
      }
      if (call.method == 'setBounds') {
        pendingMoves++;
        if (pendingMoves > maxPendingMoves) maxPendingMoves = pendingMoves;
        if (nativeLatency != Duration.zero) {
          await Future<void>.delayed(nativeLatency);
        }
        final args = call.arguments as Map;
        position = Offset(args['x'] as double, args['y'] as double);
        moveTimes.add(tester.binding.clock.now().difference(_clockOrigin));
        movePositions.add(position);
        pendingMoves--;
      }
      return null;
    });
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        screen,
        (call) async => {
              'displays': [
                {
                  'id': '1',
                  'size': {'width': 1920.0, 'height': 1080.0},
                  'visiblePosition': {'dx': 0.0, 'dy': 0.0},
                  'visibleSize': {'width': 1920.0, 'height': 1040.0},
                },
              ],
            });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(window, null);
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(screen, null);
    });
    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data:
              MediaQuery.of(context).copyWith(disableAnimations: reducedMotion),
          child: child!,
        ),
        home: const MiniPlayerWindow(
          stationState: StationUiState(),
          playbackState: PlaybackState(),
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
