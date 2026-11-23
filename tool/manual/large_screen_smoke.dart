// Real HWND, fullscreen, raster-fence and retained-page checks.
// Run instructions are in docs/development/verification.md.
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'package:thmr_app/core/models/models.dart';
import 'package:thmr_app/core/platform/desktop_window.dart';
import 'package:thmr_app/core/platform/window_presentation.dart';
import 'package:thmr_app/core/player/playback_controller.dart';
import 'package:thmr_app/core/state/large_screen_settings.dart';
import 'package:thmr_app/core/state/channel_provider.dart';
import 'package:thmr_app/core/state/station_provider.dart';
import 'package:thmr_app/core/theme/thmr_colors.dart';
import 'package:thmr_app/core/theme/thmr_motion.dart';
import 'package:thmr_app/core/theme/thmr_focus_ring.dart';
import 'package:thmr_app/core/theme/thmr_theme.dart';
import 'package:thmr_app/features/large_screen/large_screen_controller.dart';
import 'package:thmr_app/features/large_screen/large_screen_surface.dart';
import 'package:thmr_app/features/large_screen/large_screen_settings_panel.dart';
import 'package:thmr_app/features/mini/desktop_player_surface.dart';

class _Station extends StateNotifier<StationUiState> implements StationPoller {
  _Station()
      : super(StationUiState(
            initialLoading: false,
            status: StationStatus.fromJson({
              'station': {'id': 'test', 'name': '东方音乐电台'},
              'current': {
                'trackId': 'test',
                'title': '原生窗口切换检查',
                'artist': 'Touhou Music Radio',
                'durationSec': 180,
                'positionSec': 10
              },
              'queue': [
                for (var i = 0; i < 8; i++)
                  {'trackId': '$i', 'title': '接下来 $i', 'artist': '东方音乐电台'}
              ],
            })));
  @override
  Future<void> refresh() async {}
}

