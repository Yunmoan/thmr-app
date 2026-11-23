import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';
import 'package:thmr_app/core/input/app_input.dart';
import 'package:thmr_app/core/input/app_commands.dart';
import 'package:thmr_app/core/models/models.dart';
import 'package:thmr_app/core/platform/window_presentation.dart';
import 'package:thmr_app/core/theme/thmr_motion.dart';
import 'package:thmr_app/core/player/playback_controller.dart';
import 'package:thmr_app/core/player/spectrum.dart';
import 'package:thmr_app/core/state/station_provider.dart';
import 'package:thmr_app/core/state/large_screen_settings.dart';
import 'package:thmr_app/core/state/channel_provider.dart';
import 'package:thmr_app/features/listen/widgets/channel_switcher.dart';
import 'package:thmr_app/shared/widgets/thmr_background.dart';
import 'package:thmr_app/shared/widgets/track_cover.dart';
import 'package:thmr_app/features/large_screen/large_screen_button.dart';
import 'package:thmr_app/features/large_screen/large_screen_controller.dart';
import 'package:thmr_app/features/large_screen/large_screen_music_visual.dart';
import 'package:thmr_app/features/large_screen/large_screen_player.dart';
import 'package:thmr_app/features/large_screen/large_screen_surface.dart';
import 'package:thmr_app/features/large_screen/large_screen_settings_panel.dart';
import 'package:thmr_app/features/large_screen/large_screen_preview.dart';
import 'package:thmr_app/features/large_screen/large_screen_content.dart';
import 'package:thmr_app/features/mini/mini_player.dart';
import 'package:thmr_app/features/mini/desktop_player_surface.dart';
import 'package:thmr_app/core/theme/thmr_focus_ring.dart';

StationStatus _status(
        {String title = '幽雅に咲かせ、墨染の桜',
        int queueCount = 1,
        String coverUrl = ''}) =>
    StationStatus.fromJson({
      'station': {'id': 'touhou', 'name': '东方音乐电台'},
      'current': {
        'trackId': 'one',
        'title': title,
        'artist': '上海アリス幻樂団',
        'positionSec': 75,
        'durationSec': 240,
        'coverUrl': coverUrl,
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
  _Harness(this.tester, {this.spectrum});
  final WidgetTester tester;
  final SpectrumSource? spectrum;
  final navigator = GlobalKey<NavigatorState>();
  final scroll = ScrollController();
  final mainFocus = FocusNode();
  final surfaceRevision = ValueNotifier(0);
  final station = _Station();
  final playback = _Playback();
  final calls = <bool>[];
  final nativeMethods = <String>[];
  final orientations = <List<dynamic>>[];
  final keepScreenOnCalls = <bool>[];
  late final container = ProviderContainer(overrides: [
    stationProvider.overrideWith((ref) => station),
    playbackProvider.overrideWith((ref) => playback),
    largeScreenSpectrumProvider.overrideWithValue(spectrum),
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
  bool workAreaFollowsFullscreen = false;
  Completer<void>? enterGate;
  Completer<void>? frameGate;
  bool concealed = false;
  VoidCallback? onConceal;
  final revealed = <LargeScreenState>[];
  final revealedOpacities = <double>[];
  final flushed = <LargeScreenState>[];

  Future<void> mount(
      {Size size = const Size(1280, 720),
      double scale = 1,
      bool desktopRoot = false,
      bool reducedMotion = false,
      bool isIPad = false,
      FakeViewPadding padding = const FakeViewPadding(),
      bool startFullScreen = true}) async {
    // The stage tests exercise native fullscreen paths; opt in explicitly now
    // that the product default is windowed.
    SharedPreferences.setMockInitialValues({
      'largeScreen': '{"startFullScreen":$startFullScreen}',
    });
    tester.view.devicePixelRatio = 1;
    tester.view.display.size = size;
    tester.view.physicalSize = size;
    tester.view.padding = padding;
    tester.view.viewPadding = padding;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemChrome.setPreferredOrientations') {
        orientations.add(List<dynamic>.from(call.arguments as List));
      }
      return null;
    });
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('thmr/mobile_presentation'), (call) async {
      if (call.method == 'isIPad') return isIPad;
      if (call.method == 'setKeepScreenOn') {
        keepScreenOnCalls.add(call.arguments as bool);
      }
      return null;
    });
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
        if (workAreaFollowsFullscreen && !nativeFullScreen) {
          return {'left': 0.0, 'top': 0.0, 'right': 0.0, 'bottom': 0.0};
        }
        return {
          'left': workAreaInsets.left,
          'top': workAreaInsets.top,
          'right': workAreaInsets.right,
          'bottom': workAreaInsets.bottom
        };
      }
      if (call.method == 'conceal') {
        onConceal?.call();
        concealed = true;
      }
      if (call.method == 'waitForFrame') await frameGate?.future;
      if (call.method == 'flushFrame') {
        flushed.add(container.read(largeScreenProvider));
      }
      if (call.method == 'reveal') {
        concealed = false;
        revealed.add(container.read(largeScreenProvider));
        final key = container.read(largeScreenProvider).active
            ? 'large-mode-transition'
            : 'standard-mode-transition';
        final fades = find
            .descendant(
                of: find.byKey(ValueKey(key), skipOffstage: false),
                matching: find.byType(FadeTransition, skipOffstage: false),
                skipOffstage: false)
            .evaluate();
        if (fades.isNotEmpty) {
          revealedOpacities
              .add((fades.first.widget as FadeTransition).opacity.value);
        }
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
      tester.view.display.resetSize();
      tester.view.resetPadding();
      tester.view.resetViewPadding();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('window_manager'), null);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('thmr/window_presentation'), null);
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('thmr/mobile_presentation'), null);
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

