// 检查真实 Windows runner、DWM 窗口隐藏与光栅化同步，完成后退出。
// 运行步骤见 docs/development/verification.md。
import 'dart:io';
import 'dart:ffi' as ffi;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'package:thmr_app/core/platform/window_presentation.dart';
import 'package:thmr_app/core/state/settings_provider.dart';
import 'package:thmr_app/features/mini/desktop_player_surface.dart';
import 'package:thmr_app/features/mini/mini_player.dart';
import 'package:thmr_app/shared/widgets/thmr_panel.dart';

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
  // 使用正式窗口切换和毛玻璃卡片，页面内容使用本地测试数据。
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
          child: _WindowCards(),
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
    const restoreCycles =
        int.fromEnvironment('restoreCycles', defaultValue: 40);
    final presentation = WindowPresentation();
    var slowestRestore = 0;
    for (var cycle = 0; cycle < restoreCycles; cycle++) {
      final maximize = cycle.isEven;
      if (maximize) {
        await windowManager.maximize();
      } else {
        await windowManager.unmaximize();
      }
      await _waitForWindow(
          () async => await windowManager.isMaximized() == maximize);
      await binding.endOfFrame.timeout(const Duration(seconds: 4));
      final view = binding.platformDispatcher.implicitView!;
      final expectedSize = view.physicalSize;
      await windowManager.minimize();
      await _waitForWindow(windowManager.isMinimized);
      final start = clock.elapsedMilliseconds;
      await windowManager.restore();
      await _waitForWindow(() async => !await windowManager.isMinimized());
      await binding.endOfFrame.timeout(const Duration(seconds: 4));
      await presentation.flushFrame();
      if (view.physicalSize.isEmpty || view.physicalSize != expectedSize) {
        throw StateError('Restore changed the Flutter viewport: '
            '$expectedSize -> ${view.physicalSize}');
      }
      final elapsed = clock.elapsedMilliseconds - start;
      if (elapsed > slowestRestore) slowestRestore = elapsed;
    }
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
      await _waitForWindow(() async => !await windowManager.isMaximized());
    }
    _report(
        'WINDOW_SMOKE restored $restoreCycles times, max=${slowestRestore}ms');

    const cycles = int.fromEnvironment('cycles', defaultValue: 12);
    for (var cycle = 0; cycle < cycles; cycle++) {
      final maximize = cycle.isOdd;
      if (maximize) {
        await windowManager.maximize();
        // 标题栏路径只投递命令，测试需等原生状态真正更新。
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
      _report('WINDOW_SMOKE cycle=$cycle maximized=$maximize '
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
    _report(
        'WINDOW_SMOKE PASS: ${cycles * 2} native transitions, no Flutter errors');
    _exitProbe(0);
  } catch (error, stack) {
    _report('WINDOW_SMOKE FAIL: $error\n$stack');
    _exitProbe(1);
  }
}

void _report(String message) {
  debugPrint(message);
  const path = String.fromEnvironment('reportPath');
  if (path.isNotEmpty) {
    File(path).writeAsStringSync('$message\n', mode: FileMode.append);
  }
}

Future<void> _waitForWindow(Future<bool> Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!await condition()) {
    if (DateTime.now().isAfter(deadline)) {
      throw StateError('Window state change timed out');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

class _WindowCards extends StatelessWidget {
  const _WindowCards();

  @override
  Widget build(BuildContext context) => GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 350,
          mainAxisExtent: 120,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
        ),
        itemCount: 24,
        itemBuilder: (context, index) => ThmrPanel(
          child: Center(child: Text('MAIN ${index + 1}')),
        ),
      );
}

Never _exitProbe(int code) {
  // 沿用应用的 Windows 退出路径。即使探针从未启动播放，媒体 DLL 仍可能在卸载时阻塞常规
  // ExitProcess。
  final kernel = ffi.DynamicLibrary.open('kernel32.dll');
  final current = kernel.lookupFunction<ffi.Pointer<ffi.Void> Function(),
      ffi.Pointer<ffi.Void> Function()>('GetCurrentProcess');
  final terminate = kernel.lookupFunction<
      ffi.Int32 Function(ffi.Pointer<ffi.Void>, ffi.Uint32),
      int Function(ffi.Pointer<ffi.Void>, int)>('TerminateProcess');
  terminate(current(), code);
  exit(code);
}