class _Playback extends StateNotifier<PlaybackState>
    implements PlaybackController {
  _Playback() : super(const PlaybackState());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Settings extends LargeScreenSettingsController {
  @override
  Future<void> update(LargeScreenSettings next) async {
    state = next;
  }

  @override
  Future<void> persist() async {}
}

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  binding.deferFirstFrame();
  final errors = <FlutterErrorDetails>[];
  FlutterError.onError = (error) {
    errors.add(error);
    FlutterError.presentError(error);
  };
  final container = ProviderContainer(overrides: [
    stationProvider.overrideWith((ref) => _Station()),
    playbackProvider.overrideWith((ref) => _Playback()),
    largeScreenSettingsProvider.overrideWith((ref) => _Settings()),
    channelCatalogProvider.overrideWith(
        (ref) async => const [RadioChannel(id: 'touhou', name: '综合频道')]),
  ]);
  await container.read(largeScreenSettingsProvider.notifier).ready;
  const editorPreview = bool.fromEnvironment('editorPreview');
  if (editorPreview) {
    await container.read(largeScreenSettingsProvider.notifier).update(
            const LargeScreenSettings(queue: LargeScreenQueue.list, widgets: [
          LargeScreenWidgetSettings(id: 'clock', format: 'HH:mm:ss'),
          LargeScreenWidgetSettings(
              id: 'date',
              kind: LargeScreenWidgetKind.date,
              position: LargeScreenWidgetPosition.topLeft,
              format: 'M月d日 EEEE',
              fontSize: 20),
          LargeScreenWidgetSettings(
              id: 'event',
              kind: LargeScreenWidgetKind.text,
              position: LargeScreenWidgetPosition.bottomCenter,
              text: '河东 THO · 东方音乐电台',
              fontSize: 24),
        ]));
  }
  await initializeDesktopWindow();
  if (editorPreview) await windowManager.setSize(const Size(1280, 880));
  final retained = GlobalKey();
  final renderedFrame = GlobalKey();
  final inputKey = GlobalKey();
  final input = TextEditingController(text: 'THMR');
  final mainFocus = FocusNode();
  final scroll = ScrollController();
  runApp(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: editorPreview
            ? ThmrTheme.dark()
            : ThemeData(
                useMaterial3: true,
                colorScheme: ColorScheme.fromSeed(seedColor: ThmrColors.accent),
                extensions: [ThmrTokens.reimuLight.accessible()]),
        builder: (context, child) => RepaintBoundary(
            key: renderedFrame,
            child: Consumer(
                builder: (context, ref, _) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(
                        disableAnimations:
                            const bool.fromEnvironment('reducedMotion')),
                    child: ThmrFocusLayer(
                        reserveEdgeSpace: !ref
                            .watch(largeScreenProvider.select((s) => s.active)),
                        child: DesktopPlayerSurface(child: child!))))),
        home: editorPreview
            ? const LargeScreenSettingsPage()
            : LargeScreenSurface(
                child: Scaffold(
                    key: retained,
                    body: Column(children: [
                      TextField(
                          key: inputKey,
                          controller: input,
                          focusNode: mainFocus),
                      Expanded(
                          child: ListView.builder(
                              controller: scroll,
                              itemCount: 100,
                              itemExtent: 50,
                              itemBuilder: (_, i) => Text('普通播放器 $i'))),
                    ]))),
      )));
  await binding.endOfFrame;
  binding.allowFirstFrame();
  await binding.waitUntilFirstFrameRasterized;
  if (editorPreview) {
    try {
      await _checkEditor(binding, renderedFrame, errors);
      debugPrint(
          'LARGE_SCREEN_EDITOR_PASS: native configuration, text input, format presets, expansion state and live preview; no Flutter errors');
      _exitProbe(0);
    } catch (error, stack) {
      debugPrint('LARGE_SCREEN_EDITOR_FAIL: $error\n$stack');
      _exitProbe(1);
    }
  }
  await windowManager.show();
  await windowManager.focus();
  await WindowPresentation().startupReady();
  scroll.jumpTo(750);
  mainFocus.requestFocus();
  await binding.endOfFrame;
  final initialElement = retained.currentContext;
  final initialInputElement = inputKey.currentContext;
  final initialMetrics = MediaQuery.sizeOf(retained.currentContext!);
  final initialSize =
      (retained.currentContext!.findRenderObject() as RenderBox).size;
  final initialBounds = await windowManager.getBounds();
  final controller = container.read(largeScreenProvider.notifier);
  try {
    for (var cycle = 0; cycle < 4; cycle++) {
      final profile = LargeScreenSettings(
        layout: LargeScreenLayout.values[cycle],
        queue: cycle == 0 && const bool.fromEnvironment('previewPause')
            ? LargeScreenQueue.list
            : LargeScreenQueue.values[cycle],
        framing:
            cycle.isEven ? LargeScreenFraming.fill : LargeScreenFraming.fit,
        startFullScreen: cycle.isEven,
        autoHideControls: false,
        musicEffect: cycle.isEven
            ? LargeScreenMusicEffect.fluid
            : LargeScreenMusicEffect.aurora,
        widgets: const [
          LargeScreenWidgetSettings(id: 'time', format: 'HH:mm:ss'),
          LargeScreenWidgetSettings(
              id: 'date',
              kind: LargeScreenWidgetKind.date,
              position: LargeScreenWidgetPosition.topLeft,
              format: 'M月d日 EEEE',
              fontSize: 20),
          LargeScreenWidgetSettings(
              id: 'event',
              kind: LargeScreenWidgetKind.text,
              position: LargeScreenWidgetPosition.bottomCenter,
              text: '东方音乐交流会',
              fontSize: 24),
        ],
      );
      await container
          .read(largeScreenSettingsProvider.notifier)
          .update(profile);
      final entering = controller.change(true);
      if (!identical(entering, controller.change(true))) {
        throw StateError('Overlapping entry');
      }
      await entering.timeout(const Duration(seconds: 10));
      if (!container.read(largeScreenProvider).active) {
        throw StateError('Stage did not open');
      }
      await _checkVisibleStage(binding);
      const snapshotFile = String.fromEnvironment('snapshotFile');
      if (cycle == 0 && snapshotFile.isNotEmpty) {
        await binding.endOfFrame;
        final boundary = renderedFrame.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
        final raster = await boundary.toImage(
            pixelRatio:
                MediaQuery.devicePixelRatioOf(renderedFrame.currentContext!));
        final png = await raster.toByteData(format: ui.ImageByteFormat.png);
        raster.dispose();
        await File(snapshotFile)
            .writeAsBytes(png!.buffer.asUint8List(), flush: true);
        await controller.change(false);
        if (errors.isNotEmpty) {
          throw StateError('${errors.length} Flutter errors');
        }
        debugPrint('LARGE_SCREEN_SNAPSHOT_PASS: $snapshotFile');
        _exitProbe(0);
      }
      if (cycle == 0 && const bool.fromEnvironment('previewPause')) {
        debugPrint('LARGE_SCREEN_PREVIEW_READY');
        const readyFile = String.fromEnvironment('previewReadyFile');
        if (readyFile.isNotEmpty) {
          await File(readyFile).writeAsString('ready', flush: true);
        }
        await Future<void>.delayed(const Duration(seconds: 30));
      }
      if (MediaQuery.sizeOf(retained.currentContext!) != initialMetrics ||
          scroll.offset != 750) {
        throw StateError('Hidden page reflowed or scrolled during entry');
      }
      if (await windowManager.isFullScreen() != profile.startFullScreen) {
        throw StateError('Initial fullscreen state');
      }
      for (var toggle = 0; toggle < 2; toggle++) {
        final wasFullScreen = await windowManager.isFullScreen();
        await controller
            .toggleFullScreen()
            .timeout(const Duration(seconds: 10));
        if (!container.read(largeScreenProvider).active ||
            await windowManager.isFullScreen() == wasFullScreen) {
          throw StateError('Fullscreen toggle lost the player or failed');
        }
        await _checkVisibleStage(binding);
      }
      await _checkCollapseFrames(binding, controller);
      if (container.read(largeScreenProvider).active ||
          await windowManager.isFullScreen()) {
        throw StateError('Ordinary window not restored');
      }
      if (retained.currentContext != initialElement ||
          (retained.currentContext!.findRenderObject() as RenderBox).size !=
              initialSize) {
        throw StateError('Retained page changed size or identity');
      }
      if (inputKey.currentContext != initialInputElement ||
          input.text != 'THMR' ||
          scroll.offset != 750 ||
          !mainFocus.hasFocus) {
        throw StateError('Input state, focus or scroll position lost');
      }
      final bounds = await windowManager.getBounds();
      if ((bounds.width - initialBounds.width).abs() > 2 ||
          (bounds.height - initialBounds.height).abs() > 2) {
        throw StateError(
            'Window bounds not restored: $initialBounds -> $bounds');
      }
      debugPrint(
          'LARGE_SCREEN_SMOKE cycle=$cycle layout=${profile.layout.name} queue=${profile.queue.name} PASS');
    }
    final queued = controller.change(true);
    if (!identical(queued, controller.change(false))) {
      throw StateError('Exit request escaped the transition queue');
    }
    await queued.timeout(const Duration(seconds: 10));
    if (container.read(largeScreenProvider).active ||
        container.read(largeScreenProvider).busy) {
      throw StateError('Queued exit was dropped');
    }
    await windowManager.maximize();
    final deadline = DateTime.now().add(const Duration(seconds: 3));
    while (!await windowManager.isMaximized()) {
      if (DateTime.now().isAfter(deadline)) {
        throw StateError('Maximize timed out');
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await WindowPresentation().flushFrame();
    await container
        .read(largeScreenSettingsProvider.notifier)
        .update(const LargeScreenSettings(startFullScreen: true));
    await controller.change(true).timeout(const Duration(seconds: 10));
    await _checkCollapseFrames(binding, controller);
    if (!await windowManager.isMaximized() || scroll.offset != 750) {
      throw StateError('Maximized window or scroll not restored');
    }
    if (errors.isNotEmpty) throw StateError('${errors.length} Flutter errors');
    debugPrint(
        'LARGE_SCREEN_SMOKE PASS: 20 native transitions; page, metrics, input, focus, scroll, maximized window and queued exit verified; no Flutter errors');
    _exitProbe(0);
  } catch (error, stack) {
    debugPrint('LARGE_SCREEN_SMOKE FAIL: $error\n$stack');
    _exitProbe(1);
  }
}

Future<void> _checkEditor(WidgetsBinding binding, GlobalKey frame,
    List<FlutterErrorDetails> errors) async {
  Element find(bool Function(Widget) matches) {
    Element? found;
    void visit(Element element) {
      if (matches(element.widget)) {
        found ??= element;
      } else {
        element.visitChildElements(visit);
      }
    }

    visit(binding.rootElement!);
    if (found == null) throw StateError('Configuration control not mounted');
    return found!;
  }

  Future<void> settle() async {
    await Future<void>.delayed(const Duration(milliseconds: 300));
    binding.scheduleFrame();
    await binding.endOfFrame;
  }

  (find((w) => w is TabBar).widget as TabBar).controller!.index = 1;
  await settle();
  void select(String id) =>
      (find((w) => w.key == ValueKey('select-$id')).widget as InputChip)
          .onSelected!(true);
  select('date');
  await settle();
  final advanced = find((w) => w is ExpansionTile);
  VoidCallback? toggle;
  void ink(Element element) {
    final control = element.widget;
    if (control is InkWell && control.onTap != null) toggle ??= control.onTap;
    element.visitChildElements(ink);
  }

  ink(advanced);
  if (toggle == null) throw StateError('Advanced styles cannot expand');
  toggle!();
  await settle();
  final format = find((w) => w.key == const ValueKey('component-format-date'))
      .widget as TextField;
  format.controller!.text = 'yyyy-MM-dd EEEE';
  format.onChanged!(format.controller!.text);
  await settle();
  (find((w) =>
          w is ChoiceChip &&
          w.label is Text &&
          (w.label as Text).data == '月日与星期').widget as ChoiceChip)
      .onSelected!(true);
  await settle();
  toggle!();
  await settle();
  toggle!();
  await settle();
  select('event');
  await settle();
  final text = find((w) => w.key == const ValueKey('component-text-event'))
      .widget as TextField;
  text.controller!.value = const TextEditingValue(
      text: '河东 THO · 东方音乐电台', selection: TextSelection.collapsed(offset: 15));
  text.onChanged!(text.controller!.text);
  await settle();
  if (errors.isNotEmpty) {
    throw StateError('${errors.length} Flutter errors: ${errors.first}');
  }
  const snapshot = String.fromEnvironment('snapshotFile');
  if (snapshot.isNotEmpty) {
    final boundary =
        frame.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final raster = await boundary.toImage(
        pixelRatio: MediaQuery.devicePixelRatioOf(frame.currentContext!));
    final data = await raster.toByteData(format: ui.ImageByteFormat.png);
    raster.dispose();
    await File(snapshot).writeAsBytes(data!.buffer.asUint8List(), flush: true);
    debugPrint('LARGE_SCREEN_EDITOR_SNAPSHOT: $snapshot');
  }
}

Element? _findFrameElement(WidgetsBinding binding, Key key) {
  Element? result;
  void visit(Element element) {
    if (element.widget.key == key) {
      result = element;
      return;
    }
    element.visitChildElements((child) {
      if (result == null) visit(child);
    });
  }

  visit(binding.rootElement!);
  return result;
}

Future<void> _checkCollapseFrames(
    WidgetsBinding binding, LargeScreenController controller) async {
  var watching = true;
  var sawStandard = false;
  String? badFrame;
  void sample(Duration _) {
    if (!watching) return;
    final stage =
        _findFrameElement(binding, const ValueKey('large-mode-transition'));
    final transition = stage ??
        _findFrameElement(binding, const ValueKey('standard-mode-transition'));
    final fade = transition?.widget;
    if (fade is! ThmrFadeSlide || fade.animation.value != 1) {
      badFrame ??= 'Incomplete ${stage == null ? 'ordinary' : 'stage'} frame';
    }
    if (stage == null && fade is ThmrFadeSlide) sawStandard = true;
    binding.addPostFrameCallback(sample);
  }

  binding.addPostFrameCallback(sample);
  try {
    await controller.change(false).timeout(const Duration(seconds: 10));
  } finally {
    watching = false;
  }
  if (badFrame != null || !sawStandard) {
    throw StateError(badFrame ?? 'No ordinary frame after collapsing');
  }
}

Future<void> _checkVisibleStage(WidgetsBinding binding) async {
  Element? find(Key key) => _findFrameElement(binding, key);

  final fade = find(const ValueKey('large-mode-transition'))?.widget;
  if (fade is! ThmrFadeSlide || fade.animation.value != 1) {
    throw StateError(
        'Stage content is transparent after a completed transition');
  }
  final fadeElement = find(const ValueKey('large-mode-transition'))!;
  void inspect(Element element) {
    if (element.widget is FadeTransition) {
      if ((element.widget as FadeTransition).opacity.value != 1) {
        throw StateError('A painted stage layer remains transparent');
      }
    }
    element.visitChildElements(inspect);
  }

  inspect(fadeElement);
  for (final key in [
    'large-screen-window-drag',
    'large-screen-title',
    'large-screen-cover',
    'large-screen-controls'
  ]) {
    final element = find(ValueKey(key));
    if (element == null) continue;
    final render = element.findRenderObject()! as RenderBox;
    final rect = MatrixUtils.transformRect(
        render.getTransformTo(null), Offset.zero & render.size);
    if (!(Offset.zero & MediaQuery.sizeOf(element)).contains(rect.center)) {
      throw StateError('Stage content is outside the viewport: $key $rect');
    }
  }
  final controls = find(const ValueKey('large-screen-controls'))!;
  final box = controls.findRenderObject()! as RenderBox;
  final bottom = box.localToGlobal(Offset(0, box.size.height)).dy;
  final insets = await WindowPresentation().workAreaInsets();
  final available = MediaQuery.sizeOf(controls).height - insets.bottom;
  if (bottom > available + 1) {
    throw StateError('Controls overlap the taskbar: $bottom > $available');
  }
}

Never _exitProbe(int code) {
  // Match the existing Windows native probe: avoid registered media DLL hooks
  // blocking ExitProcess after the successful checks, even without audio.
  final kernel = ffi.DynamicLibrary.open('kernel32.dll');
  final current = kernel.lookupFunction<ffi.Pointer<ffi.Void> Function(),
      ffi.Pointer<ffi.Void> Function()>('GetCurrentProcess');
  final terminate = kernel.lookupFunction<
      ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Uint32),
      int Function(ffi.Pointer<ffi.Void>, int)>('TerminateProcess');
  terminate(current(), code);
  exit(code);
}
