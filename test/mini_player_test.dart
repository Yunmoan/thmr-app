import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:thmr_app/core/models/models.dart';
import 'package:thmr_app/core/player/playback_controller.dart';
import 'package:thmr_app/core/platform/window_presentation.dart';
import 'package:thmr_app/core/state/station_provider.dart';
import 'package:thmr_app/core/state/settings_provider.dart';
import 'package:thmr_app/core/theme/thmr_theme.dart';
import 'package:thmr_app/features/mini/mini_player.dart';
import 'package:thmr_app/shared/widgets/track_cover.dart';
import 'package:thmr_app/shared/widgets/volume_slider.dart';

import 'fixtures/mini_window_mock.dart';

void main() {
  testWidgets('side peek expands on activation or hover', (tester) async {
    SharedPreferences.setMockInitialValues({});
    Future<void> advance(int milliseconds) async {
      for (var elapsed = 0; elapsed < milliseconds; elapsed += 20) {
        await tester.pump(const Duration(milliseconds: 20));
      }
    }

    tester.view.physicalSize = kMiniWindowSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const windowChannel = MethodChannel('window_manager');
    var hides = 0;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(windowChannel, (call) async {
      if (call.method == 'hide') hides++;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(windowChannel, null));
    final positions = <Offset>[];
    var position = const Offset(8, 100);
    mockMiniWindow(
      tester,
      bounds: () => position & kMiniWindowSize,
      move: (target) {
        position = target;
        positions.add(target);
      },
    );
    await WindowPresentation().startupReady();
    addTearDown(() {
      miniPresentationChannel.setMethodCallHandler(null);
    });

    await tester.pumpWidget(ProviderScope(
      child: MaterialApp(
        builder: (context, child) => const MiniPlayerWindow(
          stationState: StationUiState(),
          playbackState: PlaybackState(),
        ),
        home: const SizedBox.shrink(),
      ),
    ));
    final listener =
        tester.state(find.byType(MiniPlayerWindow)) as WindowListener;
    final reveal = find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == '展开迷你播放器',
    );
    listener.onWindowMoved();
    await advance(420);
    expect(positions.last, const Offset(-320, 100));
    expect(hides, 0);
    expect(reveal, findsOneWidget);

    // 再次启动时，即使 HWND 已可见且未收到新显示事件，也应展开缩在屏幕外的迷你播放器。
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      miniPresentationChannel.name,
      miniPresentationChannel.codec
          .encodeMethodCall(const MethodCall('activate')),
      (_) {},
    );
    await advance(220);
    expect(positions.last, const Offset(0, 100));
    expect(reveal, findsNothing);
    position = const Offset(8, 100);
    listener.onWindowMoved();
    await advance(420);
    expect(reveal, findsOneWidget);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(340, 55));
    await advance(220);
    expect(positions.last, const Offset(0, 100));
    expect(reveal, findsNothing);

    await ProviderScope.containerOf(
            tester.element(find.byType(MiniPlayerWindow)))
        .read(settingsProvider.notifier)
        .setMiniEdgeHideMode(MiniEdgeHideMode.hidden);

    await mouse.moveTo(const Offset(500, 200));
    await advance(700);
    expect(positions.last, const Offset(-341, 100));
    expect(hides, 0);
    await mouse.moveTo(const Offset(342, 55));
    await advance(220);
    expect(positions.last, const Offset(0, 100));
    await mouse.removePointer();
  });

  testWidgets('drag and mode changes cancel in-flight edge animations',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = kMiniWindowSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const windowChannel = MethodChannel('window_manager');
    var windowPosition = const Offset(100, 5);
    final positions = <Offset>[];
    final dragDone = Completer<void>();
    var dragStarts = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      windowChannel,
      (call) async {
        if (call.method == 'isFullScreen') return false;
        if (call.method == 'startDragging') {
          dragStarts++;
          windowPosition = const Offset(100, 100);
          await dragDone.future;
        }
        return null;
      },
    );
    mockMiniWindow(
      tester,
      bounds: () => windowPosition & kMiniWindowSize,
      move: (target) {
        windowPosition = target;
        positions.add(target);
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(windowChannel, null);
    });

    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
        home: MiniPlayerWindow(
          stationState: StationUiState(),
          playbackState: PlaybackState(),
        ),
      ),
    ));
    final listener =
        tester.state(find.byType(MiniPlayerWindow)) as WindowListener;
    listener.onWindowMoved();
    for (var i = 0; i < 13; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(positions, isNotEmpty);

    final gesture = await tester.startGesture(const Offset(110, 50));
    await gesture.moveBy(const Offset(24, 0));
    await tester.pump();
    expect(dragStarts, 1);
    final movesAtDragStart = positions.length;
    listener.onWindowMoved();
    for (var i = 0; i < 16; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(positions.length, movesAtDragStart);

    await gesture.up();
    dragDone.complete();
    for (var i = 0; i < 13; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(windowPosition, const Offset(100, 100));
    expect(positions.length, movesAtDragStart);

    windowPosition = const Offset(100, 5);
    listener.onWindowMoved();
    for (var i = 0; i < 13; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(positions.length, greaterThan(movesAtDragStart));
    final movesAtModeChange = positions.length;
    ProviderScope.containerOf(tester.element(find.byType(MiniPlayerWindow)))
        .read(miniTransitionBusyProvider.notifier)
        .state = true;
    listener.onWindowMoved();
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(positions.length, movesAtModeChange);
  });

  test('mini player tucks against either edge of a monitor work area', () {
    const workArea = Rect.fromLTWH(-1600, 20, 1600, 900);
    MiniEdgePlacement? placement(Rect bounds) => miniEdgePlacement((
          bounds: bounds,
          scale: 1.0,
          displays: [(bounds: workArea, workArea: workArea)],
        ));

    final top = placement(const Rect.fromLTWH(-900, 25, 320, 96));
    expect(top?.edge, MiniEdge.top);
    expect(top?.expanded, const Offset(-900, 20));
    expect(top?.tuckedAt(16), const Offset(-900, -60));
    expect(top?.tuckedAt(46), const Offset(-900, -30));
    expect(top?.tuckedAt(3), const Offset(-900, -73));

    final corner = placement(const Rect.fromLTWH(-1590, 25, 320, 96));
    expect(corner?.edge, MiniEdge.top);

    final left = placement(const Rect.fromLTWH(-1590, 100, 320, 96));
    expect(left?.edge, MiniEdge.left);
    expect(left?.expanded, const Offset(-1600, 100));
    expect(left?.tuckedAt(16), const Offset(-1904, 100));
    expect(left?.tuckedAt(3), const Offset(-1917, 100));

    final right = placement(const Rect.fromLTWH(-326, 100, 320, 96));
    expect(right?.edge, MiniEdge.right);
    expect(right?.expanded, const Offset(-320, 100));
    expect(right?.tuckedAt(16), const Offset(-16, 100));
    expect(right?.tuckedAt(3), const Offset(-3, 100));

    expect(placement(const Rect.fromLTWH(-950, 100, 320, 96)), isNull);
  });

  test('an offset monitor only blocks the part of an edge it shares', () {
    const neighbor = Rect.fromLTWH(1920, 250, 1600, 900);
    MiniEdgePlacement? placement(double y) => miniEdgePlacement((
          bounds: Rect.fromLTWH(1568, y, 344, 112),
          scale: 1.0,
          displays: [
            primaryMiniDisplay,
            (bounds: neighbor, workArea: neighbor),
          ],
        ));

    expect(placement(138)?.edge, MiniEdge.right);
    expect(placement(139), isNull);
  });

  test('a stacked monitor blocks tucking even through its taskbar', () {
    expect(
      miniEdgePlacement((
        bounds: const Rect.fromLTWH(200, 8, 344, 112),
        scale: 1.0,
        displays: const [
          primaryMiniDisplay,
          (
            bounds: Rect.fromLTWH(0, -1080, 1920, 1080),
            workArea: Rect.fromLTWH(0, -1080, 1920, 960),
          ),
        ],
      )),
      isNull,
    );
  });

  testWidgets('top edge supports summary, tab and hidden on a second monitor',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = kMiniWindowSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final positions = <Offset>[];
    var position = const Offset(-900, 25);
    mockMiniWindow(
      tester,
      bounds: () => position & kMiniWindowSize,
      move: (target) {
        position = target;
        positions.add(target);
      },
      displays: const [
        primaryMiniDisplay,
        (
          bounds: Rect.fromLTWH(-1600, 20, 1600, 900),
          workArea: Rect.fromLTWH(-1600, 20, 1600, 900),
        ),
      ],
    );

    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(
        home: MiniPlayerWindow(
          stationState: StationUiState(),
          playbackState: PlaybackState(),
        ),
      ),
    ));
    final listener =
        tester.state(find.byType(MiniPlayerWindow)) as WindowListener;
    listener.onWindowMoved();
    for (var i = 0; i < 21; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(positions.last, const Offset(-900, -46));
    expect(find.text('暂无播放'), findsOneWidget);
    expect(find.text('等待下一首'), findsOneWidget);
    expect(find.byType(TrackCover), findsOneWidget);

    final settings =
        ProviderScope.containerOf(tester.element(find.byType(MiniPlayerWindow)))
            .read(settingsProvider.notifier);
    final illustration = find.byWidgetPredicate((widget) {
      if (widget is! Image || widget.image is! ResizeImage) return false;
      final image = (widget.image as ResizeImage).imageProvider;
      return image is AssetImage &&
          image.assetName == 'assets/brand/background_alt.png';
    });
    expect(illustration, findsOneWidget);
    await settings.setMiniShowIllustration(false);
    await tester.pump();
    expect(illustration, findsNothing);
    expect(
        (await SharedPreferences.getInstance()).getBool('miniShowIllustration'),
        isFalse);
    await settings.setMiniShowIllustration(true);
    await tester.pump();
    expect(illustration, findsOneWidget);

    await settings.setMiniEdgeHideMode(MiniEdgeHideMode.tab);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(positions.last, const Offset(-900, -76));
    expect(find.byIcon(Icons.keyboard_arrow_down_rounded), findsOneWidget);
    final tab = find.byWidgetPredicate((widget) =>
        widget is SizedBox && widget.width == 44 && widget.height == 16);
    expect(tab, findsOneWidget);

    await settings.setMiniEdgeHideMode(MiniEdgeHideMode.hidden);
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(positions.last, const Offset(-900, -89));
    expect(find.text('暂无播放'), findsNothing);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(172, 110));
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(positions.last, const Offset(-900, 20));
    await mouse.removePointer();
  });

  for (final preset in MiniPlayerSizePreset.values) {
    for (final textScale in [1.0, 1.3, 2.0]) {
      testWidgets('mini player $preset fits at ${textScale}x text',
          (tester) async {
        final windowSize =
            miniWindowSize(TextScaler.linear(textScale), preset: preset);
        tester.view.physicalSize = windowSize;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
            theme: ThmrTheme.light(),
            // 正式应用的迷你播放器构建在 Navigator 和 Overlay 之外。
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(textScale),
              ),
              child: MiniPlayerWindow(
                stationState: StationUiState(
                  status: const StationStatus(
                    station: StationInfo(
                      id: 'main',
                      name: 'THMR',
                      enabled: true,
                      public: null,
                      streamAuthEnabled: false,
                      bitrates: [],
                    ),
                    listeners: 3,
                    uniqueIps: 3,
                    current: CurrentTrack(
                      trackId: '1',
                      title: 'Saigetsu (tribetrigger edit)',
                      artist: 'tribetrigger',
                      coverUrl: '',
                      startedAtMs: 0,
                      expectedEndMs: 0,
                      positionSec: 58,
                      durationSec: 253,
                    ),
                    previous: null,
                    queue: [],
                  ),
                  updatedAt: DateTime.now(),
                ),
                playbackState: const PlaybackState(),
              ),
            ),
            home: const SizedBox.shrink(),
          ),
        ));

        expect(tester.takeException(), isNull);
        expect(find.byType(VolumeSlider), findsOneWidget);
        expect(find.text('00:58'), findsNothing);
        expect(find.text('放送中'), findsNothing);
        expect(tester.getBottomLeft(find.byType(VolumeSlider)).dy,
            lessThan(windowSize.height));
        if (textScale == 1.0) {
          expect(find.text('tribetrigger'), findsOneWidget);
          await tester.pump(const Duration(seconds: 4));
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text('3 人在听'), findsOneWidget);
          await tester.pump(const Duration(seconds: 4));
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text('tribetrigger'), findsOneWidget);
        }
      });
    }
  }
}
