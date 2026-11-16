import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thmr_app/core/input/app_input.dart';
import 'package:thmr_app/core/input/app_commands.dart';
import 'package:thmr_app/core/models/models.dart';
import 'package:thmr_app/core/player/playback_controller.dart';
import 'package:thmr_app/core/state/station_provider.dart';
import 'package:thmr_app/core/state/large_screen_settings.dart';
import 'package:thmr_app/core/state/channel_provider.dart';
import 'package:thmr_app/features/listen/widgets/channel_switcher.dart';
import 'package:thmr_app/shared/widgets/thmr_background.dart';
import 'package:thmr_app/features/large_screen/large_screen_button.dart';
import 'package:thmr_app/features/large_screen/large_screen_controller.dart';
import 'package:thmr_app/features/large_screen/large_screen_player.dart';
import 'package:thmr_app/features/large_screen/large_screen_surface.dart';
import 'package:thmr_app/features/mini/mini_player.dart';
import 'package:thmr_app/features/mini/desktop_player_surface.dart';
import 'package:thmr_app/core/theme/thmr_focus_ring.dart';

StationStatus _status({String title = '幽雅に咲かせ、墨染の桜', int queueCount = 1}) =>
    StationStatus.fromJson({
      'station': {'id': 'touhou', 'name': '东方音乐电台'},
      'current': {
        'trackId': 'one',
        'title': title,
        'artist': '上海アリス幻樂団',
        'positionSec': 75,
        'durationSec': 240,
      },
      'queue': [
        for (var i = 0; i < queueCount; i++)
          {
            'trackId': 'queued-$i',
            'title': i == 0 ? '少女綺想曲' : '接下来 $i',
            'artist': 'ZUN'
          },
      ],
    });

class _Station extends StateNotifier<StationUiState> implements StationPoller {
  _Station()
      : super(StationUiState(
            status: _status(),
            initialLoading: false,
            updatedAt: DateTime.now()));

  void update(StationUiState value) => state = value;

  @override
  Future<void> refresh() async {}
}

