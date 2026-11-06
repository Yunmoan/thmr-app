// In-window bottom dock player bar, shown when not on the Listen tab.
// Mirrors the web dock bar: cover / title / bitrate / play / volume / open.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config.dart';
import '../../core/player/playback_controller.dart';
import '../../core/state/settings_provider.dart';
import '../../core/state/station_provider.dart';
import '../../core/theme/thmr_theme.dart';
import 'track_cover.dart';
import 'volume_slider.dart';
import 'volume_wheel_control.dart';

/// 非收听页时的窗口底部播放条(参照 Web 端 dock bar)。
/// compact = 窄屏/移动端:省略音量滑杆与码率选择。
class PlayerDockBar extends ConsumerWidget {
  const PlayerDockBar({super.key, this.compact = false, this.onOpenPlayer});

  final bool compact;

  /// 「打开播放器」→ 跳回收听页(由 HomeShell 注入切页回调)。
  final VoidCallback? onOpenPlayer;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).thmr;
    final status = ref.watch(stationProvider.select((s) => s.status));
    final cur = status?.current;

    return Container(
      decoration: BoxDecoration(
        color: tokens.solidPanel,
        border: Border(top: BorderSide(color: tokens.panelBorder)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
      child: Row(
        children: [
          TrackCover(url: cur?.coverUrl ?? '', size: 44, radius: 6),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  cur?.title ?? '暂无播放',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700, height: 1.25),
                ),
                Text(
                  cur?.artist ?? '等待下一首',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: tokens.mutedInk),
                ),
              ],
            ),
          ),
          if (!compact) ...[
            const SizedBox(width: 12),
            const _DockBitrate(),
            const SizedBox(width: 10),
            const _DockPlayButton(),
            const SizedBox(width: 10),
            const _DockVolume(),
            const SizedBox(width: 12),
          ],
          if (compact) ...[
            const SizedBox(width: 10),
            const _DockPlayButton(),
            const SizedBox(width: 10),
          ],
          OutlinedButton.icon(
            onPressed: onOpenPlayer,
            icon: const Icon(Icons.open_in_new_rounded, size: 15),
            label: const Text('打开播放器'),
          ),
        ],
      ),
    );
  }
}

/// 播放/暂停(窄订阅:仅相位变化时重建)。
class _DockPlayButton extends ConsumerWidget {
  const _DockPlayButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final accent = Theme.of(context).colorScheme.primary;
    final onAccent = Theme.of(context).thmr.onAccent;
    final phase = ref.watch(playbackProvider.select((s) => s.phase));
    final busy = phase == PlaybackPhase.connecting ||
        phase == PlaybackPhase.reconnecting;
    final playing =
        phase == PlaybackPhase.online || phase == PlaybackPhase.buffering;

    return SizedBox(
      width: 36,
      height: 36,
      child: Material(
        color: accent,
        borderRadius: BorderRadius.circular(999),
        child: InkWell(
          borderRadius: BorderRadius.circular(999),
          onTap: () {
            final url = ref.read(streamUrlProvider);
            ref.read(playbackProvider.notifier).toggle(url);
          },
          child: Center(
            child: busy
                ? SizedBox(
                    width: 15,
                    height: 15,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: onAccent),
                  )
                : Icon(
                    playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    size: 22,
                    color: onAccent,
                  ),
          ),
        ),
      ),
    );
  }
}

/// 音量:静音图标 + 紧凑滑杆(拖动中用临时值防抖)。
class _DockVolume extends ConsumerStatefulWidget {
  const _DockVolume();

  @override
  ConsumerState<_DockVolume> createState() => _DockVolumeState();
}

class _DockVolumeState extends ConsumerState<_DockVolume> {
  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    final volume = ref.watch(playbackProvider.select((s) => s.volume));
    final shown = volume;
    final muted = shown <= 0;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        VolumeWheelControl(
          value: shown,
          onChanged: (v) => ref.read(playbackProvider.notifier).setVolume(v),
          child: IconButton(
            visualDensity: VisualDensity.compact,
            icon: Icon(
              muted
                  ? Icons.volume_off_rounded
                  : shown < 50
                      ? Icons.volume_down_rounded
                      : Icons.volume_up_rounded,
              size: 18,
              color: tokens.mutedInk,
            ),
            onPressed: () {
              final pb = ref.read(playbackProvider);
              ref
                  .read(playbackProvider.notifier)
                  .setVolume(pb.volumeAfterMuteToggle);
            },
          ),
        ),
        SizedBox(
          width: 120,
          child: VolumeSlider(
            value: shown,
            onChanged: (v) => ref.read(playbackProvider.notifier).setVolume(v),
          ),
        ),
      ],
    );
  }
}

/// 码率选择:弹出菜单,选择后按需重连当前流。
class _DockBitrate extends ConsumerWidget {
  const _DockBitrate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).thmr;
    final accent = Theme.of(context).colorScheme.primary;
    final station = ref.watch(stationProvider);
    final settings = ref.watch(settingsProvider);
    final profiles = station.status?.station.enabledBitrates ?? const [];
    if (profiles.length < 2) return const SizedBox.shrink();
    final selected =
        station.selectedProfile(settings.bitrateFor(appConfig.stationId));

    return PopupMenuButton<String>(
      position: PopupMenuPosition.over,
      onSelected: (id) => _switchTo(ref, id),
      itemBuilder: (menuContext) => [
        for (final p in profiles)
          PopupMenuItem(
            value: p.id,
            child: Text(
              p.label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: p.id == selected.id ? accent : tokens.ink,
                    fontWeight: p.id == selected.id ? FontWeight.w700 : null,
                  ),
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: tokens.fieldBg,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: tokens.panelBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              selected.label,
              style: Theme.of(context)
                  .textTheme
                  .labelMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
            const Icon(Icons.arrow_drop_down_rounded, size: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _switchTo(WidgetRef ref, String profileId) async {
    await ref
        .read(settingsProvider.notifier)
        .setBitrate(appConfig.stationId, profileId);
    // 正在播放 → 立即切到新流继续放送
    final pb = ref.read(playbackProvider);
    if (pb.phase == PlaybackPhase.online ||
        pb.phase == PlaybackPhase.buffering ||
        pb.phase == PlaybackPhase.connecting) {
      final url = ref.read(streamUrlProvider);
      if (url != null) {
        await ref.read(playbackProvider.notifier).tune(url);
      }
    }
  }
}