class _StageSpectrum implements SpectrumSource {
  int starts = 0, stops = 0, polls = 0;

  @override
  void start() => starts++;

  @override
  void stop() => stops++;

  @override
  Float32List poll(int bands) {
    polls++;
    return Float32List(bands)..fillRange(0, bands, .65);
  }
}

void main() {
  testWidgets('stage messages belong only to the visible scaffold',
      (tester) async {
    final h = _Harness(tester);
    await h.mount();
    await h.change(true);
    final context = tester.element(find.byType(LargeScreenPlayer));
    ScaffoldMessenger.of(context).showThmrSnackBar(
        context, const SnackBar(content: Text('stage message')));
    await tester.pump();
    await tester.pump(ThmrMotion.duration);
    expect(find.byType(SnackBar, skipOffstage: false), findsOneWidget,
        reason: 'The retained ordinary scaffold must not get a duplicate '
            'message and Hero while it is offstage.');
    final route = h.navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('covered'))));
    await tester.pumpAndSettle();
    h.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await route;
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('fullscreen resizing keeps the initialized stage opaque',
      (tester) async {
    final h = _Harness(tester);
    await h.mount();
    await h.change(true);
    final hidden = <LargeScreenState>[];
    final subscription = h.container.listen(largeScreenProvider, (_, next) {
      if (next.active && !next.contentVisible) hidden.add(next);
    });
    addTearDown(subscription.close);
    final toggling = h.controller.toggleFullScreen();
    await tester.pumpAndSettle();
    await toggling;
    expect(hidden, isEmpty,
        reason: 'Fullscreen changes resize an existing stage without fading '
            'its initialized content back to transparent.');
    expect(h.container.read(largeScreenProvider).active, isTrue);
    expect(h.container.read(largeScreenProvider).fullScreen, isFalse);
  },
      variant: const TargetPlatformVariant({
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      }));

  testWidgets(
      'mode changes remove open tooltip overlays before concealing their anchor',
      (tester) async {
    final h = _Harness(tester);
    await h.mount();
    tester
        .state<RawTooltipState>(find.byTooltip('大屏幕模式'))
        .ensureTooltipVisible();
    await tester.pumpAndSettle();
    expect(find.text('大屏幕模式'), findsOneWidget);
    var tooltipWasOpen = false;
    h.onConceal =
        () => tooltipWasOpen = find.text('大屏幕模式').evaluate().isNotEmpty;
    await h.change(true);
    expect(tooltipWasOpen, isFalse,
        reason: 'The tooltip traversal parent must be detached before its '
            'retained page is hidden from the semantics tree.');
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
      'native frame fences request a frame while lifecycle scheduling is paused',
      (tester) async {
    final h = _Harness(tester);
    await h.mount();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    expect(tester.binding.framesEnabled, isFalse);
    final pending = WindowPresentation().flushFrame();
    final scheduled = tester.binding.hasScheduledFrame;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    await pending;
    expect(scheduled, isTrue,
        reason: 'A native transition must submit its frame before waiting for '
            'the window to become visible again.');
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
      'settings preview follows edits without owning window or playback',
      (tester) async {
    final h = _Harness(tester);
    await h.mount(size: const Size(1440, 900), desktopRoot: true);
    Future<void> presentation(bool _) async {}
    h.controller.animatePresentation = presentation;
    final before = [...h.nativeMethods];
    unawaited(h.navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const LargeScreenSettingsPage())));
    await tester.pumpAndSettle();
    expect(find.byType(LargeScreenPreview), findsOneWidget);
    expect(h.controller.animatePresentation, presentation);
    final preview =
        find.byWidgetPredicate((w) => w is LargeScreenPlayer && w.preview);
    expect(preview, findsOneWidget);
    expect(find.descendant(of: preview, matching: find.byType(ChannelSwitcher)),
        findsNothing);
    await tester.tap(find.text('封面在右'));
    await tester.pumpAndSettle();
    expect(
        tester
            .widget<LargeScreenContent>(find.descendant(
                of: preview, matching: find.byType(LargeScreenContent)))
            .settings
            .layout,
        LargeScreenLayout.coverRight);
    await tester.tap(find.widgetWithText(Tab, '小组件'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加活动组件'));
    await tester.pumpAndSettle();
    expect(h.container.read(largeScreenSettingsProvider).widgets.length, 3);
    final items = h.container.read(largeScreenSettingsProvider).widgets;
    await tester.tap(find.byKey(ValueKey('select-${items.last.id}')));
    await tester.pumpAndSettle();
    final input = find.byKey(ValueKey('component-text-${items.last.id}'));
    await tester.ensureVisible(input);
    await tester.enterText(input, '河东 THO · 东方音乐电台');
    await tester.pump();
    final editable = tester.state<EditableTextState>(
        find.descendant(of: input, matching: find.byType(EditableText)));
    expect(editable.widget.focusNode.hasFocus, isTrue);
    expect(find.descendant(of: preview, matching: find.text('河东 THO · 东方音乐电台')),
        findsOneWidget);
    expect(h.playback.toggles, 0);
    expect(h.nativeMethods, before);
    expect(h.controller.animatePresentation, presentation);
    await tester.tap(find.byTooltip('放大预览'));
    await tester.pumpAndSettle();
    expect(find.byType(LargeScreenPreview), findsNWidgets(2));
    await tester.tap(find.byTooltip('关闭预览'));
    await tester.pumpAndSettle();
    expect(h.controller.animatePresentation, presentation);
    h.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    expect(h.controller.animatePresentation, presentation);
    expect(tester.takeException(), isNull);
  });

  for (final size in [const Size(280, 800), const Size(1440, 900)]) {
    testWidgets('preview aspect ratios and modal fit $size', (tester) async {
      final h = _Harness(tester);
      await h.mount(size: size, scale: 2);
      unawaited(h.navigator.currentState!.push(MaterialPageRoute<void>(
          builder: (_) => const LargeScreenSettingsPage())));
      await tester.pumpAndSettle();
      if (size.width < 1100) {
        await tester.tap(find.text('预览'));
        await tester.pumpAndSettle();
      }
      for (final (label, ratio) in [
        ('16:10', 16 / 10),
        ('4:3', 4 / 3),
        ('9:16', 9 / 16),
        ('手机横屏', 844 / 390),
        ('手机竖屏', 390 / 844),
        ('16:9', 16 / 9),
      ]) {
        await tester.tap(find.byTooltip('预览比例'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
        final frame = tester
            .getSize(find.byKey(const ValueKey('large-screen-preview-frame')));
        expect(frame.width / frame.height, closeTo(ratio, .01));
        expect(tester.takeException(), isNull);
      }
    });
  }

  testWidgets('spectrum uses live audio in the settings and on the stage',
      (tester) async {
    final source = _StageSpectrum();
    final h = _Harness(tester, spectrum: source)..resizeOnTransition = true;
    await h.mount(size: const Size(1440, 900), desktopRoot: true);
    await h.playback.toggle(null);
    unawaited(h.navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const LargeScreenSettingsPage())));
    await tester.pumpAndSettle();
    final style = find.text('镜像频谱');
    await tester.ensureVisible(style);
    await tester.tap(style);
    await tester.pumpAndSettle();
    final visual = find.descendant(
        of: find.byType(LargeScreenPreview),
        matching: find.byType(LargeScreenMusicVisual));
    final demo = tester.widget<LargeScreenMusicVisual>(visual);
    expect(demo.effect, LargeScreenMusicEffect.spectrum);
    expect(demo.demo, isTrue);
    expect(demo.source, isNull);
    expect(source.starts, 0);
    expect(find.text('动效预览使用示例节奏'), findsOneWidget);

    await tester.tap(find.text('重播动效'));
    await tester.pump();
    expect(tester.widget<LargeScreenMusicVisual>(visual).key, isNot(demo.key));
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpAndSettle();
    expect(source.starts, 0);

    await h.playback.toggle(null);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    final live = tester.widget<LargeScreenMusicVisual>(visual);
    expect(live.demo, isFalse);
    expect(live.source, same(source));
    expect(source.starts, 1);
    expect(source.polls, greaterThan(0));
    expect(find.text('频谱预览使用当前播放的音频'), findsOneWidget);
    expect(find.text('重播动效'), findsNothing);

    await h.playback.toggle(null);
    await tester.pumpAndSettle();
    expect(source.stops, 1);
    expect(tester.widget<LargeScreenMusicVisual>(visual).demo, isTrue);
    h.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await h.change(true);
    final stageVisual = find.descendant(
        of: find.byType(LargeScreenPlayer),
        matching: find.byType(LargeScreenMusicVisual));
    expect(tester.widget<LargeScreenMusicVisual>(stageVisual).demo, isFalse);
    expect(source.starts, 1, reason: 'the radio is paused');

    await h.playback.toggle(null);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    expect(source.starts, 2);
    final collapse = find.byTooltip('收起大屏幕模式').hitTestable();
    expect(collapse, findsOneWidget);
    await tester.tap(collapse, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(stageVisual, findsNothing);
    expect(find.text('main control').hitTestable(), findsOneWidget);
    expect(source.stops, 2);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
      'portrait covers center in contain mode and crop to fill in cover mode',
      (tester) async {
    final h = _Harness(tester);
    await h.mount();
    await h.container.read(largeScreenSettingsProvider.notifier).update(
        const LargeScreenSettings(
            layout: LargeScreenLayout.coverLeft,
            queue: LargeScreenQueue.hidden));
    await h.change(true);
    final cover = find.byKey(const ValueKey('large-screen-cover'));
    final size = tester.getSize(cover);
    const url = 'https://cover.test/portrait.png';
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(
        const Rect.fromLTWH(0, 0, 20, 40), Paint()..color = Colors.red);
    final picture = recorder.endRecording();
    final portrait = await tester.runAsync(() => picture.toImage(20, 40));
    picture.dispose();
    final key =
        await TrackCover.providerFor(url, cacheWidth: size.width.round())
            .obtainKey(ImageConfiguration.empty);
    PaintingBinding.instance.imageCache.putIfAbsent(
        key,
        () => OneFrameImageStreamCompleter(
            Future.value(ImageInfo(image: portrait!))));
    h.station.update(
        StationUiState(status: _status(coverUrl: url), initialLoading: false));
    await tester.pumpAndSettle();
    Future<int> edgeAlpha() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(find
          .descendant(of: cover, matching: find.byType(RepaintBoundary))
          .first);
      final frame = await boundary.toImage();
      final bytes = await tester
          .runAsync(() => frame.toByteData(format: ui.ImageByteFormat.rawRgba));
      final alpha =
          bytes!.getUint8(((frame.height ~/ 2) * frame.width + 1) * 4 + 3);
      frame.dispose();
      return alpha;
    }

    expect(await edgeAlpha(), 0,
        reason: 'Contain keeps transparent, centered side margins.');
    await h.container.read(largeScreenSettingsProvider.notifier).update(
        const LargeScreenSettings(
            layout: LargeScreenLayout.coverLeft,
            queue: LargeScreenQueue.hidden,
            coverFit: LargeScreenCoverFit.cover));
    await tester.pumpAndSettle();
    expect(await edgeAlpha(), 255,
        reason:
            'Cover fills the entire square instead of retaining side bars.');
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
      'native resize without window events refreshes the work area before reveal',
      (tester) async {
    final h = _Harness(tester)
      ..workAreaFollowsFullscreen = true
      ..workAreaInsets = const EdgeInsets.only(bottom: 54);
    await h.mount(size: const Size(1920, 1080), desktopRoot: true);
    await h.change(true);
    final controls =
        tester.getRect(find.byKey(const ValueKey('large-screen-controls')));
    expect(controls.bottom, lessThanOrEqualTo(1080 - 54));
    expect(
        tester
            .widget<LargeScreenPlayer>(find.byType(LargeScreenPlayer))
            .safeInsets
            .bottom,
        54);
    await h.change(false);
    await h.change(true);
    expect(
        tester
            .widget<LargeScreenPlayer>(find.byType(LargeScreenPlayer))
            .safeInsets
            .bottom,
        54);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

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
      expect(find.byTooltip('收起大屏幕模式').hitTestable(), findsOneWidget);
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
    expect(find.byTooltip('收起大屏幕模式').hitTestable(), findsOneWidget);
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
      expect(find.byTooltip('收起大屏幕模式').hitTestable(), findsOneWidget);
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
    expect(find.byTooltip('收起大屏幕模式').hitTestable(), findsOneWidget);
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

  testWidgets('Windows collapse hands off between two fully visible pages',
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
    double? stageAtConceal;
    h.onConceal = () => stageAtConceal = (fade('large-mode-transition')
            .evaluate()
            .single
            .widget as FadeTransition)
        .opacity
        .value;
    await h.change(false);
    expect(stageAtConceal, 1,
        reason: 'The last exposed stage frame still has its content.');
    expect(h.revealedOpacities.last, 1,
        reason: 'The first exposed normal frame already has its content.');
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
    expect(find.byKey(const ValueKey('large-screen-window-drag-strip')),
        findsOneWidget);
    h.nativeMethods.clear();
    await tester.drag(find.byKey(const ValueKey('large-screen-window-drag')),
        const Offset(40, 20),
        kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(h.nativeMethods, contains('startDragging'));
    h.nativeMethods.clear();
    await tester.drag(
        find.byKey(const ValueKey('large-screen-window-drag-strip')),
        const Offset(40, 20),
        kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(h.nativeMethods, contains('startDragging'));
    h.nativeMethods.clear();
    await tester.drag(find.byTooltip('收起大屏幕模式'), const Offset(40, 20),
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

  testWidgets(
      'fluid motion keeps the illustration visible and tints it with the cover',
      (tester) async {
    final h = _Harness(tester);
    await h.mount();
    const url = 'https://cover.test/fluid.png';
    final cover = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(
          const Rect.fromLTWH(0, 0, 16, 16), Paint()..color = Colors.blue);
      final picture = recorder.endRecording();
      final image = await picture.toImage(16, 16);
      picture.dispose();
      return image;
    });
    const provider = ResizeImage(NetworkImage(url),
        width: 48, height: 48, policy: ResizeImagePolicy.fit);
    final key = await tester
        .runAsync(() => provider.obtainKey(ImageConfiguration.empty));
    PaintingBinding.instance.imageCache.putIfAbsent(
        key!,
        () => OneFrameImageStreamCompleter(
            Future.value(ImageInfo(image: cover!))));
    await h.container.read(largeScreenSettingsProvider.notifier).update(
        const LargeScreenSettings(
            musicEffect: LargeScreenMusicEffect.fluid,
            showIllustration: true,
            illustrationOpacity: .65));
    h.station.update(
        StationUiState(status: _status(coverUrl: url), initialLoading: false));
    // A playing fluid stage animates continuously, so pause for a settled frame.
    await h.playback.toggle(null);
    await h.change(true);
    await tester.pumpAndSettle();
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await tester.pumpAndSettle();
    final background = tester.widget<ThmrBackground>(find.descendant(
        of: find.byType(LargeScreenPlayer),
        matching: find.byType(ThmrBackground)));
    expect(background.underlayAboveWash, isTrue);
    final opacity = tester.widget<Opacity>(find.descendant(
        of: find.byKey(const ValueKey('background-illustration')),
        matching: find.byType(Opacity)));
    expect(opacity.opacity, closeTo(.65 * .55, .001),
        reason: 'fluid motion keeps the portrait visible but subdued');
    final tint = background.illustrationTint;
    expect(tint, isNotNull, reason: 'the cover pigments wash the illustration');
    expect(tint!.a, closeTo(.38, .01));
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
    await tester.tap(find.byTooltip('收起大屏幕模式'));
    await tester.pumpAndSettle();
    expect(h.nativeFullScreen, isFalse);
    expect(find.text('main control'), findsOneWidget);
    expect(h.playback.toggles, 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
      'completed fullscreen exits restore painted content after a lost callback',
      (tester) async {
    final h = _Harness(tester);
    await h.mount();
    await h.change(true);
    // A replaced native surface may finish the request without driving the
    // widget's original animation callback.
    h.controller.animatePresentation = (_) async {};
    await tester.tap(find.byTooltip('退出全屏'));
    await tester.pumpAndSettle();
    expect(h.container.read(largeScreenProvider).fullScreen, isFalse);
    final stageFade = find
        .descendant(
            of: find.byKey(const ValueKey('large-mode-transition')),
            matching: find.byType(FadeTransition))
        .first;
    expect(tester.widget<FadeTransition>(stageFade).opacity.value, 1);
    h.controller.animateStandard = (_) async {};
    await h.change(false);
    final standardFade = find
        .descendant(
            of: find.byKey(const ValueKey('standard-mode-transition')),
            matching: find.byType(FadeTransition))
        .first;
    expect(tester.widget<FadeTransition>(standardFade).opacity.value, 1);
    expect(find.text('main control').hitTestable(), findsOneWidget);
    expect(tester.takeException(), isNull);
  },
      variant: const TargetPlatformVariant({
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      }));

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
    final collapse = tester.widget<IconButton>(find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == '收起大屏幕模式'));
    expect(collapse.onPressed, isNull);
    h.frameGate!.complete();
    await tester.pumpAndSettle();
    await entering;
    expect(h.revealed.single.active, isTrue);
    expect(h.revealed.single.busy, isTrue);
    expect(h.revealed.single.contentVisible, isTrue);
    expect(h.flushed.last.busy, isFalse);
    h.frameGate = null;
    await h.change(false);
    expect(h.revealed.last.active, isFalse);
    expect(h.revealed.last.busy, isTrue);
    expect(h.flushed.last.busy, isFalse);
    expect(h.concealed, isFalse);
    expect(h.revealedOpacities, hasLength(2));
    expect(h.revealedOpacities, everyElement(greaterThan(0)),
        reason: 'The incoming content must be visible at either reveal.');
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
      await tester.tap(find.byTooltip('大屏幕模式'));
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
    expect(find.text('无法收起大屏幕模式，请重试。'), findsOneWidget);
    h.failExit = false;
    await tester.tap(find.byTooltip('收起大屏幕模式'));
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
    await tester.tap(find.byTooltip('收起大屏幕模式'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('大屏幕模式'), findsOneWidget);
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

  testWidgets('phones enter in portrait and reflow in landscape without a lock',
      (tester) async {
    final h = _Harness(tester);
    const portrait = Size(390, 844);
    const landscape = Size(844, 390);
    await h.mount(
        size: portrait, padding: const FakeViewPadding(top: 54, bottom: 34));
    await h.container
        .read(largeScreenSettingsProvider.notifier)
        .update(const LargeScreenSettings(
          musicEffect: LargeScreenMusicEffect.off,
          autoHideControls: false,
        ));
    h.scroll.jumpTo(750);
    await tester.tap(find.byTooltip('大屏幕模式'));
    await tester.pumpAndSettle();
    final cover = find.byKey(const ValueKey('large-screen-cover'));
    final title = find.byKey(const ValueKey('large-screen-title'));
    final controls = find.byKey(const ValueKey('large-screen-controls-slot'));
    final exit = find.byTooltip('收起大屏幕模式');
    expect(h.container.read(largeScreenProvider).active, isTrue);
    expect(tester.view.physicalSize, portrait);
    expect(
        tester.getBottomLeft(cover).dy, lessThan(tester.getTopLeft(title).dy));
    expect(tester.getTopLeft(exit).dy, greaterThanOrEqualTo(54));
    expect(tester.getBottomLeft(controls).dy, lessThanOrEqualTo(810));
    expect(find.byTooltip('进入全屏'), findsNothing);
    expect(find.byType(DragToMoveArea), findsNothing);
    expect(h.nativeMethods, isEmpty);
    expect(h.keepScreenOnCalls, isEmpty);

    const landscapePadding = FakeViewPadding(left: 47, right: 47, bottom: 21);
    tester.view.display.size = landscape;
    tester.view.physicalSize = landscape;
    tester.view.padding = landscapePadding;
    tester.view.viewPadding = landscapePadding;
    await tester.pumpAndSettle();
    expect(tester.getTopRight(cover).dx, lessThan(tester.getTopLeft(title).dx));
    expect(tester.getTopLeft(cover).dx, greaterThanOrEqualTo(47));
    expect(tester.getBottomLeft(controls).dy, lessThanOrEqualTo(369));
    final scrollArea = find.byKey(const ValueKey('large-screen-phone-scroll'));
    final queue = find.byKey(const ValueKey('large-screen-queue'));
    expect(tester.getBottomLeft(queue).dy,
        lessThanOrEqualTo(tester.getBottomLeft(scrollArea).dy));
    final art = find.descendant(
      of: find.byKey(const ValueKey('background-illustration')),
      matching: find.byType(FractionallySizedBox),
    );
    expect(tester.getTopRight(exit).dx, lessThan(tester.getTopLeft(art).dx));
    expect(tester.getTopRight(find.byType(LinearProgressIndicator)).dx,
        lessThan(tester.getTopLeft(art).dx));

    await h.navigator.currentState!.maybePop();
    await tester.pumpAndSettle();
    expect(h.container.read(largeScreenProvider).active, isFalse);
    expect(h.orientations, isEmpty);
    expect(tester.view.physicalSize, landscape);
    expect(h.scroll.offset, 750);
    expect(tester.takeException(), isNull);
  },
      variant: const TargetPlatformVariant(
          {TargetPlatform.android, TargetPlatform.iOS}));

  testWidgets('short phone landscape scrolls its queue with controls pinned',
      (tester) async {
    final h = _Harness(tester);
    await h.mount(size: const Size(568, 320), scale: 2);
    h.station.update(StationUiState(
      status: _status(
        title: '幽雅に咲かせ、墨染の桜 ${List.filled(6, 'Long track title').join(' ')}',
        queueCount: 40,
      ),
      initialLoading: false,
    ));
    await h.container
        .read(largeScreenSettingsProvider.notifier)
        .update(const LargeScreenSettings(
          musicEffect: LargeScreenMusicEffect.off,
          queue: LargeScreenQueue.list,
          autoHideControls: false,
          cardLayout: true,
          layout: LargeScreenLayout.coverRight,
        ));
    await h.change(true);
    final cover = find.byKey(const ValueKey('large-screen-cover'));
    final title = find.byKey(const ValueKey('large-screen-title'));
    expect(tester.getTopRight(title).dx, lessThan(tester.getTopLeft(cover).dx));
    final controls = find.byKey(const ValueKey('large-screen-controls-slot'));
    final before = tester.getRect(controls);
    final endOfQueue = find.text('接下来 39');
    expect(endOfQueue, findsNothing);
    await tester.scrollUntilVisible(
      endOfQueue,
      160,
      scrollable: find.descendant(
        of: find.byKey(const ValueKey('large-screen-phone-scroll')),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.pumpAndSettle();
    expect(endOfQueue.hitTestable(), findsOneWidget);
    expect(tester.getRect(controls), before);
    await tester.tap(find.byTooltip('暂停播放'));
    await tester.pumpAndSettle();
    expect(h.playback.toggles, 1);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('iPad keeps its stage layout even in a phone-sized split window',
      (tester) async {
    final h = _Harness(tester);
    await h.mount(size: const Size(390, 700), isIPad: true);
    await h.container.read(largeScreenSettingsProvider.notifier).update(
        const LargeScreenSettings(musicEffect: LargeScreenMusicEffect.off));
    await h.change(true);
    final tabletFrame =
        find.byKey(const ValueKey('large-screen-centered-frame'));
    expect(tabletFrame, findsOneWidget);
    expect(
        find.byKey(const ValueKey('large-screen-phone-scroll')), findsNothing);
    tester.view.physicalSize = const Size(1180, 820);
    await tester.pumpAndSettle();
    final cover = find.byKey(const ValueKey('large-screen-cover'));
    final title = find.byKey(const ValueKey('large-screen-title'));
    expect(tester.getTopRight(cover).dx, lessThan(tester.getTopLeft(title).dx));
    expect(tabletFrame, findsOneWidget);
    expect(h.orientations, isEmpty);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets(
      'mobile keeps the screen awake only while opted in and foreground',
      (tester) async {
    final h = _Harness(tester);
    await h.mount();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await h.container
        .read(largeScreenSettingsProvider.notifier)
        .update(const LargeScreenSettings(keepScreenOn: true));
    await h.change(true);
    expect(h.keepScreenOnCalls.last, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(h.keepScreenOnCalls.last, isFalse);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(h.keepScreenOnCalls.last, isTrue);
    await h.container
        .read(largeScreenSettingsProvider.notifier)
        .update(const LargeScreenSettings(keepScreenOn: false));
    await tester.pump();
    expect(h.keepScreenOnCalls.last, isFalse);
    await h.container
        .read(largeScreenSettingsProvider.notifier)
        .update(const LargeScreenSettings(keepScreenOn: true));
    await tester.pump();
    expect(h.keepScreenOnCalls.last, isTrue);
    await h.change(false);
    expect(h.keepScreenOnCalls.last, isFalse);
    expect(tester.takeException(), isNull);
  },
      variant: const TargetPlatformVariant(
          {TargetPlatform.android, TargetPlatform.iOS}));

  testWidgets('entering from a covered route still reveals the stage',
      (tester) async {
    final h = _Harness(tester);
    await h.mount(desktopRoot: true);
    h.navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('settings page'))));
    await tester.pumpAndSettle();
    final entering = h.controller.change(true);
    // Tickers under an opaque route are muted; drive frames instead of
    // waiting for the entrance to settle.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    h.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    await entering;
    final fade = find
        .descendant(
            of: find.byKey(const ValueKey('large-mode-transition')),
            matching: find.byType(FadeTransition))
        .first;
    expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
    expect(h.container.read(largeScreenProvider).busy, isFalse);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('pushed settings page exposes an adjustable effect intensity',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final h = _Harness(tester);
    await h.mount(size: const Size(1440, 900), desktopRoot: true);
    unawaited(h.navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const LargeScreenSettingsPage())));
    await tester.pumpAndSettle();
    final intensity = find.semantics.byPredicate((node) =>
        node.label == '动效强度' &&
        node.getSemanticsData().hasAction(ui.SemanticsAction.increase));
    expect(intensity.evaluate().single.value, '60%');
    tester.semantics.increase(intensity);
    await tester.pumpAndSettle();
    expect(intensity.evaluate().single.value, '70%');
    semantics.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('collapsing completes even when the stage ticker is muted',
      (tester) async {
    final h = _Harness(tester);
    await h.mount(desktopRoot: true);
    h.navigator.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('settings page'))));
    await tester.pumpAndSettle();
    final entering = h.controller.change(true);
    // The opaque route mutes the stage ticker. The entrance watchdog must land
    // the stage at full opacity and release busy anyway.
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await entering;
    expect(h.container.read(largeScreenProvider).busy, isFalse);
    expect(h.container.read(largeScreenProvider).contentVisible, isTrue);

    final exiting = h.controller.change(false);
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await exiting;
    expect(h.container.read(largeScreenProvider).active, isFalse);
    expect(h.container.read(largeScreenProvider).busy, isFalse);

    h.navigator.currentState!.pop();
    await tester.pumpAndSettle();
    final fade = find
        .descendant(
            of: find.byKey(const ValueKey('standard-mode-transition')),
            matching: find.byType(FadeTransition))
        .first;
    expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
    expect(find.byType(LargeScreenPlayer), findsNothing);
    expect(find.text('main control').hitTestable(), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