class _Playback extends StateNotifier<PlaybackState>
    implements PlaybackController {
  _Playback() : super(const PlaybackState(phase: PlaybackPhase.online));
  int toggles = 0;

  @override
  Future<void> toggle(String? url) async {
    toggles++;
    state = state.copyWith(
        phase: state.phase == PlaybackPhase.online
            ? PlaybackPhase.idle
            : PlaybackPhase.online);
  }

  @override
  Future<void> setVolume(double value) async {
    state = state.copyWith(volume: value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Harness {
  _Harness(this.tester);
  final WidgetTester tester;
  final navigator = GlobalKey<NavigatorState>();
  final scroll = ScrollController();
  final mainFocus = FocusNode();
  final surfaceRevision = ValueNotifier(0);
  final station = _Station();
  final playback = _Playback();
  final calls = <bool>[];
  final nativeMethods = <String>[];
  late final container = ProviderContainer(overrides: [
    stationProvider.overrideWith((ref) => station),
    playbackProvider.overrideWith((ref) => playback),
    streamUrlProvider.overrideWithValue('https://radio.test/live'),
    channelCatalogProvider.overrideWith((ref) async => const [
          RadioChannel(id: 'touhou', name: '综合频道'),
          RadioChannel(id: 'other', name: '原曲频道')
        ]),
    gamepadEventsProvider.overrideWithValue(const Stream.empty()),
    gamepadConnectionsProvider.overrideWithValue(const Stream.empty()),
  ]);
  LargeScreenController get controller =>
      container.read(largeScreenProvider.notifier);
  bool nativeFullScreen = false;
  bool failEnter = false;
  bool failExit = false;
  bool resizeOnTransition = false;
  bool deferFullScreenEvent = false;
  EdgeInsets workAreaInsets = EdgeInsets.zero;
  Completer<void>? enterGate;
  Completer<void>? frameGate;
  bool concealed = false;
  final revealed = <LargeScreenState>[];
  final flushed = <LargeScreenState>[];

  Future<void> mount(
      {Size size = const Size(1280, 720),
      double scale = 1,
      bool desktopRoot = false,
      bool reducedMotion = false}) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('window_manager'), (call) async {
      nativeMethods.add(call.method);
      if (call.method == 'isFullScreen') return nativeFullScreen;
      if (call.method == 'isMaximized') return false;
      if (call.method == 'getBounds') {
        return {
          'x': 100.0,
          'y': 100.0,
          'width': tester.view.physicalSize.width,
          'height': tester.view.physicalSize.height
        };
      }
      if (call.method == 'setFullScreen') {
        final active = (call.arguments as Map)['isFullScreen'] as bool;
        calls.add(active);
        if (active && failEnter) throw PlatformException(code: 'unavailable');
        if (!active && failExit) throw PlatformException(code: 'unavailable');
        if (active) await enterGate?.future;
        nativeFullScreen = active;
        if (resizeOnTransition) {
          tester.view.physicalSize = active ? const Size(1920, 1080) : size;
        }
        if (!deferFullScreenEvent) controller.nativeFullScreenChanged(active);
      }
      return null;
    });
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('thmr/window_presentation'), (call) async {
      if (call.method == 'workAreaInsets') {
        return {
          'left': workAreaInsets.left,
          'top': workAreaInsets.top,
          'right': workAreaInsets.right,
          'bottom': workAreaInsets.bottom
        };
      }
      if (call.method == 'conceal') concealed = true;
      if (call.method == 'waitForFrame') await frameGate?.future;
      if (call.method == 'flushFrame') {
        flushed.add(container.read(largeScreenProvider));
      }
      if (call.method == 'reveal') {
        concealed = false;
        revealed.add(container.read(largeScreenProvider));
      }
      return null;
    });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
      scroll.dispose();
      mainFocus.dispose();
      surfaceRevision.dispose();
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('window_manager'), null);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('thmr/window_presentation'), null);
    });
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(
          textButtonTheme: TextButtonThemeData(
              style: ButtonStyle(
                  backgroundBuilder:
                      desktopRoot ? ThmrFocusRing.buttonBuilder : null)),
          iconButtonTheme: IconButtonThemeData(
              style: ButtonStyle(
                  backgroundBuilder: desktopRoot
                      ? ThmrFocusRing.circularButtonBuilder
                      : null)),
        ),
        navigatorKey: navigator,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: reducedMotion),
          child: AppInput(
              navigatorKey: navigator,
              child: desktopRoot
                  ? Consumer(
                      builder: (context, ref, _) => ThmrFocusLayer(
                          reserveEdgeSpace: !ref.watch(
                              largeScreenProvider.select((s) => s.active)),
                          child: DesktopPlayerSurface(child: child!)))
                  : child!),
        ),
        home: ValueListenableBuilder(
            valueListenable: surfaceRevision,
            builder: (_, revision, __) => LargeScreenSurface(
                  key: ValueKey(revision),
                  child: Scaffold(
                    body: Column(children: [
                      TextButton(
                          focusNode: mainFocus,
                          onPressed: () {},
                          child: const Text('main control')),
                      const LargeScreenButton(),
                      Expanded(
                        child: ListView.builder(
                            key: const ValueKey('retained-list'),
                            controller: scroll,
                            itemCount: 100,
                            itemExtent: 50,
                            itemBuilder: (_, i) => Text('row $i')),
                      ),
                    ]),
                  ),
                )),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> change(bool active) async {
    final pending = controller.change(active);
    await tester.pumpAndSettle();
    await pending;
    await tester.pump();
  }
}

