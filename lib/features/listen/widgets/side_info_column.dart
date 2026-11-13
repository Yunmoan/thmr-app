// Right column for wide layouts: previous track / stream state / queue list.
// Mirrors web "过去与未来" (StatusPanel) + queue.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;

import '../../../shared/widgets/focus_outline.dart';
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

class _QueueList extends StatefulWidget {
  const _QueueList({required this.status});

  final StationStatus status;

  @override
  State<_QueueList> createState() => _QueueListState();
}

class _QueueListState extends State<_QueueList> {
  final _scrollController = ScrollController();
  List<String> _coverUrls = const [];
  int _cacheWidth = 0;
  int _preloadGeneration = 0;
  double? _cacheExtent;
  final _indexWidths = <String, double>{};
  final _timeWidths = <String, double>{};
  TextStyle? _indexMetricStyle, _timeMetricStyle;
  (TextScaler, TextDirection, Locale?)? _metricContext;

  List<QueueEntry> get queue => widget.status.queue;

  @override
  void initState() {
    super.initState();
    PaintingBinding.instance.systemFonts.addListener(_fontsChanged);
  }

  void _fontsChanged() {
    setState(() {
      _indexWidths.clear();
      _timeWidths.clear();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _schedulePreload();
  }

  @override
  void didUpdateWidget(covariant _QueueList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedulePreload();
  }

  void _schedulePreload() {
    final cacheWidth = (40 * MediaQuery.devicePixelRatioOf(context)).round();
    final urls = queue.isEmpty
        ? <String>[]
        : <String>{'', ...queue.map((entry) => entry.coverUrl)}.toList();
    if (cacheWidth == _cacheWidth && listEquals(urls, _coverUrls)) return;
    _cacheWidth = cacheWidth;
    _coverUrls = urls;
    final generation = ++_preloadGeneration;
    if (urls.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _preloadGeneration) return;
      unawaited(_preloadCovers(urls, cacheWidth, generation));
    });
  }

