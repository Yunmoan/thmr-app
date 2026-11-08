import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:media_kit/media_kit.dart' show Media, Player;
import 'package:shared_preferences/shared_preferences.dart';

import '../state/station_provider.dart';
import '../state/radio_source_provider.dart';
import 'audio_engine.dart';
import 'shared_radio_stream.dart';

/// 播放状态机 — 与 Web 端 player store 对齐(FLUTTER.md 4.4)。
enum PlaybackPhase { idle, connecting, online, buffering, reconnecting }

class PlaybackState {
  final PlaybackPhase phase;
  final bool userPaused; // 用户手动暂停 → 不自动恢复
  final double volume; // 0-100
  final double lastAudibleVolume; // 取消静音时恢复的音量
  final int listenedSec; // 本次会话累计收听秒数(暂停冻结、换曲延续)
  final String? error;

  const PlaybackState({
    this.phase = PlaybackPhase.idle,
    this.userPaused = false,
    this.volume = 100,
    this.lastAudibleVolume = 100,
    this.listenedSec = 0,
    this.error,
  });

  bool get audiblyPlaying => phase == PlaybackPhase.online;

  double get volumeAfterMuteToggle => volume > 0 ? 0 : lastAudibleVolume;

  PlaybackState copyWith({
    PlaybackPhase? phase,
    bool? userPaused,
    double? volume,
    double? lastAudibleVolume,
    int? listenedSec,
    String? error,
    bool clearError = false,
  }) =>
      PlaybackState(
        phase: phase ?? this.phase,
        userPaused: userPaused ?? this.userPaused,
        volume: volume ?? this.volume,
        lastAudibleVolume: lastAudibleVolume ??
            (volume != null && volume > 0 ? volume : this.lastAudibleVolume),
        listenedSec: listenedSec ?? this.listenedSec,
        error: clearError ? null : (error ?? this.error),
      );
}

