import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../player/audio_engine.dart';
import '../api/radio_api.dart';
import '../models/models.dart';
import 'channel_provider.dart';
import 'settings_provider.dart';
import 'radio_source_provider.dart';

/// 电台运行时 UI 状态。
class StationUiState {
  final StationStatus? status;
  final Object? error;
  final bool initialLoading;

  /// current.trackId 或 startedAtMs 变化时递增，促使投票和收藏状态同步刷新。
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

  /// 优先选用仍可用的偏好档位，其次用首个启用的档位。无可用档位时生成 128 kbps 的默认档位。
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

/// 每 10 秒轮询一次。若预计结束时间合理，则额外在 expectedEndMs 后 800 毫秒刷新。
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
      // 定时轮询与手动刷新可以并发。迟到的旧响应不能覆盖已应用的新快照。
      if (!mounted || requestId < _lastAppliedRequestId) return;
      _lastAppliedRequestId = requestId;
      var generation = state.trackGeneration;
      final cur = s.current;
      if (cur?.trackId != _lastTrackId ||
          cur?.startedAtMs != _lastStartedAtMs) {
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
        final artwork = absolutizeCover(cur.coverUrl, _api.baseUrl);
        // 桌面媒体面板和移动端锁屏使用同一条曲目信息。
        unawaited(updateSystemMediaMetadata(
            trackId: '${cur.trackId}-${cur.startedAtMs}',
            title: cur.title,
            artist: cur.artist,
            artUri: artwork,
            positionSec: cur.positionSec,
            durationSec: cur.durationSec));
        audioHandler.updateNowPlaying(
            trackId: cur.trackId,
            startedAtMs: cur.startedAtMs,
            title: cur.title,
            artist: cur.artist,
            artUri: artwork,
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
  (ref) => StationPoller(
    ref.watch(radioApiProvider),
    ref.watch(activeStationIdProvider),
  ),
);

/// 收到当前频道的状态后，按码率偏好生成完整的直播流 URL。手动播放可先用暂定来源，
/// 自动连播会等测速完成。
final streamUrlProvider = Provider<String?>((ref) {
  final stationId = ref.watch(activeStationIdProvider);
  final st = ref.watch(stationProvider);
  if (st.status?.station.id != stationId) return null;
  final preferred =
      ref.watch(settingsProvider.select((s) => s.bitrateFor(stationId)));
  final profile = st.selectedProfile(preferred);
  // radioApiProvider 跟随所选播放源，切换来源时会重新生成直播流地址。
  return ref.watch(radioApiProvider).streamUrl(stationId, profile.id);
});
