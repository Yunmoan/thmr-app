import 'dart:io' show exit;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/foundation.dart';

/// Keeps the Dart isolate alive until native audio callbacks are detached.
/// Concurrent close/menu/keyboard requests must share the same cleanup.
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
      // If a native plugin is stuck, terminate the process directly rather than
      // unloading the Flutter VM underneath its still-live callbacks.
      exitProcess(0);
    }
    return AppExitResponse.exit;
  }
}
