// 移动端以横向卡片显示队列，点击卡片打开详情弹层。

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/thmr_motion.dart';

import '../../../shared/widgets/horizontal_wheel_scroll.dart';
import '../../../shared/widgets/thmr_panel.dart';
import '../../../core/models/models.dart';
import '../../../core/theme/thmr_theme.dart';
import '../../../shared/widgets/track_cover.dart';
import 'side_info_column.dart' show showQueueSheet;

/// 播放队列条目的预计播出时间。后端未提供时返回 null。
String? queuePlannedHHmm(QueueEntry e) {
  if (e.plannedStartMs <= 0) return null;
  final t = DateTime.fromMillisecondsSinceEpoch(e.plannedStartMs);
  return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// 横向队列和队列页面共用的条目详情弹层。
void showQueueEntryDetail(BuildContext context, QueueEntry entry, int index,
    {String? heading,
    String? album,
    String? playbackLabel,
    String? durationLabel}) {
  final tokens = Theme.of(context).thmr;
  final planned = queuePlannedHHmm(entry);
  final duration = durationLabel ?? '时长 ${formatDuration(entry.durationSec)}';
  final timing = playbackLabel != null
      ? '$duration · $playbackLabel'
      : planned == null
          ? duration
          : '$duration · 预计 $planned 播放';
  final copyText = [
    entry.title,
    entry.artist,
    if (album != null && album.isNotEmpty) album,
    timing,
  ].join('\n');
  final wide = MediaQuery.of(context).size.width >= 720;
  var copied = false;
  showModalBottomSheet<void>(
    sheetAnimationStyle: ThmrMotion.style(context),
    context: context,
    isScrollControlled: true,
    constraints: BoxConstraints(maxWidth: wide ? 480 : double.infinity),
    builder: (_) => SafeArea(
      child: SingleChildScrollView(
        child: StatefulBuilder(
          builder: (context, setState) => Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      width: 180,
                      height: 180,
                      child: TrackCoverImage(
                        url: entry.coverUrl,
                        cacheWidth:
                            (180 * MediaQuery.devicePixelRatioOf(context))
                                .round(),
                      ),
                    ),
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
                SelectableText(entry.title,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                SelectableText(entry.artist,
                    style: Theme.of(context)
                        .textTheme
                        .bodyMedium
                        ?.copyWith(color: tokens.mutedInk)),
                if (album != null && album.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  SelectableText(album,
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
                        child: SelectableText(
                      timing,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: tokens.mutedInk),
                    )),
                  ],
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: copyText));
                      if (!context.mounted) return;
                      setState(() => copied = true);
                      await Future<void>.delayed(
                          const Duration(milliseconds: 1600));
                      if (context.mounted) setState(() => copied = false);
                    },
                    icon: Icon(
                        copied ? Icons.check_rounded : Icons.copy_rounded,
                        size: 16),
                    label: Text(copied ? '已复制' : '复制信息'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// 横向队列卡片至少高 92 个逻辑像素，字号放大时按三行文字所需高度扩展。
double queueStripHeight(BuildContext context) {
  final text = Theme.of(context).textTheme;
  var height = 30.0; // 预留行间距、内边距和边框的高度。
  for (final style in [text.titleSmall, text.bodySmall, text.labelSmall]) {
    final painter = TextPainter(
        text: TextSpan(text: '曲目', style: style),
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context))
      ..layout();
    height += painter.height;
    painter.dispose();
  }
  return height > 92 ? height : 92;
}

class QueueStrip extends StatefulWidget {
  const QueueStrip({super.key, required this.status});

  final StationStatus status;

  @override
  State<QueueStrip> createState() => _QueueStripState();
}

class _QueueStripState extends State<QueueStrip> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = widget.status;
    final tokens = Theme.of(context).thmr;
    final queue = status.queue;
    if (queue.isEmpty) {
      return SizedBox(
        height: 92,
        child: ThmrPanel(
          child: Center(
            child: Text(
              '队列暂无曲目 · 尽情期待',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: tokens.mutedInk),
            ),
          ),
        ),
      );
    }
    return Column(
      children: [
        HorizontalWheelScroll(
          controller: _scrollController,
          child: SizedBox(
            height: queueStripHeight(context),
            child: ListView.separated(
              controller: _scrollController,
              scrollDirection: Axis.horizontal,
              itemCount: queue.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) {
                final e = queue[i];
                return _QueueCard(entry: e, index: i);
              },
            ),
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
    return SizedBox(
        width: 264,
        child: ThmrPanel(
          onTap: () => showQueueEntryDetail(context, entry, index),
          padding: const EdgeInsets.all(11),
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
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w800,
                            fontFeatures: const [FontFeature.tabularFigures()],
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
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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
        ));
  }
}

/// 显示曲目时长，后端提供时也显示预计播出时间。
String plannedLabel(QueueEntry entry, int index) {
  final planned = queuePlannedHHmm(entry);
  return planned == null
      ? formatDuration(entry.durationSec)
      : '${formatDuration(entry.durationSec)} · 预计 $planned';
}
