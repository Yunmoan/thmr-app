import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player/audio_engine.dart';
import '../api/radio_api.dart';
import '../config.dart';
import '../models/models.dart';
import 'settings_provider.dart';

/// 电台运行时 UI 状态。
class StationUiState {
  final StationStatus? status;
  final Object? error;
  final bool initialLoading;

  /// 换曲计数:`current.trackId` 或 `startedAtMs` 变化时 +1,
  /// 驱动收藏状态 / 投票轮次等跟随刷新。
  final int trackGeneration;

  /// 最近一次成功轮询时间(展示「更新于 …」)。
  final DateTime? updatedAt;

  const StationUiState({
    this.status,
    this.error,
    this.initialLoading = true,
    this.trackGeneration = 0,
    this.updatedAt,
  });

  StationUiState copyWith({
    StationStatus? status,
    Object? error,
    bool clearError = false,
    bool? initialLoading,
    int? trackGeneration,
    DateTime? updatedAt,
  }) =>
      StationUiState(
        status: status ?? this.status,
        error: clearError ? null : (error ?? this.error),
        initialLoading: initialLoading ?? this.initialLoading,
        trackGeneration: trackGeneration ?? this.trackGeneration,
        updatedAt: updatedAt ?? this.updatedAt,
      );

  /// 当前码率档(用户偏好或默认第一个)。
  StreamProfile selectedProfile(String preferredId) {
    final list = status?.station.enabledBitrates ?? const [];
    if (list.isEmpty) {
      return const StreamProfile(
          id: '128k',
          bitrateKbps: 128,
          sampleRate: 44100,
          channels: 2,
          enabled: true);
    }
    for (final p in list) {
      if (p.id == preferredId) return p;
    }
    return list.first;
  }
}

/// 双定时器轮询(FLUTTER.md 4.3):
/// 常规 10s 一次;拿到 expectedEndMs 后在换曲时刻 +800ms 精准再刷。
class StationPoller extends StateNotifier<StationUiState> {
  StationPoller(this._api, this._stationId) : super(const StationUiState()) {
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) => _poll());
  }

  final RadioApi _api;
  final String _stationId;
  late final Timer _timer;
  Timer? _endTimer;
  String? _lastTrackId;
  int? _lastStartedAtMs;
  (String, int, String, String, String)? _lastMediaSignature;
  int _requestId = 0;
  int _lastAppliedRequestId = 0;

  Future<void> _poll() async {
    final requestId = ++_requestId;
    try {
      final s = await _api.status(_stationId);
      if (!mounted || requestId < _lastAppliedRequestId) return;
      _lastAppliedRequestId = requestId;
      var generation = state.trackGeneration;
      final cur = s.current;
      if (cur != null &&
          (cur.trackId != _lastTrackId ||
              cur.startedAtMs != _lastStartedAtMs)) {
        generation++;
      }
      final mediaSignature = cur == null
          ? null
          : (cur.trackId, cur.startedAtMs, cur.title, cur.artist, cur.coverUrl);
      final mediaChanged = mediaSignature != _lastMediaSignature;
      _lastMediaSignature = mediaSignature;
      _lastTrackId = cur?.trackId;
      _lastStartedAtMs = cur?.startedAtMs;
      if (cur == null && mediaChanged) {
        unawaited(clearSystemMediaMetadata());
        audioHandler.clearNowPlaying();
      } else if (cur != null && mediaChanged) {
        // Windows SMTC and mobile lock-screen metadata share the same track.
        unawaited(updateSystemMediaMetadata(
            trackId: '${cur.trackId}-${cur.startedAtMs}',
            title: cur.title,
            artist: cur.artist,
            artUri: cur.coverUrl,
            positionSec: cur.positionSec,
            durationSec: cur.durationSec));
        audioHandler.updateNowPlaying(
            trackId: cur.trackId,
            startedAtMs: cur.startedAtMs,
            title: cur.title,
            artist: cur.artist,
            artUri: cur.coverUrl,
            durationSec: cur.durationSec);
      } else if (cur != null) {
        unawaited(updateSystemMediaTimeline(
            positionSec: cur.positionSec, durationSec: cur.durationSec));
      }
      if (cur != null) {
        audioHandler.updatePosition(cur.positionSec);
      }
      state = state.copyWith(
          status: s,
          clearError: true,
          initialLoading: false,
          trackGeneration: generation,
          updatedAt: DateTime.now());
      _scheduleEndRefresh(cur?.expectedEndMs);
    } catch (e) {
      if (!mounted || requestId < _lastAppliedRequestId) return;
      state = state.copyWith(error: e, initialLoading: false);
    }
  }

  void _scheduleEndRefresh(int? expectedEndMs) {
    _endTimer?.cancel();
    if (expectedEndMs == null || expectedEndMs <= 0) return;
    final delay = expectedEndMs - DateTime.now().millisecondsSinceEpoch + 800;
    if (delay <= 0 || delay > const Duration(minutes: 30).inMilliseconds) {
      return;
    }
    _endTimer = Timer(Duration(milliseconds: delay), _poll);
  }

  /// 用户主动刷新(下拉等)。
  Future<void> refresh() => _poll();

  @override
  void dispose() {
    _timer.cancel();
    _endTimer?.cancel();
    super.dispose();
  }
}

final stationProvider = StateNotifierProvider<StationPoller, StationUiState>(
  (ref) => StationPoller(RadioApi(), appConfig.stationId),
);

/// 直播流地址:状态接口可用 + 用户码率偏好 → 完整 URL。
final streamUrlProvider = Provider<String?>((ref) {
  final st = ref.watch(stationProvider);
  final status = st.status;
  if (status == null) return null;
  final prefs = ref.watch(settingsProvider);
  final profile = st.selectedProfile(prefs.bitrateFor(appConfig.stationId));
  return RadioApi().streamUrl(appConfig.stationId, profile.id);
});
