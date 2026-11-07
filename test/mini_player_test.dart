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
import 'package:thmr_app/core/state/station_provider.dart';
import 'package:thmr_app/core/state/settings_provider.dart';
import 'package:thmr_app/core/theme/thmr_theme.dart';
import 'package:thmr_app/features/mini/mini_player.dart';
import 'package:thmr_app/shared/widgets/track_cover.dart';
import 'package:thmr_app/shared/widgets/volume_slider.dart';

void main() {
  testWidgets('side edge hides to a mouse-revealable strip', (tester) async {
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
    const screenChannel =
        MethodChannel('dev.leanflutter.plugins/screen_retriever');
    final positions = <Offset>[];
    var hides = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      windowChannel,
      (call) async {
        if (call.method == 'getBounds') {
          return {'x': 8.0, 'y': 100.0, 'width': 344.0, 'height': 112.0};
        }
        if (call.method == 'setBounds') {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          positions.add(Offset(args['x'] as double, args['y'] as double));
        }
        if (call.method == 'hide') hides++;
        return null;
      },
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      screenChannel,
      (call) async => {
        'displays': [
          {
            'id': '1',
            'size': {'width': 1920.0, 'height': 1080.0},
            'visiblePosition': {'dx': 0.0, 'dy': 0.0},
            'visibleSize': {'width': 1920.0, 'height': 1040.0},
          },
        ],
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(windowChannel, null);
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(screenChannel, null);
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
    listener.onWindowMoved();
    await advance(420);
    expect(positions.last, const Offset(-328, 100));
    expect(hides, 0);
    expect(find.text('暂无播放'), findsNothing);

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(340, 55));
    await advance(220);
    expect(positions.last, const Offset(0, 100));
    expect(find.text('暂无播放'), findsOneWidget);

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
    const screenChannel =
        MethodChannel('dev.leanflutter.plugins/screen_retriever');
    var windowPosition = const Offset(100, 5);
    final positions = <Offset>[];
    final dragDone = Completer<void>();
    var dragStarts = 0;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      windowChannel,
      (call) async {
        if (call.method == 'isFullScreen') return false;
        if (call.method == 'getBounds') {
          return {
            'x': windowPosition.dx,
            'y': windowPosition.dy,
            'width': kMiniWindowSize.width,
            'height': kMiniWindowSize.height,
          };
        }
        if (call.method == 'setBounds') {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          windowPosition = Offset(args['x'] as double, args['y'] as double);
          positions.add(windowPosition);
        }
        if (call.method == 'startDragging') {
          dragStarts++;
          windowPosition = const Offset(100, 100);
          await dragDone.future;
        }
        return null;
      },
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      screenChannel,
      (call) async => {
        'displays': [
          {
            'id': '1',
            'size': {'width': 1920.0, 'height': 1080.0},
            'visiblePosition': {'dx': 0.0, 'dy': 0.0},
            'visibleSize': {'width': 1920.0, 'height': 1040.0},
          },
        ],
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(windowChannel, null);
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(screenChannel, null);
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
    final top = miniEdgePlacement(
      const Rect.fromLTWH(-900, 25, 320, 96),
      workArea,
    );
    expect(top?.edge, MiniEdge.top);
    expect(top?.expanded, const Offset(-900, 20));
    expect(top?.tucked, const Offset(-900, -60));
    expect(top?.tuckedAt(46), const Offset(-900, -30));
    expect(top?.tuckedAt(3), const Offset(-900, -73));

    final corner = miniEdgePlacement(
      const Rect.fromLTWH(-1590, 25, 320, 96),
      workArea,
    );
    expect(corner?.edge, MiniEdge.top);

    final left = miniEdgePlacement(
      const Rect.fromLTWH(-1590, 100, 320, 96),
      workArea,
    );
    expect(left?.edge, MiniEdge.left);
    expect(left?.expanded, const Offset(-1600, 100));
    expect(left?.tucked, const Offset(-1904, 100));
    expect(left?.tuckedAt(3), const Offset(-1917, 100));

    final right = miniEdgePlacement(
      const Rect.fromLTWH(-326, 100, 320, 96),
      workArea,
    );
    expect(right?.edge, MiniEdge.right);
    expect(right?.expanded, const Offset(-320, 100));
    expect(right?.tucked, const Offset(-16, 100));
    expect(right?.tuckedAt(3), const Offset(-3, 100));

    expect(
      miniEdgePlacement(const Rect.fromLTWH(-950, 100, 320, 96), workArea),
      isNull,
    );
  });

  test('mini player uses the monitor containing most of its window', () {
    const left = Rect.fromLTWH(-1600, 20, 1600, 900);
    const right = Rect.fromLTWH(0, 0, 1920, 1040);
    expect(
      miniWorkAreaForWindow(
        const Rect.fromLTWH(-900, 25, 320, 96),
        [right, left],
      ),
      left,
    );
    expect(
      miniWorkAreaForWindow(
        const Rect.fromLTWH(-140, 25, 320, 96),
        [left, right],
      ),
      right,
    );
  });

  testWidgets('top edge supports summary, tab and hidden on a second monitor',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = kMiniWindowSize;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const windowChannel = MethodChannel('window_manager');
    const screenChannel =
        MethodChannel('dev.leanflutter.plugins/screen_retriever');
    final positions = <Offset>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      windowChannel,
      (call) async {
        if (call.method == 'getBounds') {
          return {'x': -900.0, 'y': 25.0, 'width': 344.0, 'height': 112.0};
        }
        if (call.method == 'setBounds') {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          positions.add(Offset(args['x'] as double, args['y'] as double));
        }
        return null;
      },
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      screenChannel,
      (call) async => {
        'displays': [
          {
            'id': 'main',
            'size': {'width': 1920.0, 'height': 1080.0},
            'visiblePosition': {'dx': 0.0, 'dy': 0.0},
            'visibleSize': {'width': 1920.0, 'height': 1040.0},
          },
          {
            'id': 'left',
            'size': {'width': 1600.0, 'height': 900.0},
            'visiblePosition': {'dx': -1600.0, 'dy': 20.0},
            'visibleSize': {'width': 1600.0, 'height': 900.0},
          },
        ],
      },
    );
    addTearDown(() {
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(windowChannel, null);
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(screenChannel, null);
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
    for (final textScale in [1.0, 1.3]) {
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
            // The production mini player is built outside Navigator/Overlay.
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