/// 直播流播放控制(media_kit)。
/// 断线恢复对齐 Web 端:error → 1s 重连;buffering 持续 >5s → 3s 后重连;
/// 连续失败 5 次退回 idle。用户手动暂停期间不自动恢复。
class PlaybackController extends StateNotifier<PlaybackState> {
  PlaybackController({String? Function()? streamUrl})
      : _streamUrl = streamUrl,
        super(const PlaybackState()) {
    // 全局共享播放引擎(audio_service / SMTC 共用同一实例)
    _player = enginePlayer;
    _playingSubscription = _player.stream.playing.listen(_onPlaying);
    _bufferingSubscription = _player.stream.buffering.listen(_onBuffering);
    _errorSubscription = _player.stream.error.listen(_onError);
    registerMediaControls(
      play: playFromSystem,
      pause: pause,
      stop: stop,
      volume: setVolume,
    );
    // 启动时恢复上次音量(shared_preferences,与设置项同一套方案)
    _loadVolume();
    // 累计收听计时:仅在「正在播放」时每秒 +1
    _listenTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted &&
          (state.phase == PlaybackPhase.online ||
              state.phase == PlaybackPhase.buffering)) {
        state = state.copyWith(listenedSec: state.listenedSec + 1);
      }
    });
  }

  late final Player _player;
  final String? Function()? _streamUrl;
  late final StreamSubscription<bool> _playingSubscription;
  late final StreamSubscription<bool> _bufferingSubscription;
  late final StreamSubscription<String> _errorSubscription;
  Timer? _stallTimer;
  Timer? _reconnectTimer;
  Timer? _listenTimer;
  String? _currentUrl;
  int _consecutiveFailures = 0;
  int _volumeRevision = 0;
  bool _disposed = false;
  bool get _useLocalRelay =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.linux);

  Future<void> _openRadio(String url, {required bool play}) async {
    var playbackUrl = url;
    if (_useLocalRelay) {
      try {
        playbackUrl = (await sharedRadioStream.activate(url)).toString();
      } catch (_) {
        // Playback remains available even if the optional local relay fails.
        sharedRadioStream.stop();
      }
    }
    await _player.open(Media(playbackUrl), play: play);
  }

  void _onPlaying(bool playing) {
    if (_disposed) return;
    // Windows SMTC:同步系统媒体面板状态
    unawaited(updateSystemMediaPlayback(
        playing: playing, stopped: !playing && _currentUrl == null));
    if (playing) {
      _stallTimer?.cancel();
      _consecutiveFailures = 0;
      state = state.copyWith(phase: PlaybackPhase.online, clearError: true);
    } else if (state.phase == PlaybackPhase.online && !state.userPaused) {
      // 流被中断(未手动暂停)→ 视为断线
      state = state.copyWith(phase: PlaybackPhase.buffering);
      _scheduleReconnect(const Duration(seconds: 3));
    }
  }

  void _onBuffering(bool buffering) {
    if (_disposed) return;
    if (!buffering) {
      _stallTimer?.cancel();
      if (state.phase == PlaybackPhase.buffering && _player.state.playing) {
        state = state.copyWith(phase: PlaybackPhase.online);
      }
      return;
    }
    if (state.phase == PlaybackPhase.online ||
        state.phase == PlaybackPhase.connecting) {
      state = state.copyWith(phase: PlaybackPhase.buffering);
      // waiting 持续 >5s → 重连
      _stallTimer?.cancel();
      _stallTimer = Timer(const Duration(seconds: 5), () {
        if (mounted &&
            (state.phase == PlaybackPhase.buffering ||
                state.phase == PlaybackPhase.connecting)) {
          _scheduleReconnect(const Duration(seconds: 3));
        }
      });
    }
  }

  void _onError(String message) {
    if (_disposed) return;
    if (state.userPaused || _currentUrl == null) return;
    state = state.copyWith(
        phase: PlaybackPhase.reconnecting,
        error: message.isEmpty ? null : message);
    _scheduleReconnect(const Duration(seconds: 1));
  }

  void _scheduleReconnect(Duration delay) {
    _reconnectTimer?.cancel();
    if (_currentUrl == null || state.userPaused) return;
    _consecutiveFailures++;
    if (_consecutiveFailures >= 5) {
      state = state.copyWith(
        phase: PlaybackPhase.idle,
        error: '连续重连失败,请稍后手动重试',
      );
      return;
    }
    _reconnectTimer = Timer(delay, () async {
      if (_disposed || _currentUrl == null || state.userPaused) return;
      state = state.copyWith(phase: PlaybackPhase.reconnecting);
      await _openRadio(_currentUrl!, play: true);
    });
  }

  /// 连接直播流(换码率 = 换地址重连,FLUTTER.md 4.2)。
  Future<void> tune(String url, {bool autoplay = true}) async {
    _currentUrl = url;
    _reconnectTimer?.cancel();
    _stallTimer?.cancel();
    _consecutiveFailures = 0;
    state = state.copyWith(
      phase: PlaybackPhase.connecting,
      userPaused: !autoplay,
      clearError: true,
    );
    await _openRadio(url, play: autoplay);
  }

  /// Switching a source preserves the live path, quality, token and pause state.
  Future<void> changeRadioSource(String baseUrl) async {
    final current = _currentUrl;
    if (current == null) return;
    final previous = Uri.parse(current);
    final base = Uri.parse(baseUrl);
    if (previous.origin == base.origin) return;
    final next = retargetRadioUrl(current, baseUrl);
    _currentUrl = next;
    if (state.userPaused) return;
    try {
      await tune(next);
    } catch (_) {
      if (!_disposed) _onError('切换播放源失败，正在尝试重新连接');
    }
  }

  /// 主播放键:未在播 → 连流;连接中/在播 → 暂停。(主面板与迷你窗共用)
  Future<void> toggle(String? streamUrl) async {
    switch (state.phase) {
      case PlaybackPhase.idle:
      case PlaybackPhase.reconnecting:
        if (streamUrl != null) await tune(streamUrl);
      case PlaybackPhase.connecting:
      case PlaybackPhase.buffering:
      case PlaybackPhase.online:
        await pause();
    }
  }

  Future<void> pause() async {
    state = state.copyWith(userPaused: true, phase: PlaybackPhase.idle);
    _reconnectTimer?.cancel();
    _stallTimer?.cancel();
    if (_useLocalRelay) {
      // Resume already opens the live edge again. Stop the local relay so a
      // paused player does not keep downloading radio audio.
      sharedRadioStream.stop();
      await _player.stop();
    } else {
      await _player.pause();
    }
  }

  Future<void> resume() async {
    if (_currentUrl == null) return;
    // 暂停过久的直播流应从头重连,拿到实时位置
    state = state.copyWith(
        userPaused: false, phase: PlaybackPhase.connecting, clearError: true);
    await _openRadio(_currentUrl!, play: true);
  }

  /// Media keys and lock-screen controls rejoin the current live edge.
  Future<void> playFromSystem() async {
    if (state.phase == PlaybackPhase.online ||
        state.phase == PlaybackPhase.connecting) {
      return;
    }
    if (_currentUrl != null) {
      await resume();
    } else {
      final url = _streamUrl?.call();
      if (url != null) await tune(url);
    }
  }

  Future<void> stop() async {
    _currentUrl = null;
    _reconnectTimer?.cancel();
    _stallTimer?.cancel();
    // stop 不重置音量(保持与持久化值、播放器实际音量一致)
    state = PlaybackState(
      volume: state.volume,
      lastAudibleVolume: state.lastAudibleVolume,
    );
    if (_useLocalRelay) sharedRadioStream.stop();
    await _player.stop();
    unawaited(updateSystemMediaPlayback(playing: false, stopped: true));
  }

  Future<void> setVolume(double value) async {
    final v = value.clamp(0.0, 100.0);
    _volumeRevision++;
    state = state.copyWith(volume: v);
    final lastAudibleVolume = state.lastAudibleVolume;
    await _player.setVolume(v);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('volume', v);
    await prefs.setDouble('last_audible_volume', lastAudibleVolume);
  }

  /// 启动时恢复上次音量;用户先于加载完成调过音量则放弃恢复。
  Future<void> _loadVolume() async {
    final prefs = await SharedPreferences.getInstance();
    final v = prefs.getDouble('volume');
    if (v == null || _volumeRevision != 0 || _disposed) return;
    final savedLast = prefs.getDouble('last_audible_volume');
    state = state.copyWith(
      volume: v,
      lastAudibleVolume:
          v > 0 ? v : (savedLast != null && savedLast > 0 ? savedLast : 100),
    );
    await _player.setVolume(v);
  }

  @override
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _stallTimer?.cancel();
    _listenTimer?.cancel();
    _playingSubscription.cancel();
    _bufferingSubscription.cancel();
    _errorSubscription.cancel();
    unregisterMediaControls();
    // 不 dispose 共享引擎(后台保活依赖它)
    super.dispose();
  }
}

final playbackProvider =
    StateNotifierProvider<PlaybackController, PlaybackState>((ref) {
  final controller =
      PlaybackController(streamUrl: () => ref.read(streamUrlProvider));
  ref.listen(radioSourceProvider.select((source) => source.selected.baseUrl),
      (_, next) => unawaited(controller.changeRadioSource(next)));
  return controller;
});
