import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';

import 'app.dart';
import 'core/player/audio_engine.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 桌面 / 移动全平台播放后端(just_audio 桌面实现受限,统一 media_kit)
  MediaKit.ensureInitialized();

  if (!kIsWeb && Platform.isWindows) {
    await windowManager.ensureInitialized();
    const options = WindowOptions(
      titleBarStyle: TitleBarStyle.hidden,
      size: Size(1180, 780),
      minimumSize: Size(430, 660),
      backgroundColor: Colors.transparent,
    );
    await windowManager.waitUntilReadyToShow(options, () async {
      await windowManager.show();
      await windowManager.focus();
    });
  }

  runApp(const ProviderScope(child: ThmrApp()));
  // Audio service registration can wait for Android's service binding. It must
  // never keep the launch screen up or prevent the app from opening.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(initBackgroundAudio()
        .timeout(const Duration(seconds: 20))
        .catchError((Object error, StackTrace stack) {
      debugPrint('Background audio initialization failed: $error\n$stack');
    }));
  });
}
