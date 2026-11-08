import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The adapter caches state before the first frame starts the native service.
/// D-Bus commands enter the same controller callbacks as on-screen controls.
class LinuxMediaControls {
  LinuxMediaControls({
    required this.play,
    required this.pause,
    required this.stop,
    required this.setVolume,
    required this.raise,
  });

  static const channel = MethodChannel('thmr/linux_media');
  final Future<void> Function() play, pause, stop, raise;
  final Future<void> Function(double) setVolume;
  final Map<String, Object> _state = {
    'status': 'Stopped',
    'track': '',
    'title': '',
    'artist': '',
    'artwork': '',
    'duration': 0,
    'position': 0,
    'volume': 1.0,
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
          case 'raise':
            await raise();
          case 'volume':
            await setVolume(
                (args['value'] as num).toDouble().clamp(0, 1) * 100);
        }
      } catch (error) {
        debugPrint('Linux media command failed: $error');
      }
    });
    try {
      await channel.invokeMethod<void>('start');
      _ready = true;
      await _push();
    } catch (error) {
      debugPrint('Linux media controls unavailable: $error');
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
      debugPrint('Linux media state update failed: $error');
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
