import 'package:flutter/material.dart';
import '../../../core/theme/thmr_motion.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../shared/widgets/focus_outline.dart';
import '../../../core/models/models.dart';
import '../../../core/state/settings_provider.dart';
import '../../../core/state/station_provider.dart';
import '../../../core/theme/thmr_theme.dart';

/// 选择不同 profileId 时更新直播地址。若正在播放，使用新码率重连。
class BitrateRow extends ConsumerWidget {
  const BitrateRow({super.key, this.status});

  final StationStatus? status;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final station = status == null
        ? ref.watch(stationProvider)
        : StationUiState(status: status);
    final settings = ref.watch(settingsProvider);
    final displayed = station.status;
    final profiles = displayed?.station.enabledBitrates ?? const [];
    if (profiles.isEmpty) return const SizedBox.shrink();

    final stationId = displayed!.station.id;
    final selected = station.selectedProfile(settings.bitrateFor(stationId));

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
          FocusOutline(
              radius: 999,
              focusBounds: true,
              child: ChoiceChip(
                label: Text(p.label),
                selected: p.id == selected.id,
                onSelected: (selected) {
                  if (selected) {
                    ref
                        .read(settingsProvider.notifier)
                        .setBitrate(stationId, p.id);
                  }
                },
              )),
        // 码率选项旁提供复制直播链接的入口。
        IconButton(
          tooltip: '复制收听链接(当前码率的流地址)',
          visualDensity: VisualDensity.compact,
          icon: Icon(Icons.link_rounded,
              size: 18, color: Theme.of(context).thmr.mutedInk),
          onPressed: () {
            final url = ref.read(streamUrlProvider);
            if (url == null) return;
            Clipboard.setData(ClipboardData(text: url));
            ScaffoldMessenger.of(context).showThmrSnackBar(
                context, const SnackBar(content: Text('收听链接已复制')));
          },
        ),
      ],
    );
  }
}
