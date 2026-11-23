import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:media_kit/media_kit.dart' show Media, Player;
import 'package:shared_preferences/shared_preferences.dart';

import '../state/channel_provider.dart';
import '../state/station_provider.dart';
import '../state/radio_source_provider.dart';
import 'audio_engine.dart';
import 'shared_radio_stream.dart';

/// 直播流从连接、播放到重连的状态。
enum PlaybackPhase { idle, connecting, online, buffering, reconnecting }

class PlaybackState {
  final PlaybackPhase phase;
  final bool userPaused; // 用户手动暂停 → 不自动恢复
  final double volume; // 0-100
  final double lastAudibleVolume; // 取消静音时恢复的音量
  final int listenedSec; // 本次会话累计秒数，暂停不计时，换曲仍延续。
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

/// 使用 media_kit 控制直播播放和断线恢复。
/// 单帧解码出错时先观察播放进度。直播中断后最多自动重连四次，实际播放后清零。
class PlaybackController extends StateNotifier<PlaybackState> {
  PlaybackController({String? Function()? streamUrl, Player? player})
      : _streamUrl = streamUrl,
        _player = player ?? enginePlayer,
        super(const PlaybackState()) {
    // 默认使用共享播放引擎，测试可注入 Player。
    _playingSubscription = _player.stream.playing.listen(_onPlaying);
    _bufferingSubscription = _player.stream.buffering.listen(_onBuffering);
    _positionSubscription = _player.stream.position.listen(_onPosition);
    _errorSubscription = _player.stream.error.listen(_onError);
    registerMediaControls(
      play: playFromSystem,
      pause: pause,
      stop: stop,
      volume: setVolume,
    );
    // 启动时恢复上次音量(shared_preferences,与设置项同一套方案)
    _loadVolume();
    // 在线或缓冲阶段累计收听时长，每秒加 1。
    _listenTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted &&
          (state.phase == PlaybackPhase.online ||
              state.phase == PlaybackPhase.buffering)) {
        state = state.copyWith(listenedSec: state.listenedSec + 1);
      }
    });
  }

  final Player _player;
  final String? Function()? _streamUrl;
  late final StreamSubscription<bool> _playingSubscription;
  late final StreamSubscription<bool> _bufferingSubscription;
  late final StreamSubscription<Duration> _positionSubscription;
  late final StreamSubscription<String> _errorSubscription;
  Timer? _stallTimer;
  Timer? _reconnectTimer;
  Timer? _decodeRecoveryTimer;
  Timer? _listenTimer;
  String? _currentUrl;
  bool _resumeAfterChannelChange = false;
  int _openRevision = 0;
  int _consecutiveFailures = 0;
  int _volumeRevision = 0;
  bool _disposed = false;
  bool get _canReconnect =>
      !_disposed &&
      _currentUrl != null &&
      !state.userPaused &&
      state.phase != PlaybackPhase.idle;

  bool get _useLocalRelay =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  Future<void> _openRadio(String url, {required bool play}) async {
    _cancelRecovery();
    final revision = ++_openRevision;
    var playbackUrl = url;
    if (_useLocalRelay) {
      try {
        playbackUrl = (await sharedRadioStream.activate(url)).toString();
      } catch (_) {
        // 本地中继启动失败时回退到上游原地址，以保留播放能力。
        sharedRadioStream.stop();
      }
    }
    // 等待中继期间，暂停、换台或停止可能已经使本次连接失效。
    if (_disposed || revision != _openRevision) return;
    await _player.open(Media(playbackUrl), play: play);
  }

  void _onPlaying(bool playing) {
    if (_disposed || (playing && !_canReconnect)) return;
    // 将播放状态同步到当前平台的系统媒体控件。
    unawaited(updateSystemMediaPlayback(
        playing: playing, stopped: !playing && _currentUrl == null));
    if (playing) {
      _stallTimer?.cancel();
      if (state.phase == PlaybackPhase.buffering) _reconnectTimer?.cancel();
      state = state.copyWith(phase: PlaybackPhase.online, clearError: true);
    } else if (state.phase == PlaybackPhase.online && !state.userPaused) {
      // 流被中断(未手动暂停)→ 视为断线
      state = state.copyWith(phase: PlaybackPhase.buffering);
      _scheduleReconnect(const Duration(seconds: 3));
    }
  }

  void _onBuffering(bool buffering) {
    if (!_canReconnect) return;
    if (!buffering) {
      _stallTimer?.cancel();
      if (state.phase == PlaybackPhase.buffering && _player.state.playing) {
        _reconnectTimer?.cancel();
        state = state.copyWith(phase: PlaybackPhase.online);
      }
      return;
    }
    if (state.phase == PlaybackPhase.online ||
        state.phase == PlaybackPhase.connecting) {
      state = state.copyWith(phase: PlaybackPhase.buffering);
      // 缓冲持续 5 秒后，安排在 3 秒后重连。
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

  void _onPosition(Duration position) {
    // 引擎在收到第一帧音频前就可能上报正在播放。
    if (_consecutiveFailures > 0 &&
        position > Duration.zero &&
        _canReconnect &&
        _player.state.playing) {
      _consecutiveFailures = 0;
    }
  }

  void _onError(String message) {
    if (!_canReconnect) return;
    if (message.trim() != 'Error decoding audio.') {
      _reconnectAfterError(message);
      return;
    }
    // 直播流中途的 ID3 标签或损坏单帧也会触发这条解码日志。
    if (_decodeRecoveryTimer?.isActive ?? false) return;
    final position = _player.state.position;
    _decodeRecoveryTimer = Timer(const Duration(seconds: 2), () {
      if (!_canReconnect) return;
      final player = _player.state;
      if (player.playing &&
          !player.completed &&
          player.position > Duration.zero &&
          player.position != position) {
        return;
      }
      _reconnectAfterError('音频流解码中断，正在重新连接…');
    });
  }

  void _reconnectAfterError(String message) {
    _decodeRecoveryTimer?.cancel();
    state = state.copyWith(
        phase: PlaybackPhase.reconnecting,
        error: message.isEmpty ? null : message);
    _scheduleReconnect(const Duration(seconds: 1));
  }

  void _scheduleReconnect(Duration delay) {
    if (!_canReconnect || (_reconnectTimer?.isActive ?? false)) return;
    if (_consecutiveFailures >= 4) {
      _openRevision++;
      _cancelRecovery();
      if (_useLocalRelay) sharedRadioStream.stop();
      unawaited(_player.stop().catchError((Object _) {}));
      state = state.copyWith(
        phase: PlaybackPhase.idle,
        error: '连续重连失败,请稍后手动重试',
      );
      return;
    }
    _reconnectTimer = Timer(delay, () async {
      if (!_canReconnect) return;
      final url = _currentUrl!;
      final previousRevision = _openRevision;
      state = state.copyWith(phase: PlaybackPhase.reconnecting);
      if (previousRevision != _openRevision) return;
      _consecutiveFailures++;
      final opening = _openRadio(url, play: true);
      final revision = _openRevision;
      try {
        await opening;
      } catch (_) {
        if (revision == _openRevision) _onError('直播流连接失败，正在重新连接…');
      }
    });
  }

  void _cancelRecovery() {
    _reconnectTimer?.cancel();
    _stallTimer?.cancel();
    _decodeRecoveryTimer?.cancel();
  }

  /// 连接直播流，换码率时使用新流地址重新连接。
  Future<void> tune(String url, {bool autoplay = true}) async {
    _resumeAfterChannelChange = false;
    _currentUrl = url;
    _consecutiveFailures = 0;
    state = state.copyWith(
      phase: PlaybackPhase.connecting,
      userPaused: !autoplay,
      clearError: true,
    );
    await _openRadio(url, play: autoplay);
  }

  /// 等待新频道的直播流配置期间，停止播放旧频道。
  Future<void> switchStation() async {
    final hadStream = _currentUrl != null;
    _resumeAfterChannelChange = !state.userPaused &&
        (_resumeAfterChannelChange ||
            (hadStream && state.phase != PlaybackPhase.idle));
    _currentUrl = null;
    _openRevision++;
    _cancelRecovery();
    state = state.copyWith(
      phase: _resumeAfterChannelChange
          ? PlaybackPhase.connecting
          : PlaybackPhase.idle,
      clearError: true,
    );
    if (hadStream) {
      if (_useLocalRelay) sharedRadioStream.stop();
      await _player.stop();
    }
  }

  /// 更新频道的直播流地址，仅在原本有播放意图时重连。
  Future<void> updateStreamUrl(String url) async {
    if (url == _currentUrl) return;
    if (_resumeAfterChannelChange ||
        (_currentUrl != null &&
            !state.userPaused &&
            state.phase != PlaybackPhase.idle)) {
      await _retune(url, '切换直播流失败，正在尝试重新连接');
    } else if (_currentUrl != null) {
      _currentUrl = url;
    }
  }

  /// 切换播放源时保留直播路径、码率档位、token 和暂停状态。
  Future<void> changeRadioSource(String baseUrl) async {
    final current = _currentUrl;
    if (current == null) return;
    final previous = Uri.parse(current);
    final base = Uri.parse(baseUrl);
    if (previous.origin == base.origin) return;
    final next = retargetRadioUrl(current, baseUrl);
    _currentUrl = next;
    if (state.userPaused) return;
    await _retune(next, '切换播放源失败，正在尝试重新连接');
  }

  Future<void> _retune(String url, String failureMessage) async {
    try {
      await tune(url);
    } catch (_) {
      if (!_disposed && _currentUrl == url) _onError(failureMessage);
    }
  }

  /// 收听面板和迷你窗共用主播放键。空闲或重连中重新连流，连接、缓冲或播放中则暂停。
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
    _resumeAfterChannelChange = false;
    _openRevision++;
    state = state.copyWith(
        userPaused: true, phase: PlaybackPhase.idle, clearError: true);
    _cancelRecovery();
    if (_useLocalRelay) {
      // 恢复播放会重新连接实时位置。暂停时关闭本地中继，避免继续下载直播音频。
      sharedRadioStream.stop();
      await _player.stop();
    } else {
      await _player.pause();
    }
  }

  Future<void> resume() async {
    if (_currentUrl == null) return;
    // 从当前直播位置重新连流，跳过暂停期间积压的内容。
    _consecutiveFailures = 0;
    state = state.copyWith(
        userPaused: false, phase: PlaybackPhase.connecting, clearError: true);
    await _openRadio(_currentUrl!, play: true);
  }

  /// 媒体键和锁屏上的播放操作从当前直播位置开始。
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
    _resumeAfterChannelChange = false;
    _openRevision++;
    _currentUrl = null;
    _cancelRecovery();
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
    _cancelRecovery();
    _listenTimer?.cancel();
    _playingSubscription.cancel();
    _bufferingSubscription.cancel();
    _positionSubscription.cancel();
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
  ref.listen(activeStationIdProvider, (_, __) {
    audioHandler.clearNowPlaying();
    unawaited(clearSystemMediaMetadata());
    unawaited(controller.switchStation());
  });
  ref.listen(radioSourceProvider.select((source) => source.selected.baseUrl),
      (_, next) => unawaited(controller.changeRadioSource(next)));
  ref.listen(streamUrlProvider, (_, next) {
    if (next != null) unawaited(controller.updateStreamUrl(next));
  });
  return controller;
});
