import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// macOS 媒体控制适配器，对接 MPNowPlayingInfoCenter 和 MPRemoteCommandCenter。
/// Dart 管理共享媒体状态。原生接入前缓存更新，接入后按快照推送。
class MacosMediaControls {
  MacosMediaControls({
    required this.play,
    required this.pause,
    required this.stop,
  });

  static const channel = MethodChannel('thmr/macos_media');
  final Future<void> Function() play, pause, stop;
  final Map<String, Object> _state = {
    'status': 'Stopped',
    'title': '',
    'artist': '',
    'artwork': '',
    'duration': 0,
    'position': 0,
  };
  bool _ready = false;
  bool _disposed = false;

  Future<void> start() async {
    if (_disposed) return;
    channel.setMethodCallHandler((call) async {
      if (_disposed || call.method != 'command') return;
      final args = call.arguments as Map;
      try {
        switch (args['command']) {
          case 'play':
            await play();
          case 'pause':
            await pause();
          case 'stop':
            await stop();
        }
      } catch (error) {
        debugPrint('macOS media command failed: $error');
      }
    });
    try {
      await channel.invokeMethod<void>('start');
      if (_disposed) return;
      _ready = true;
      await _push();
    } catch (error) {
      debugPrint('macOS media controls unavailable: $error');
    }
  }

  Future<void> update(Map<String, Object> state) async {
    if (_disposed) return;
    _state.addAll(state);
    await _push();
  }

  Future<void> _push() async {
    if (!_ready) return;
    try {
      await channel.invokeMethod<void>(
          'update', Map<String, Object>.of(_state));
    } catch (error) {
      debugPrint('macOS media state update failed: $error');
    }
  }

  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    _ready = false;
    channel.setMethodCallHandler(null);
    try {
      await channel.invokeMethod<void>('stop');
    } catch (_) {}
  }
}
