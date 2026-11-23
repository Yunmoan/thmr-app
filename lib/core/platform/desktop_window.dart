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

/// Linux 窗口装饰、初始位置与尺寸、首帧显示由 GTK 管理。初始化 window_manager 时需保留 GTK 的
/// 原生标题栏。
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
      // 仅安装关闭代理，保留 AppKit 的标题栏和窗口尺寸、位置。
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

/// Linux 应先停止播放和后台任务，再直接结束进程。销毁 GTK 窗口或走 Flutter 的常规退出流程可能与
/// 原生线程收尾发生竞态。
Future<void> quitDesktopApplication(Future<void> Function() releaseResources,
    {TargetPlatform? platform, void Function(int) exitProcess = exit}) async {
  final target = platform ?? defaultTargetPlatform;
  if (target == TargetPlatform.windows) terminateWindowsProcess();
  if (target == TargetPlatform.macOS) {
    // Cmd+Q 和托盘「退出」共用 main.dart 中的退出协调逻辑，确保 mpv 清理完成后再退出。
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
