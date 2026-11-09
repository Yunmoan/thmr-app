import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Dart adapter for macOS Now Playing (MPNowPlayingInfoCenter) and media
/// keys (MPRemoteCommandCenter), mirroring [LinuxMediaControls]: state is
/// cached until the native side attaches, then every change is pushed as a
/// whole so neither side tracks partial updates.
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

  Future<void> start() async {
    channel.setMethodCallHandler((call) async {
      if (call.method != 'command') return;
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
      _ready = true;
      await _push();
    } catch (error) {
      debugPrint('macOS media controls unavailable: $error');
    }
  }

  Future<void> update(Map<String, Object> state) async {
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
    _ready = false;
    channel.setMethodCallHandler(null);
    try {
      await channel.invokeMethod<void>('stop');
    } catch (_) {}
  }
}
