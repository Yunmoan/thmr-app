import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final desktopTrayAvailableProvider =
    StateProvider<bool>((ref) => !kIsWeb && Platform.isWindows);

/// Recheck the actual panel host, including after a shell restart. Never infer
/// availability from tray_manager's successful icon-registration call.
class LinuxTrayMonitor extends ValueNotifier<bool> {
  LinuxTrayMonitor() : super(false);

  static const channel = MethodChannel('thmr/linux_tray');
  Timer? _timer;
  bool _disposed = false;
  bool _checking = false;

  Future<void> start() async {
    if (await refresh() && !_disposed) {
      _timer ??= Timer.periodic(const Duration(seconds: 2), (_) => refresh());
    }
  }

  Future<bool> refresh() async {
    if (_disposed || _checking) return false;
    _checking = true;
    try {
      final available = await channel
              .invokeMethod<bool>('isAvailable')
              .timeout(const Duration(seconds: 2)) ??
          false;
      if (!_disposed) value = available;
      return true;
    } on MissingPluginException {
      if (!_disposed) value = false;
      return false;
    } catch (_) {
      if (!_disposed) value = false;
      return true;
    } finally {
      _checking = false;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }
}
