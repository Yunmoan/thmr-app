import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final desktopTrayAvailableProvider =
    StateProvider<bool>((ref) => !kIsWeb && Platform.isWindows);

/// 检查实际承载托盘图标的面板服务，覆盖桌面 shell 重启的情况。
/// tray_manager 注册图标成功也可能没有可用的面板服务。
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
