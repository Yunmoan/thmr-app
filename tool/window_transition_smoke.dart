// Runs the real Windows runner, DWM cloak and raster fence without network or
// audio. Run: flutter run -d windows -t tool/window_transition_smoke.dart
// The probe exits automatically and never writes application preferences.
import 'dart:io';
import 'dart:ffi' as ffi;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'package:thmr_app/core/state/settings_provider.dart';
import 'package:thmr_app/features/mini/desktop_player_surface.dart';
import 'package:thmr_app/features/mini/mini_player.dart';

Future<void> main() async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  binding.deferFirstFrame();
  final errors = <FlutterErrorDetails>[];
  FlutterError.onError = (details) {
    errors.add(details);
    FlutterError.presentError(details);
  };
  final container = ProviderContainer();
  await container.read(settingsProvider.notifier).ready;
  // Avoid font downloads and polling: this uses the production surface with
  // simple colored content, while retaining its actual transition animation.
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(const WindowOptions(
    titleBarStyle: TitleBarStyle.hidden,
    size: Size(1180, 780),
    minimumSize: kMainMinWindowSize,
    backgroundColor: Colors.transparent,
  ));
  runApp(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          disableAnimations: const bool.fromEnvironment('reducedMotion'),
        ),
        child: const DesktopPlayerSurface(
          miniPlayer: ColoredBox(
            color: Colors.blue,
            child: Center(child: Text('MINI')),
          ),
          child: ColoredBox(
            color: Colors.red,
            child: Center(child: Text('MAIN')),
          ),
        ),
      ),
      home: const SizedBox.shrink(),
    ),
  ));
  await binding.endOfFrame;
  binding.allowFirstFrame();
  await binding.waitUntilFirstFrameRasterized;
  await windowManager.show();
  await windowManager.focus();
  final transition = container.read(miniModeTransitionProvider);
  final clock = Stopwatch()..start();
  try {
    const cycles = int.fromEnvironment('cycles', defaultValue: 12);
    for (var cycle = 0; cycle < cycles; cycle++) {
      final maximize = cycle.isOdd;
      if (maximize) {
        await windowManager.maximize();
        // The title-bar path posts a command, so wait for actual native state.
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        while (!await windowManager.isMaximized()) {
          if (DateTime.now().isAfter(deadline)) {
            throw StateError('Maximize timed out');
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }
      final bounds = maximize ? null : await windowManager.getBounds();
      final enterStart = clock.elapsedMilliseconds;
      final entering = transition.change(true, TextScaler.noScaling);
      final duplicate = transition.change(true, TextScaler.noScaling);
      if (!identical(entering, duplicate)) {
        throw StateError('Overlapping entry');
      }
      await entering.timeout(const Duration(seconds: 8));
      final enteredAt = clock.elapsedMilliseconds;
      if (!container.read(miniPlayerProvider)) {
        throw StateError('Mini not active');
      }
      await transition
          .change(false, TextScaler.noScaling)
          .timeout(const Duration(seconds: 8));
      if (container.read(miniPlayerProvider)) {
        throw StateError('Main not restored');
      }
      if (await windowManager.isMaximized() != maximize) {
        throw StateError('Maximized state lost');
      }
      final restored = await windowManager.getBounds();
      if (bounds != null &&
          ((restored.width - bounds.width).abs() > 2 ||
              (restored.height - bounds.height).abs() > 2)) {
        throw StateError('Bounds changed: $bounds -> $restored');
      }
      debugPrint('WINDOW_SMOKE cycle=$cycle maximized=$maximize '
          'enter=${enteredAt - enterStart}ms '
          'exit=${clock.elapsedMilliseconds - enteredAt}ms');
      if (maximize) {
        await windowManager.unmaximize();
        final deadline = DateTime.now().add(const Duration(seconds: 3));
        while (await windowManager.isMaximized()) {
          if (DateTime.now().isAfter(deadline)) {
            throw StateError('Restore timed out');
          }
          await Future<void>.delayed(const Duration(milliseconds: 10));
        }
      }
    }
    if (errors.isNotEmpty) throw StateError('${errors.length} Flutter errors');
    debugPrint(
        'WINDOW_SMOKE PASS: ${cycles * 2} native transitions, no Flutter errors');
    _exitProbe(0);
  } catch (error, stack) {
    debugPrint('WINDOW_SMOKE FAIL: $error\n$stack');
    _exitProbe(1);
  }
}

Never _exitProbe(int code) {
  // Match the app's Windows exit path: a registered media DLL can block normal
  // ExitProcess during teardown, even though this probe never starts playback.
  final kernel = ffi.DynamicLibrary.open('kernel32.dll');
  final current = kernel.lookupFunction<ffi.Pointer<ffi.Void> Function(),
      ffi.Pointer<ffi.Void> Function()>('GetCurrentProcess');
  final terminate = kernel.lookupFunction<
      ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Uint32),
      int Function(ffi.Pointer<ffi.Void>, int)>('TerminateProcess');
  terminate(current(), code);
  exit(code);
}