  Future<void> _preloadCovers(
      List<String> urls, int cacheWidth, int generation) async {
    // Start at most two thumbnails between frames. Waiting for scheduler idle
    // would starve this work while the playback spectrum ticker is running.
    for (var start = 0; start < urls.length; start += 2) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || generation != _preloadGeneration) return;
      // Give an active scroll priority over additional background decodes.
      while (_scrollController.hasClients &&
          _scrollController.position.isScrollingNotifier.value) {
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || generation != _preloadGeneration) return;
      }
      if (_scrollController.hasClients) {
        final viewport = _scrollController.position.viewportDimension;
        final currentExtent = _cacheExtent ?? 250;
        final targetExtent = viewport * 2;
        if (currentExtent < targetExtent) {
          // Grow the layout cache a few rows at a time after the first paint.
          setState(() {
            _cacheExtent = (currentExtent + viewport / 2)
                .clamp(0, targetExtent)
                .toDouble();
          });
        }
      }
      await Future.wait(urls.skip(start).take(2).map((url) {
        return precacheImage(
          TrackCover.providerFor(url, cacheWidth: cacheWidth),
          context,
          onError: (_, __) {},
        ).timeout(const Duration(seconds: 10), onTimeout: () {});
      }));
    }
  }

  @override
  void dispose() {
    ++_preloadGeneration;
    PaintingBinding.instance.systemFonts.removeListener(_fontsChanged);
    _scrollController.dispose();
    super.dispose();
  }

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
    final labelStyle = Theme.of(context).textTheme.labelSmall;
    final indexStyle = labelStyle?.copyWith(
      color: Theme.of(context).colorScheme.primary,
      fontWeight: FontWeight.w800,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final timeStyle = labelStyle?.copyWith(
      color: tokens.mutedInk,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final defaultStyle = DefaultTextStyle.of(context).style;
    final indexMetricStyle = defaultStyle.merge(indexStyle);
    final timeMetricStyle = defaultStyle.merge(timeStyle);
    final metricContext = (
      MediaQuery.textScalerOf(context),
      Directionality.of(context),
      Localizations.maybeLocaleOf(context)
    );
    if (_metricContext != metricContext ||
        _indexMetricStyle == null ||
        _indexMetricStyle!.compareTo(indexMetricStyle) ==
            RenderComparison.layout) {
      _indexWidths.clear();
    }
    if (_metricContext != metricContext ||
        _timeMetricStyle == null ||
        _timeMetricStyle!.compareTo(timeMetricStyle) ==
            RenderComparison.layout) {
      _timeWidths.clear();
    }
    _metricContext = metricContext;
    _indexMetricStyle = indexMetricStyle;
    _timeMetricStyle = timeMetricStyle;
    // Reserve columns from the whole queue, so newly visible rows cannot shift
    // the title when index digits or schedule availability change.
    final indexWidth = _textColumnWidth(
      context,
      Iterable.generate(queue.length, (i) => '#${i + 1}'),
      indexStyle,
      cache: _indexWidths,
    );
    final durationWidth = _textColumnWidth(
      context,
      queue.map((entry) => formatDuration(entry.durationSec)),
      timeStyle,
      cache: _timeWidths,
    );
    final plannedWidth = _textColumnWidth(
      context,
      queue.map(queuePlannedHHmm).whereType<String>(),
      timeStyle,
      cache: _timeWidths,
    );
    final scheduleWidth =
        _textColumnWidth(context, ['预计'], timeStyle, cache: _timeWidths) +
            4 +
            plannedWidth;
    final timeWidth =
        durationWidth > scheduleWidth ? durationWidth : scheduleWidth;
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
                controller: _scrollController,
                scrollCacheExtent: _cacheExtent == null
                    ? null
                    : ScrollCacheExtent.pixels(_cacheExtent!),
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
                  final planned = queuePlannedHHmm(e);
                  return FocusOutline(
                      child: InkWell(
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
                                    SizedBox(
                                      width: indexWidth,
                                      child: Text(
                                        '#${i + 1}',
                                        maxLines: 1,
                                        softWrap: false,
                                        style: indexStyle,
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
                          SizedBox(
                            width: timeWidth,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  formatDuration(e.durationSec),
                                  textAlign: TextAlign.right,
                                  maxLines: 1,
                                  softWrap: false,
                                  style: timeStyle,
                                ),
                                if (planned != null)
                                  // This font has proportional digits even
                                  // with tabularFigures. Anchor the prefix
                                  // separately so time widths cannot move it.
                                  Row(
                                    children: [
                                      Text('预计', style: timeStyle),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          planned,
                                          textAlign: TextAlign.right,
                                          maxLines: 1,
                                          softWrap: false,
                                          style: timeStyle,
                                        ),
                                      ),
                                    ],
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ));
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
              onPressed: () => showQueueSheet(context, status: widget.status),
              icon: const Icon(Icons.unfold_more_rounded, size: 17),
              label: Text('查看全部 ${queue.length} 首'),
            ),
          ),
        ),
      ],
    );
  }
}

double _textColumnWidth(
    BuildContext context, Iterable<String> labels, TextStyle? style,
    {required Map<String, double> cache}) {
  TextPainter? painter;
  final effectiveStyle = DefaultTextStyle.of(context).style.merge(style);
  var width = 0.0;
  for (final label in labels) {
    var measured = cache[label];
    if (measured == null) {
      painter ??= TextPainter(
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          locale: Localizations.maybeLocaleOf(context),
          maxLines: 1);
      painter.text = TextSpan(text: label, style: effectiveStyle);
      painter.layout();
      measured = painter.width;
      if (cache.length >= 512) cache.remove(cache.keys.first);
      cache[label] = measured;
    }
    if (measured > width) width = measured;
  }
  painter?.dispose();
  return width.ceilToDouble();
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
