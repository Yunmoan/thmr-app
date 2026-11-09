import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/state/radio_source_provider.dart';
import '../../core/state/settings_provider.dart';
import '../../core/theme/thmr_theme.dart';
import '../../shared/widgets/thmr_panel.dart';

class RadioSourcePanel extends ConsumerWidget {
  const RadioSourcePanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final source = ref.watch(radioSourceProvider);
    final preference =
        ref.watch(settingsProvider.select((value) => value.radioSource));
    final tokens = Theme.of(context).thmr;
    return ThmrPanel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(Icons.cell_tower_rounded, color: tokens.mutedInk, size: 21),
          const SizedBox(width: 10),
          Expanded(
              child:
                  Text('播放源', style: Theme.of(context).textTheme.titleSmall)),
          TextButton.icon(
            onPressed: source.testing
                ? null
                : () => ref.read(radioSourceProvider.notifier).testSources(),
            icon: const Icon(Icons.speed_rounded, size: 18),
            label: Text(source.testing ? '测速中' : '重新测速'),
          ),
        ]),
        const SizedBox(height: 4),
        Text('自动比较最优播放源，优先使用更快的可用来源。',
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: tokens.mutedInk)),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final choice in RadioSourcePreference.values)
            ChoiceChip(
              label: Text(choice.label),
              selected: preference == choice,
              onSelected: (_) =>
                  ref.read(settingsProvider.notifier).setRadioSource(choice),
            ),
        ]),
        const SizedBox(height: 12),
        if (source.testing) ...[
          const LinearProgressIndicator(),
          const SizedBox(height: 10),
        ],
        Text(
            source.ready
                ? '当前使用：${source.selected.label} · ${Uri.parse(source.selected.baseUrl).host}'
                : source.testing
                    ? '正在读取少量音频数据，比较最优连接…'
                    : '首次连接前自动测速',
            style: Theme.of(context).textTheme.bodySmall),
        if (source.measurements.isNotEmpty) ...[
          const SizedBox(height: 8),
          Wrap(spacing: 16, runSpacing: 6, children: [
            for (final measurement in source.measurements)
              Text(
                  '${measurement.source.label}：${measurement.usable ? '${measurement.probe.elapsed.inMilliseconds} ms' : '测速未成功'}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: tokens.mutedInk)),
          ]),
          const SizedBox(height: 4),
          Text('耗时为连接并读取 32 KiB 音频的总时间。手动选择时，测速不会更改来源。',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: tokens.mutedInk)),
        ],
        if (source.notice != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(source.notice!,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: tokens.mutedInk)),
          ),
      ]),
    );
  }
}
