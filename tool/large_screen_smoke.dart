// Real HWND, fullscreen, raster-fence and retained-page checks. No network,
// audio or preference writes. Run with the normal THMR instance closed:
// flutter run -d windows -t tool/large_screen_smoke.dart --no-pub
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:flutter/material.dart';
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
import 'package:thmr_app/features/large_screen/large_screen_controller.dart';
import 'package:thmr_app/features/large_screen/large_screen_surface.dart';
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
  await initializeDesktopWindow();
  final retained = GlobalKey();
  final inputKey = GlobalKey();
  final input = TextEditingController(text: 'THMR');
  final mainFocus = FocusNode();
  final scroll = ScrollController();
  runApp(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: ThemeData(
            useMaterial3: true,
            colorScheme: ColorScheme.fromSeed(seedColor: ThmrColors.accent),
            extensions: [ThmrTokens.reimuLight.accessible()]),
        builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
                disableAnimations: const bool.fromEnvironment('reducedMotion')),
            child: DesktopPlayerSurface(child: child!)),
        home: LargeScreenSurface(
            child: Scaffold(
                key: retained,
                body: Column(children: [
                  TextField(
                      key: inputKey, controller: input, focusNode: mainFocus),
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
        queue: LargeScreenQueue.values[cycle],
        framing:
            cycle.isEven ? LargeScreenFraming.fill : LargeScreenFraming.fit,
        startFullScreen: cycle.isEven,
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
      }
      await controller.change(false).timeout(const Duration(seconds: 10));
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
    await controller.change(false).timeout(const Duration(seconds: 10));
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
