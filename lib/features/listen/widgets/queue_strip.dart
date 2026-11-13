// Mobile queue strip: horizontal cards; tap opens the detail sheet.

import 'package:flutter/material.dart';

import '../../../shared/widgets/focus_outline.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/thmr_theme.dart';
import '../../../shared/widgets/track_cover.dart';
import 'side_info_column.dart' show showQueueSheet;

/// Estimated air time for a queue entry (backend schedule or null).
String? queuePlannedHHmm(QueueEntry e) {
  if (e.plannedStartMs <= 0) return null;
  final t = DateTime.fromMillisecondsSinceEpoch(e.plannedStartMs);
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// Secondary detail sheet for a queue entry (shared by strip & queue page).
void showQueueEntryDetail(BuildContext context, QueueEntry entry, int index,
    {String? heading,
    String? album,
    String? playbackLabel,
    String? durationLabel}) {
  final tokens = Theme.of(context).thmr;
  final planned = queuePlannedHHmm(entry);
  final duration = durationLabel ?? '时长 ${formatDuration(entry.durationSec)}';
  final wide = MediaQuery.of(context).size.width >= 720;
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    constraints: BoxConstraints(maxWidth: wide ? 480 : double.infinity),
    builder: (_) => SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: entry.coverUrl.isEmpty
                      ? Image.asset('assets/brand/cover-fallback.png',
                          width: 180, fit: BoxFit.cover)
                      : Image.network(entry.coverUrl,
                          width: 180, fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 14),
              Text(heading ?? '队列 #${index + 1}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        letterSpacing: 2,
                        fontWeight: FontWeight.w700,
                      )),
              const SizedBox(height: 6),
              Text(entry.title,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              Text(entry.artist,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(color: tokens.mutedInk)),
              if (album != null && album.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(album,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: tokens.mutedInk)),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.schedule_rounded,
                      size: 15, color: tokens.mutedInk),
                  const SizedBox(width: 6),
                  Flexible(
                      child: Text(
                    playbackLabel != null
                        ? '$duration · $playbackLabel'
                        : planned == null
                            ? duration
                            : '$duration · 预计 $planned 播放',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: tokens.mutedInk),
                  )),
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 「接下来」队列 — 横向卡片,高度对齐 Web 端 92px 队列卡。
class QueueStrip extends StatelessWidget {
  const QueueStrip({super.key, required this.status});

  final StationStatus status;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    final queue = status.queue;
    if (queue.isEmpty) {
      return Container(
        height: 92,
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
        SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: queue.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, i) {
              final e = queue[i];
              return _QueueCard(entry: e, index: i);
            },
          ),
        ),
        const SizedBox(height: 2),
        Center(
          child: TextButton.icon(
            onPressed: () => showQueueSheet(context, status: status),
            icon: const Icon(Icons.unfold_more_rounded, size: 16),
            label: Text('查看全部 ${queue.length} 首'),
          ),
        ),
      ],
    );
  }
}

class _QueueCard extends StatelessWidget {
  const _QueueCard({required this.entry, required this.index});

  final QueueEntry entry;
  final int index;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    return FocusOutline(
        radius: 10,
        child: InkWell(
          onTap: () => showQueueEntryDetail(context, entry, index),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            width: 264,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: tokens.panelBg.withValues(alpha: 0.82),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: tokens.panelBorder),
            ),
            child: Row(
              children: [
                TrackCover(url: entry.coverUrl, size: 72, radius: 8),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Text(
                            '#${index + 1}',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w800,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              entry.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleSmall
                                  ?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: tokens.ink),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        entry.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: tokens.mutedInk),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        plannedLabel(entry, index),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: tokens.mutedInk,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ));
  }
}

/// Duration plus scheduled air time when available.
String plannedLabel(QueueEntry entry, int index) {
  final planned = queuePlannedHHmm(entry);
  return planned == null
      ? formatDuration(entry.durationSec)
      : '${formatDuration(entry.durationSec)} · 预计 $planned';
}
