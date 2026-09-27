import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config.dart';
import '../../../core/player/playback_controller.dart';
import '../../../core/state/settings_provider.dart';
import '../../../core/state/station_provider.dart';
import '../../../core/theme/thmr_theme.dart';

/// 码率选择 chips(4.2):换 profileId = 换流地址重连,正在播放则切完继续。
class BitrateRow extends ConsumerWidget {
  const BitrateRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final station = ref.watch(stationProvider);
    final settings = ref.watch(settingsProvider);
    final status = station.status;
    final profiles = status?.station.enabledBitrates ?? const [];
    if (profiles.length < 2) return const SizedBox.shrink();

    final selected = station.selectedProfile(settings.bitrateFor(appConfig.stationId));

    return Wrap(
      spacing: 8,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 2),
          child: Text(
            '音质',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).thmr.mutedInk,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        for (final p in profiles)
          ChoiceChip(
            label: Text(p.label),
            selected: p.id == selected.id,
            onSelected: (_) => _switchTo(ref, context, p.id),
          ),
        // Low-key copy-stream-link action
        IconButton(
          tooltip: '复制收听链接(当前码率的流地址)',
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.link_rounded,
              size: 18, color: Theme.of(context).thmr.mutedInk),
          onPressed: () {
            final url = ref.read(streamUrlProvider);
            if (url == null) return;
            Clipboard.setData(ClipboardData(text: url));
            ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('收听链接已复制')));
          },
        ),
      ],
    );
  }

  Future<void> _switchTo(WidgetRef ref, BuildContext context, String profileId) async {
    await ref.read(settingsProvider.notifier).setBitrate(appConfig.stationId, profileId);
    // 正在播放 → 立即切换到新流继续放送
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
