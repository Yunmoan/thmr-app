import 'dart:async';
import 'dart:io' show exit;
import 'dart:ui' show AppExitType;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Colors, Size;
import 'package:flutter/services.dart' show ServicesBinding;
import 'package:window_manager/window_manager.dart';

import 'windows_process_exit.dart';

bool get hasDesktopWindowControls =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux);

String desktopTrayActionLabel({required bool available}) {
  if (defaultTargetPlatform == TargetPlatform.macOS) {
    return available ? '隐藏到菜单栏' : '最小化到 Dock';
  }
  return available ? '最小化到托盘' : '最小化到任务栏';
}

/// GTK owns Linux's decorations, initial geometry and first-frame presentation.
/// Initializing window_manager must not replace its native header bar.
Future<void> initializeDesktopWindow({TargetPlatform? platform}) async {
  if (kIsWeb) return;
  switch (platform ?? defaultTargetPlatform) {
    case TargetPlatform.windows:
      await windowManager.ensureInitialized();
      await windowManager.waitUntilReadyToShow(const WindowOptions(
        titleBarStyle: TitleBarStyle.hidden,
        size: Size(1180, 780),
        minimumSize: Size(430, 660),
        backgroundColor: Colors.transparent,
      ));
    case TargetPlatform.linux:
      await windowManager.ensureInitialized();
    case TargetPlatform.macOS:
      // Keep AppKit's title bar and geometry; only install the close delegate.
      await windowManager.ensureInitialized();
      await windowManager.setPreventClose(true);
    default:
      break;
  }
}

Future<void> restoreDesktopWindow() async {
  await windowManager.show();
  await windowManager.focus();
}

/// Stop Linux playback and background work before terminating the process.
/// Both GTK window destruction and Flutter's application exit can race native
/// plugin/engine threads during shutdown. Avoid that teardown after cleanup.
Future<void> quitDesktopApplication(Future<void> Function() releaseResources,
    {TargetPlatform? platform, void Function(int) exitProcess = exit}) async {
  final target = platform ?? defaultTargetPlatform;
  if (target == TargetPlatform.windows) terminateWindowsProcess();
  if (target == TargetPlatform.macOS) {
    // Cmd+Q and the tray Exit item must share main.dart's exit coordinator.
    // Destroying the window or forcing an exit would bypass its mpv cleanup.
    await ServicesBinding.instance.exitApplication(AppExitType.cancelable);
    return;
  }
  try {
    await releaseResources().timeout(const Duration(seconds: 3));
  } catch (error) {
    debugPrint('Desktop resource cleanup failed: $error');
  }
  if (target == TargetPlatform.linux) {
    exitProcess(0);
    return;
  }
  try {
    await windowManager.destroy();
  } catch (error) {
    debugPrint('Desktop window shutdown failed: $error');
    exit(0);
  }
}
