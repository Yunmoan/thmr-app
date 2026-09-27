// Right column for wide layouts: previous track / stream state / queue list.
// Mirrors web "过去与未来" (StatusPanel) + queue.

import 'package:flutter/material.dart';

import '../../../core/models/models.dart';
import '../../../core/theme/thmr_theme.dart';
import '../../../shared/widgets/thmr_panel.dart';
import '../../../shared/widgets/track_cover.dart';
import 'queue_strip.dart' show showQueueEntryDetail, queuePlannedHHmm;

class SideInfoColumn extends StatelessWidget {
  const SideInfoColumn({super.key, required this.status, this.updatedAt});

  final StationStatus status;
  final DateTime? updatedAt;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    final prev = status.previous;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader(title: '过去与未来'),
        ThmrPanel(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '上一首',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: tokens.mutedInk,
                      letterSpacing: 2,
                    ),
              ),
              const SizedBox(height: 8),
              if (prev != null)
                Row(
                  children: [
                    TrackCover(url: prev.coverUrl, size: 40, radius: 6),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            prev.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: tokens.ink),
                          ),
                          Text(
                            prev.artist,
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
                  ],
                )
              else
                Text(
                  '暂无上一首',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: tokens.mutedInk),
                ),
              const SizedBox(height: 12),
              Divider(color: tokens.panelBorder),
              const SizedBox(height: 10),
              Row(
                children: [
                  Text(
                    '流状态',
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: tokens.mutedInk),
                  ),
                  const Spacer(),
                  Text(
                    status.station.enabled ? '放送中' : '待机',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: status.station.enabled
                              ? Theme.of(context).colorScheme.primary
                              : tokens.mutedInk,
                        ),
                  ),
                ],
              ),
              if (updatedAt != null) ...[
                const SizedBox(height: 6),
                Text(
                  '更新于 ${updatedAt!.hour.toString().padLeft(2, '0')}:'
                  '${updatedAt!.minute.toString().padLeft(2, '0')}:'
                  '${updatedAt!.second.toString().padLeft(2, '0')}',
                  style: Theme.of(context)
                      .textTheme
                      .labelSmall
                      ?.copyWith(color: tokens.mutedInk),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        SectionHeader(
          title: '接下来',
          trailing: Text(
            '队列 ${status.queue.length} 首',
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: tokens.mutedInk),
          ),
        ),
        Expanded(
          child: _QueueList(status: status),
        ),
      ],
    );
  }
}

class _QueueList extends StatelessWidget {
  const _QueueList({required this.status});

  final StationStatus status;

  List<QueueEntry> get queue => status.queue;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    if (queue.isEmpty) {
      return Container(
        clipBehavior: Clip.antiAlias,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tokens.panelSoft,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: tokens.panelBorder),
        ),
        child: Text(
          '队列暂无曲目 · 尽情期待',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: tokens.mutedInk),
        ),
      );
    }
    return Column(
      children: [
        Expanded(
          child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: tokens.panelBg.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: tokens.panelBorder),
            ),
            child: ShaderMask(
              shaderCallback: (rect) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.white, Colors.white, Colors.transparent],
                stops: [0, 0.93, 1],
              ).createShader(rect),
              blendMode: BlendMode.dstIn,
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(0, 8, 0, 24),
                itemCount: queue.length,
                separatorBuilder: (_, __) => Divider(
                  color: tokens.panelBorder,
                  height: 1,
                  indent: 58,
                  endIndent: 12,
                ),
                itemBuilder: (context, i) {
                  final e = queue[i];
                  return InkWell(
                    onTap: () => showQueueEntryDetail(context, e, i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 7),
                      child: Row(
                        children: [
                          TrackCover(url: e.coverUrl, size: 40, radius: 6),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      '#${i + 1}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        fontWeight: FontWeight.w800,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures()
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        e.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                                color: tokens.ink),
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  e.artist,
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
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                formatDuration(e.durationSec),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                  color: tokens.mutedInk,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                              if (queuePlannedHHmm(e) != null)
                                Text(
                                  '预计 ${queuePlannedHHmm(e)}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(color: tokens.mutedInk),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => showQueueSheet(context, status: status),
              icon: const Icon(Icons.unfold_more_rounded, size: 17),
              label: Text('查看全部 ${queue.length} 首'),
            ),
          ),
        ),
      ],
    );
  }
}

/// Half-screen queue drawer (expand action from the side column / mobile).
Future<void> showQueueSheet(BuildContext context,
    {required StationStatus status}) {
  final size = MediaQuery.of(context).size;
  return showModalBottomSheet<void>(
    context: context,
    useSafeArea: true,
    isScrollControlled: true,
    constraints: BoxConstraints(
      maxHeight: size.height * 0.85,
      maxWidth: size.width >= 720 ? 620 : double.infinity,
    ),
    builder: (_) => QueueSheet(status: status),
  );
}

class QueueSheet extends StatelessWidget {
  const QueueSheet({super.key, required this.status});

  final StationStatus status;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    final cur = status.current;
    final queue = status.queue;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.85,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text('队列 · ${queue.length} 首',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                ThmrPanel(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      TrackCover(url: cur?.coverUrl ?? '', size: 52, radius: 8),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '正在放送',
                              style: Theme.of(context)
                                  .textTheme
                                  .labelSmall
                                  ?.copyWith(
                                      color: tokens.mutedInk, letterSpacing: 2),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              cur?.title ?? '等待下一首曲目…',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: tokens.ink),
                            ),
                            if (cur != null)
                              Text(
                                cur.artist,
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
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Padding(
                  padding: const EdgeInsets.only(left: 4, bottom: 8),
                  child: Text(
                    '接下来 · 预计排程',
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: tokens.mutedInk,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                for (var i = 0; i < queue.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: ThmrPanel(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 9),
                      // 列表行不用毛玻璃:每行一个 BackdropFilter 会拖垮 GPU
                      frost: false,
                      onTap: () => showQueueEntryDetail(context, queue[i], i),
                      child: Row(
                        children: [
                          TrackCover(
                              url: queue[i].coverUrl, size: 44, radius: 6),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      '#${i + 1}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .primary,
                                        fontWeight: FontWeight.w800,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures()
                                        ],
                                      ),
                                    ),
                                    if (i == 0) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 6, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: tokens.accentSoft,
                                          borderRadius:
                                              BorderRadius.circular(999),
                                        ),
                                        child: Text(
                                          '下一首',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primary,
                                                fontWeight: FontWeight.w700,
                                              ),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        queue[i].title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodyMedium
                                            ?.copyWith(
                                                fontWeight: FontWeight.w600,
                                                color: tokens.ink),
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  queue[i].artist,
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
                          const SizedBox(width: 8),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                formatDuration(queue[i].durationSec),
                                style: Theme.of(context)
                                    .textTheme
                                    .labelSmall
                                    ?.copyWith(
                                  color: tokens.mutedInk,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                              if (queuePlannedHHmm(queue[i]) != null)
                                Text(
                                  '预计 ${queuePlannedHHmm(queue[i])}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(color: tokens.mutedInk),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
