import 'dart:async';
import 'dart:io' show Directory, File;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:tray_manager/tray_manager.dart';

/// Owns the process-wide tray icon, including startup/exit races.
class DesktopTrayController with TrayListener {
  DesktopTrayController({
    required this.showWindow,
    required this.exitApplication,
    TargetPlatform? platform,
  }) : platform = platform ?? defaultTargetPlatform;

  static DesktopTrayController? _active;
  final TargetPlatform platform;
  final Future<void> Function() showWindow;
  final VoidCallback exitApplication;
  Directory? _directory;
  Future<bool>? _starting;
  Future<void>? _disposing;
  bool _disposed = false;
  bool _listening = false;
  bool _iconRequested = false;
  bool _ready = false;

  bool get isDisposed => _disposed;
  bool get ready => _ready && !_disposed;

  static Future<void> disposeActive() async => _active?.dispose();

  Future<bool> start() =>
      _disposed ? Future.value(false) : _starting ??= _start();

  Future<bool> _start() async {
    if (_disposed) return false;
    _active = this;
    trayManager.addListener(this);
    _listening = true;
    try {
      if (platform == TargetPlatform.macOS) {
        // tray_manager loads macOS icons through rootBundle, not file paths.
        _iconRequested = true;
        await trayManager.setIcon('assets/icons/icon-512.png', iconSize: 18);
      } else {
        final name = platform == TargetPlatform.windows
            ? 'thmr_tray.ico'
            : 'icon-512.png';
        final data = await rootBundle.load('assets/icons/$name');
        if (_disposed) return false;
        _directory = await Directory.systemTemp.createTemp('thmr-tray-');
        if (_disposed) return false;
        final file = File('${_directory!.path}/$name');
        await file.writeAsBytes(data.buffer.asUint8List(), flush: true);
        if (_disposed) return false;
        _iconRequested = true;
        await trayManager.setIcon(file.path);
      }
      if (_disposed) return false;
      if (platform == TargetPlatform.windows ||
          platform == TargetPlatform.macOS) {
        await trayManager.setToolTip('东方音乐电台 THMR');
      }
      if (_disposed) return false;
      await trayManager.setContextMenu(Menu(items: [
        MenuItem(
          key: 'show-window',
          label: '显示主窗口',
          onClick: (_) => _showWindow(),
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'exit',
          label: '退出',
          onClick: (_) {
            if (!_disposed) exitApplication();
          },
        ),
      ]));
      if (_disposed) return false;
      _ready = true;
      return true;
    } catch (error) {
      debugPrint('Desktop tray initialization failed: $error');
      _removeListener();
      await _removeIconAndFiles();
      return false;
    }
  }

  void _showWindow() {
    if (!_disposed) unawaited(showWindow());
  }

  void _showMenu() {
    if (ready) unawaited(trayManager.popUpContextMenu());
  }

  @override
  void onTrayIconMouseDown() {
    if (platform == TargetPlatform.macOS) {
      _showMenu();
    } else {
      _showWindow();
    }
  }

  @override
  void onTrayIconRightMouseDown() => _showMenu();

  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    _ready = false;
    _removeListener();
    // A late setIcon reply must not recreate an icon after destroy().
    await _starting;
    await _removeIconAndFiles();
    if (identical(_active, this)) _active = null;
  }

  void _removeListener() {
    if (!_listening) return;
    _listening = false;
    trayManager.removeListener(this);
  }

  Future<void> _removeIconAndFiles() async {
    if (_iconRequested) {
      _iconRequested = false;
      try {
        await trayManager.destroy();
      } catch (error) {
        debugPrint('Desktop tray removal failed: $error');
      }
    }
    final directory = _directory;
    _directory = null;
    if (directory != null) {
      try {
        await directory.delete(recursive: true);
      } catch (error) {
        debugPrint('Desktop tray file cleanup failed: $error');
      }
    }
  }
}
