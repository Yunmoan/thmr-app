import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app.dart';
import 'core/platform/window_presentation.dart';
import 'core/platform/desktop_window.dart';
import 'core/platform/desktop_tray.dart';
import 'core/platform/application_exit.dart';
import 'core/platform/mobile_presentation.dart';
import 'core/player/audio_engine.dart';
import 'core/player/shared_radio_stream.dart';
import 'core/player/spectrum_linux.dart';
import 'core/state/settings_provider.dart';
import 'core/state/large_screen_settings.dart';
import 'core/theme/thmr_colors.dart';
import 'core/update/update_packages.dart';

Future<void> main(List<String> args) async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  final isWindows = !kIsWeb && Platform.isWindows;
  if (isWindows) binding.deferFirstFrame();
  final updateLaunch = args.contains('--thmr-update-ack') ||
      Platform.environment.containsKey('THMR_UPDATE_ACK');
  var startupHealthy = true;
  final previousErrorHandler = FlutterError.onError;
  void updateErrorHandler(FlutterErrorDetails details) {
    startupHealthy = false;
    previousErrorHandler?.call(details);
  }

  if (updateLaunch) FlutterError.onError = updateErrorHandler;
  // 桌面端和移动端统一使用 media_kit 播放。
  try {
    MediaKit.ensureInitialized();
  } catch (error, stack) {
    if (kIsWeb || !Platform.isLinux) rethrow;
    debugPrint('Linux audio initialization failed: $error\n$stack');
    runApp(const MaterialApp(
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: SelectableText(
              '无法初始化音频播放。\n\n'
              '请使用 bundle 目录中的 thmr 启动器检查运行依赖。\n'
              'Ubuntu/Debian 可安装 libmpv2；完整说明见 README-Linux.md。',
            ),
          ),
        ),
      ),
    ));
    return; // 播放引擎初始化失败时，不确认更新成功。
  }

  final container = ProviderContainer();
  if (hasIosPresentation) unawaited(container.read(iosIsPadProvider.future));
  await Future.wait([
    container.read(settingsProvider.notifier).ready,
    container.read(largeScreenSettingsProvider.notifier).ready,
  ]);

  await initializeDesktopWindow();

  if (!kIsWeb && Platform.isMacOS) {
    final shutdown = ApplicationExitCoordinator(() async {
      await DesktopTrayController.disposeActive();
      // 释放 mpv 前先取消轮询、重连定时器和播放器订阅。AppKit 在清理完成前需保持 Flutter 引擎
      // 运行。
      container.dispose();
      try {
        await LinuxSpectrum.appleInstance.dispose();
        await disposeSystemMediaControls();
      } finally {
        await enginePlayer.dispose();
        await sharedRadioStream.dispose();
      }
    });
    AppLifecycleListener(onExitRequested: shutdown.requestExit);
  }

  runApp(UncontrolledProviderScope(
    container: container,
    child: const ThmrApp(),
  ));
  // 音频服务注册可能等待 Android 绑定服务，因此在界面首帧后异步启动。
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (updateLaunch) {
      // 给首帧后的启动错误留出观察窗口，再向安装辅助程序确认更新。
      unawaited(Future<void>.delayed(const Duration(seconds: 3), () async {
        if (startupHealthy) await acknowledgeInstalledUpdate(args);
        if (FlutterError.onError == updateErrorHandler) {
          FlutterError.onError = previousErrorHandler;
        }
      }));
    }
    unawaited(initBackgroundAudio()
        .timeout(const Duration(seconds: 20))
        .catchError((Object error, StackTrace stack) {
      debugPrint('Background audio initialization failed: $error\n$stack');
    }));
  });

  if (isWindows) {
    await _showMainWindow(binding, container.read(settingsProvider));
  }
}

Future<void> _showMainWindow(
    WidgetsBinding binding, AppSettings settings) async {
  try {
    // 窗口隐藏期间先构建界面，启动 Image 和 Google Fonts 加载。
    await binding.endOfFrame;
    final illustration =
        ThmrTokens.resolve(settings.accentTheme, Brightness.light).illustration;
    final context = binding.rootElement!;
    await Future.wait([
      precacheImage(AssetImage(illustration), context),
      precacheImage(const AssetImage('assets/brand/logo.png'), context),
      // 首次启动可能下载字体。给字体加载设定超时，届时继续显示窗口。
      GoogleFonts.pendingFonts().timeout(const Duration(seconds: 5)),
    ]);
    await binding.endOfFrame;
  } catch (error, stack) {
    debugPrint('Startup resource preparation failed: $error\n$stack');
  } finally {
    binding.allowFirstFrame();
  }
  // Dart 帧回调仅代表布局和绘制阶段已完成。等引擎光栅化首帧后再显示原生窗口。
  await binding.waitUntilFirstFrameRasterized;
  await windowManager.show();
  await windowManager.focus();
  await WindowPresentation().startupReady();
}
