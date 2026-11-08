import 'dart:async';
import 'dart:io' show Platform, exit;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Colors, Size;
import 'package:window_manager/window_manager.dart';

import 'windows_process_exit.dart';

bool get hasDesktopWindowControls =>
    !kIsWeb && (Platform.isWindows || Platform.isLinux);

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
    default:
      break;
  }
}

Future<void> restoreDesktopWindow() async {
  await windowManager.show();
  await windowManager.focus();
}

/// Keep Windows' workaround for DLL shutdown hangs. Linux releases resources
/// before letting GTK close the window and terminate its application normally.
Future<void> quitDesktopApplication(
    Future<void> Function() releaseResources) async {
  if (Platform.isWindows) terminateWindowsProcess();
  try {
    await releaseResources().timeout(const Duration(seconds: 3));
  } catch (error) {
    debugPrint('Desktop resource cleanup failed: $error');
  }
  try {
    await windowManager.destroy();
  } catch (error) {
    debugPrint('Desktop window shutdown failed: $error');
    exit(0);
  }
}
