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
import 'core/player/audio_engine.dart';
import 'core/state/settings_provider.dart';
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
  // 桌面 / 移动全平台播放后端(just_audio 桌面实现受限,统一 media_kit)
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
    return; // Never acknowledge an update whose playback engine cannot start.
  }

  final container = ProviderContainer();
  await container.read(settingsProvider.notifier).ready;

  await initializeDesktopWindow();

  runApp(UncontrolledProviderScope(
    container: container,
    child: const ThmrApp(),
  ));
  // Audio service registration can wait for Android's service binding. It must
  // never keep the launch screen up or prevent the app from opening.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (updateLaunch) {
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
    // Build while hidden so Image widgets and Google Fonts start loading.
    await binding.endOfFrame;
    final illustration =
        ThmrTokens.resolve(settings.accentTheme, Brightness.light).illustration;
    final context = binding.rootElement!;
    await Future.wait([
      precacheImage(AssetImage(illustration), context),
      precacheImage(const AssetImage('assets/brand/logo.png'), context),
      // Fonts may require a download on first launch. Fall back to system fonts
      // if the network is unavailable instead of leaving the window hidden.
      GoogleFonts.pendingFonts().timeout(const Duration(seconds: 5)),
    ]);
    await binding.endOfFrame;
  } catch (error, stack) {
    debugPrint('Startup resource preparation failed: $error\n$stack');
  } finally {
    binding.allowFirstFrame();
  }
  // A post-frame callback only means layout/paint is done on the Dart side.
  // Wait for the engine to rasterize it before exposing the native window.
  await binding.waitUntilFirstFrameRasterized;
  await windowManager.show();
  await windowManager.focus();
  await WindowPresentation().startupReady();
}
