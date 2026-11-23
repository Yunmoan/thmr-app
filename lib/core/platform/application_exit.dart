import 'dart:io' show exit;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';

/// 清理原生音频回调期间保持 Dart isolate 存活。窗口、菜单和键盘同时发起的退出请求共用同一次清理。
class ApplicationExitCoordinator {
  ApplicationExitCoordinator(
    this.releaseResources, {
    this.timeout = const Duration(seconds: 3),
    this.exitProcess = exit,
  });

  final Future<void> Function() releaseResources;
  final Duration timeout;
  final void Function(int) exitProcess;
  Future<AppExitResponse>? _pending;

  Future<AppExitResponse> requestExit() => _pending ??= _release();

  Future<AppExitResponse> _release() async {
    try {
      await releaseResources().timeout(timeout);
    } catch (error) {
      debugPrint('Application exit cleanup failed: $error');
      // 如果原生插件卡住，直接结束进程，避免在回调仍可能运行时卸载 Flutter VM。
      exitProcess(0);
    }
    return AppExitResponse.exit;
  }
}