void main() {
  for (final size in [
    const Size(2560, 1440),
    const Size(1280, 720),
    const Size(800, 400)
  ]) {
    testWidgets(
        'large widgets and playback remain inside the work area at $size',
        (tester) async {
      final h = _Harness(tester)
        ..workAreaInsets = const EdgeInsets.only(bottom: 48);
      await h.mount(
          size: size, scale: size.width == 800 ? 2 : 1, desktopRoot: true);
      await h.container.read(largeScreenSettingsProvider.notifier).update(
              LargeScreenSettings(
                  queue: LargeScreenQueue.list,
                  layout: LargeScreenLayout.centered,
                  contentMargin: 64,
                  autoHideControls: false,
                  widgets: [
                for (final position in LargeScreenWidgetPosition.values)
                  LargeScreenWidgetSettings(
                      id: position.name,
                      kind: LargeScreenWidgetKind.text,
                      text: '活动文字 ' * 40,
                      position: position,
                      fontSize: 96,
                      maxLines: 4),
              ]));
      await h.change(true);
      final controls =
          tester.getRect(find.byKey(const ValueKey('large-screen-controls')));
      expect(controls.bottom, lessThanOrEqualTo(size.height - 48));
      expect(find.byTooltip('收起大屏模式').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }

  testWidgets('all stage controls stay inside the Windows taskbar work area',
      (tester) async {
    final h = _Harness(tester)
      ..workAreaInsets = const EdgeInsets.only(bottom: 54, left: 40);
    await h.mount(size: const Size(1920, 1080), desktopRoot: true);
    await h.change(true);
    final controls =
        tester.getRect(find.byKey(const ValueKey('large-screen-controls')));
    expect(controls.bottom, lessThanOrEqualTo(1080 - 54));
    expect(
        tester
            .getRect(find.byKey(const ValueKey('large-screen-window-drag')))
            .left,
        greaterThanOrEqualTo(40));
    expect(find.byTooltip('收起大屏模式').hitTestable(), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  for (final duringEntrance in [false, true]) {
    testWidgets(
        'remounting during stage entry never strands opacity at zero: entrance=$duringEntrance',
        (tester) async {
      final h = _Harness(tester)..frameGate = Completer<void>();
      await h.mount();
      final entering = h.controller.change(true);
      for (var i = 0; i < 40 && !h.concealed; i++) {
        await tester.pump(const Duration(milliseconds: 20));
      }
      await tester.pump();
      if (duringEntrance) {
        h.frameGate!.complete();
        for (var i = 0; i < 12 && h.revealed.isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 10));
        }
        await tester.pump(const Duration(milliseconds: 40));
      }
      h.surfaceRevision.value++;
      await tester.pump();
      if (!duringEntrance) h.frameGate!.complete();
      await tester.pumpAndSettle();
      await entering;
      final fade = find
          .descendant(
              of: find.byKey(const ValueKey('large-mode-transition')),
              matching: find.byType(FadeTransition))
          .first;
      expect(h.container.read(largeScreenProvider).busy, isFalse);
      expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
      expect(find.byTooltip('收起大屏模式').hitTestable(), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }

  testWidgets(
      'production desktop wrappers reveal all stage content after entry',
      (tester) async {
    final h = _Harness(tester)..resizeOnTransition = true;
    await h.mount(desktopRoot: true);
    final previousHighlight = FocusManager.instance.highlightStrategy;
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
        () => FocusManager.instance.highlightStrategy = previousHighlight);
    final retained =
        tester.element(find.byKey(const ValueKey('retained-list')));
    h.mainFocus.requestFocus();
    await tester.pumpAndSettle();
    await h.change(true);
    final fade = find
        .descendant(
            of: find.byKey(const ValueKey('large-mode-transition')),
            matching: find.byType(FadeTransition))
        .first;
    expect(h.container.read(largeScreenProvider).busy, isFalse);
    expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
    expect(find.byTooltip('收起大屏模式').hitTestable(), findsOneWidget);
    await h.change(false);
    expect(tester.element(find.byKey(const ValueKey('retained-list'))),
        same(retained));
    expect(h.mainFocus.hasFocus, isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('asynchronous native fullscreen waits for the completion event',
      (tester) async {
    final h = _Harness(tester)..deferFullScreenEvent = true;
    await h.mount();
    final entering = h.controller.change(true);
    for (var i = 0; i < 30 && h.calls.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(h.container.read(largeScreenProvider).busy, isTrue);
    h.controller.nativeFullScreenChanged(true);
    await tester.pumpAndSettle();
    await entering;
    final exiting = h.controller.change(false);
    for (var i = 0; i < 30 && h.calls.length < 2; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(h.container.read(largeScreenProvider).active, isTrue);
    expect(h.container.read(largeScreenProvider).busy, isTrue);
    h.controller.nativeFullScreenChanged(false);
    await tester.pumpAndSettle();
    await exiting;
    expect(h.container.read(largeScreenProvider).active, isFalse);
    expect(h.container.read(largeScreenProvider).busy, isFalse);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('Escape during a native entrance completes the queued exit',
      (tester) async {
    final h = _Harness(tester)..frameGate = Completer<void>();
    await h.mount();
    final entering = h.controller.change(true);
    for (var i = 0; i < 30 && !h.concealed; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    h.frameGate!.complete();
    await tester.pumpAndSettle();
    await entering;
    expect(h.container.read(largeScreenProvider).active, isFalse);
    expect(h.container.read(largeScreenProvider).busy, isFalse);
    expect(h.calls, [true, false]);
    expect(h.concealed, isFalse);
    expect(find.text('main control'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('both presentations animate and preserve the normal page element',
      (tester) async {
    final h = _Harness(tester);
    await h.mount();
    final retained =
        tester.element(find.byKey(const ValueKey('retained-list')));
    Finder fade(String key) => find
        .descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(FadeTransition))
        .first;
    final entering = h.controller.change(true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    expect(
        tester
            .widget<FadeTransition>(fade('standard-mode-transition'))
            .opacity
            .value,
        inExclusiveRange(0, 1));
    expect(h.container.read(largeScreenProvider).busy, isTrue);
    await tester.pumpAndSettle();
    await entering;
    final exiting = h.controller.change(false);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    expect(
        tester
            .widget<FadeTransition>(fade('large-mode-transition'))
            .opacity
            .value,
        inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    await exiting;
    expect(tester.element(find.byKey(const ValueKey('retained-list'))),
        same(retained));
    expect(
        tester
            .widget<FadeTransition>(fade('standard-mode-transition'))
            .opacity
            .value,
        1);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
      'stage layout and illustration settings retain the header and controls',
      (tester) async {
    final h = _Harness(tester);
    await h.mount();
    h.station.update(
        StationUiState(status: _status(queueCount: 50), initialLoading: false));
    await h.change(true);
    final header = tester.element(find.byType(ChannelSwitcher));
    final controls = tester.element(find.byTooltip('暂停播放'));
    for (final layout in LargeScreenLayout.values) {
      await h.container.read(largeScreenSettingsProvider.notifier).update(
          LargeScreenSettings(
              layout: layout,
              queue: LargeScreenQueue.list,
              framing: LargeScreenFraming.fit,
              cardLayout: true,
              showIllustration: false));
      await tester.pump(const Duration(milliseconds: 60));
      expect(tester.element(find.byType(ChannelSwitcher)), same(header));
      expect(tester.element(find.byTooltip('暂停播放')), same(controls));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
    }
    final queue = tester
        .widget<ListView>(find.byKey(const ValueKey('large-screen-queue')));
    final scroll = queue.controller!;
    scroll.jumpTo(150);
    await h.container.read(largeScreenSettingsProvider.notifier).update(
        const LargeScreenSettings(
            queue: LargeScreenQueue.list, coverFit: LargeScreenCoverFit.cover));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<ListView>(find.byKey(const ValueKey('large-screen-queue')))
            .controller,
        same(scroll));
    expect(scroll.offset, 150);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('window drag is confined to the brand and title region',
      (tester) async {
    final h = _Harness(tester);
    await h.mount();
    await h.container
        .read(largeScreenSettingsProvider.notifier)
        .update(const LargeScreenSettings(startFullScreen: false));
    await h.change(true);
    h.nativeMethods.clear();
    await tester.drag(find.byKey(const ValueKey('large-screen-window-drag')),
        const Offset(40, 20),
        kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(h.nativeMethods, contains('startDragging'));
    h.nativeMethods.clear();
    await tester.drag(find.byTooltip('收起大屏模式'), const Offset(40, 20),
        kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(h.nativeMethods, isNot(contains('startDragging')));
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
      'channel selection stays in the stage and retains content while loading',
      (tester) async {
    final h = _Harness(tester);
    await h.mount(reducedMotion: true);
    await h.change(true);
    await tester.tap(find.text('原曲频道'));
    await tester.pumpAndSettle();
    expect(h.container.read(activeStationIdProvider), 'other');
    h.station.update(const StationUiState());
    await tester.pumpAndSettle();
    expect(find.text('幽雅に咲かせ、墨染の桜'), findsOneWidget);
    expect(find.text('正在切换频道…'), findsOneWidget);
    h.station.update(StationUiState(
        initialLoading: false,
        status: StationStatus.fromJson({
          'station': {'id': 'other', 'name': '原曲频道'},
          'current': {'trackId': 'new', 'title': '新的放送', 'artist': 'ZUN'},
        })));
    await tester.pumpAndSettle();
    expect(find.text('新的放送'), findsOneWidget);
    expect(find.text('正在切换频道…'), findsNothing);
    expect(h.container.read(largeScreenProvider).active, isTrue);
    expect(h.playback.toggles, 0);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('character starts at the right and cards can be turned on',
      (tester) async {
    final h = _Harness(tester);
    await h.mount();
    await h.change(true);
    expect(tester.widget<ThmrBackground>(find.byType(ThmrBackground)).alignment,
        Alignment.bottomRight);
    final stage = find.byType(LargeScreenPlayer);
    expect(find.descendant(of: stage, matching: find.byType(BackdropFilter)),
        findsNothing);
    await h.container.read(largeScreenSettingsProvider.notifier).update(
        const LargeScreenSettings(
            cardLayout: true,
            illustrationPosition: LargeScreenIllustrationPosition.left));
    await tester.pumpAndSettle();
    expect(tester.widget<ThmrBackground>(find.byType(ThmrBackground)).alignment,
        Alignment.bottomLeft);
    expect(find.descendant(of: stage, matching: find.byType(BackdropFilter)),
        findsWidgets);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  for (final layout in LargeScreenLayout.values) {
    for (final queue in LargeScreenQueue.values) {
      testWidgets('saved $layout / $queue changes the actual display',
          (tester) async {
        final h = _Harness(tester);
        await h.mount();
        h.station.update(StationUiState(
            status: _status(queueCount: 10), initialLoading: false));
        await h.container
            .read(largeScreenSettingsProvider.notifier)
            .update(LargeScreenSettings(
              layout: layout,
              queue: queue,
              queueCount: 8,
              framing: LargeScreenFraming.fit,
              coverFit: LargeScreenCoverFit.cover,
              themeMode: ThemeMode.dark,
              showIllustration: false,
              showProgress: queue != LargeScreenQueue.hidden,
            ));
        await h.change(true);
        final cover =
            tester.getRect(find.byKey(const ValueKey('large-screen-cover')));
        final title =
            tester.getRect(find.byKey(const ValueKey('large-screen-title')));
        if (layout == LargeScreenLayout.coverLeft) {
          expect(cover.right, lessThan(title.left));
        }
        if (layout == LargeScreenLayout.coverRight) {
          expect(cover.left, greaterThan(title.right));
        }
        if (layout == LargeScreenLayout.centered) {
          expect(cover.bottom, lessThan(title.top));
        }
        final queueView = find.byKey(const ValueKey('large-screen-queue'));
        if (queue == LargeScreenQueue.hidden) {
          expect(queueView, findsNothing);
          expect(find.byType(LinearProgressIndicator), findsNothing);
        } else {
          expect(
              tester.widget<ListView>(queueView).semanticChildCount,
              queue == LargeScreenQueue.next
                  ? 1
                  : queue == LargeScreenQueue.list
                      ? 10
                      : 8);
          expect(find.byType(LinearProgressIndicator), findsOneWidget);
        }
        expect(
            Theme.of(tester
                    .element(find.byKey(const ValueKey('large-screen-title'))))
                .brightness,
            Brightness.dark);
        expect(find.byKey(const ValueKey('large-screen-centered-frame')),
            findsOneWidget);
        expect(h.playback.toggles, 0);
        expect(tester.takeException(), isNull);
      }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
    }
  }

  testWidgets('fullscreen toggles independently and collapses only on request',
      (tester) async {
    final h = _Harness(tester);
    await h.mount();
    await h.change(true);
    expect(find.text('东方音乐电台'), findsOneWidget);
    expect(find.text('Touhou Music Radio'), findsOneWidget);
    await tester.tap(find.byTooltip('退出全屏'));
    await tester.pumpAndSettle();
    expect(h.nativeFullScreen, isFalse);
    expect(find.byType(LargeScreenPlayer), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.pumpAndSettle();
    expect(h.nativeFullScreen, isTrue);
    await tester.tap(find.byTooltip('收起大屏模式'));
    await tester.pumpAndSettle();
    expect(h.nativeFullScreen, isFalse);
    expect(find.text('main control'), findsOneWidget);
    expect(h.playback.toggles, 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('native reveal follows raster and input unlocks after entrance',
      (tester) async {
    final h = _Harness(tester);
    await h.mount();
    h.frameGate = Completer<void>();
    final entering = h.controller.change(true);
    for (var i = 0; i < 30 && !h.concealed; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    expect(h.concealed, isTrue);
    expect(h.revealed, isEmpty);
    expect(h.controller.change(true), same(entering));
    final collapse = tester.widget<IconButton>(find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == '收起大屏模式'));
    expect(collapse.onPressed, isNull);
    h.frameGate!.complete();
    await tester.pumpAndSettle();
    await entering;
    expect(h.revealed.single.active, isTrue);
    expect(h.revealed.single.busy, isTrue);
    expect(h.flushed.last.busy, isFalse);
    h.frameGate = null;
    await h.change(false);
    expect(h.revealed.last.active, isFalse);
    expect(h.revealed.last.busy, isTrue);
    expect(h.flushed.last.busy, isFalse);
    expect(h.concealed, isFalse);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('opening in a window does not force fullscreen', (tester) async {
    final h = _Harness(tester);
    await h.mount();
    await h.container
        .read(largeScreenSettingsProvider.notifier)
        .update(const LargeScreenSettings(startFullScreen: false));
    await h.change(true);
    expect(h.calls, isEmpty);
    expect(find.byTooltip('进入全屏'), findsOneWidget);
    expect(h.container.read(largeScreenProvider).active, isTrue);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  for (final size in [
    const Size(1920, 1080),
    const Size(1280, 720),
    const Size(2560, 1080),
    const Size(1024, 768),
    const Size(768, 1024),
    const Size(430, 660),
    const Size(800, 400),
  ]) {
    testWidgets(
        'large display fits $size and updates metadata without playback',
        (tester) async {
      final h = _Harness(tester);
      await h.mount(size: size, scale: size.width == 800 ? 2 : 1);
      await tester.tap(find.byTooltip('大屏模式'));
      await tester.pumpAndSettle();
      expect(find.byType(LargeScreenPlayer), findsOneWidget);
      expect(find.text('幽雅に咲かせ、墨染の桜'), findsOneWidget);
      expect(find.text('少女綺想曲'), findsOneWidget);
      expect(h.playback.toggles, 0);
      expect(tester.takeException(), isNull);
      h.station.update(StationUiState(
          status: _status(title: '很长的曲名・東方音楽・' * 20),
          initialLoading: false,
          updatedAt: DateTime.now()));
      await tester.pumpAndSettle();
      expect(find.text('很长的曲名・東方音楽・' * 20), findsOneWidget);
      expect(h.playback.toggles, 0);
      expect(tester.takeException(), isNull);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }

  testWidgets('F11 enters, Escape restores size, scroll and focus',
      (tester) async {
    final h = _Harness(tester)..resizeOnTransition = true;
    await h.mount();
    h.scroll.jumpTo(800);
    h.mainFocus.requestFocus();
    await tester.pump();
    final size = tester.getSize(find.byKey(const ValueKey('retained-list')));
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.pumpAndSettle();
    expect(h.nativeFullScreen, isTrue);
    expect(find.text('main control'), findsNothing);
    expect(h.mainFocus.hasFocus, isFalse);
    expect(
        tester.getSize(
            find.byKey(const ValueKey('retained-list'), skipOffstage: false)),
        size);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('main control'), findsOneWidget);
    expect(h.nativeFullScreen, isFalse);
    expect(h.mainFocus.hasFocus, isTrue);
    expect(h.scroll.offset, 800);
    expect(h.calls, [true, false]);
    expect(h.playback.toggles, 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('fullscreen transition coalesces input and rolls back failure',
      (tester) async {
    final h = _Harness(tester)..enterGate = Completer<void>();
    await h.mount();
    final entering = h.controller.change(true);
    expect(h.controller.change(true), same(entering));
    await tester.pump();
    expect(h.container.read(largeScreenProvider).busy, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.pump();
    h.enterGate!.complete();
    await tester.pumpAndSettle();
    await entering;
    expect(h.calls, [true, false]);
    expect(h.container.read(largeScreenProvider).active, isTrue);
    expect(h.container.read(largeScreenProvider).fullScreen, isFalse);
    await h.change(false);
    h.failEnter = true;
    await h.change(true);
    expect(h.container.read(largeScreenProvider).active, isFalse);
    expect(h.container.read(largeScreenProvider).busy, isFalse);
    expect(find.text('无法切换显示模式，请重试。'), findsOneWidget);
    expect(h.nativeFullScreen, isFalse);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('native fullscreen exits and existing fullscreen is preserved',
      (tester) async {
    final h = _Harness(tester);
    await h.mount();
    h.nativeFullScreen = true;
    await h.change(true);
    await h.change(false);
    expect(h.calls, isEmpty);
    expect(h.nativeFullScreen, isTrue);
    await h.change(true);
    final listener = tester.state(find.byType(LargeScreenSurface)) as dynamic;
    h.nativeFullScreen = false;
    listener.onWindowLeaveFullScreen();
    await tester.pumpAndSettle();
    expect(find.byType(LargeScreenPlayer), findsOneWidget);
    expect(h.container.read(largeScreenProvider).fullScreen, isFalse);
    expect(find.text('main control'), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('failed exit leaves controls available for a successful retry',
      (tester) async {
    final h = _Harness(tester);
    await h.mount();
    await h.change(true);
    h.failExit = true;
    await h.change(false);
    expect(h.container.read(largeScreenProvider).active, isTrue);
    expect(h.container.read(largeScreenProvider).busy, isFalse);
    expect(find.text('无法收起大屏模式，请重试。'), findsOneWidget);
    h.failExit = false;
    await tester.tap(find.byTooltip('收起大屏模式'));
    await tester.pumpAndSettle();
    expect(h.container.read(largeScreenProvider).active, isFalse);
    expect(h.nativeFullScreen, isFalse);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('page navigation exits presentation before changing tabs',
      (tester) async {
    final h = _Harness(tester);
    await h.mount();
    await h.change(true);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit3);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(h.container.read(appTabProvider), 2);
    expect(h.nativeFullScreen, isFalse);
    expect(find.text('main control'), findsOneWidget);
    expect(h.playback.toggles, 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('mode shortcuts exit mini before large and large before mini',
      (tester) async {
    final h = _Harness(tester);
    await h.mount();
    h.container.read(miniPlayerProvider.notifier).state = true;
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.pumpAndSettle();
    expect(h.container.read(miniPlayerProvider), isFalse);
    expect(h.nativeFullScreen, isTrue);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyM);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(h.nativeFullScreen, isFalse);
    expect(h.container.read(largeScreenProvider).active, isFalse);
    expect(h.container.read(miniPlayerProvider), isTrue);
    expect(h.playback.toggles, 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('idle controls hide, pointer and keyboard reveal them',
      (tester) async {
    final h = _Harness(tester);
    await h.mount();
    await h.change(true);
    final controls = find.byKey(const ValueKey('large-screen-controls'));
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(controls).opacity, 0);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(200, 200));
    await mouse.moveTo(const Offset(201, 200));
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(controls).opacity, 1);
    await tester.tap(find.byTooltip('暂停播放'));
    await tester.pump();
    expect(h.playback.toggles, 1);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(tester.widget<AnimatedOpacity>(controls).opacity, 1);
    await mouse.removePointer();
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('empty and failed station data have a usable exit',
      (tester) async {
    final h = _Harness(tester);
    await h.mount();
    h.station.update(const StationUiState());
    await h.change(true);
    expect(find.text('正在获取放送信息…'), findsOneWidget);
    h.station
        .update(const StationUiState(error: 'offline', initialLoading: false));
    await tester.pump();
    expect(find.text('暂时无法获取放送信息，正在重试'), findsOneWidget);
    expect(
        tester
            .widget<LinearProgressIndicator>(
                find.byType(LinearProgressIndicator))
            .value,
        0);
    await tester.tap(find.byTooltip('收起大屏模式'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('大屏模式'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));

  testWidgets('mini presentation cannot race large screen', (tester) async {
    final h = _Harness(tester);
    await h.mount();
    h.container.read(miniPlayerProvider.notifier).state = true;
    await h.change(true);
    expect(h.calls, isEmpty);
    expect(h.container.read(largeScreenProvider).active, isFalse);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('mobile has no desktop entry or fullscreen shortcut',
      (tester) async {
    final h = _Harness(tester);
    await h.mount();
    expect(find.byTooltip('大屏模式'), findsNothing);
    await tester.sendKeyEvent(LogicalKeyboardKey.f11);
    await tester.pumpAndSettle();
    await h.change(true);
    expect(h.calls, isEmpty);
    expect(h.container.read(appTabProvider), 0);
    expect(find.byType(LargeScreenPlayer), findsNothing);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}
