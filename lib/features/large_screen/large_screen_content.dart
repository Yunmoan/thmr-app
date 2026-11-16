import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/models/models.dart';
import '../../core/player/playback_controller.dart';
import '../../core/state/large_screen_settings.dart';
import '../../core/state/station_provider.dart';
import '../../core/theme/thmr_theme.dart';
import '../../core/theme/thmr_motion.dart';
import '../../shared/widgets/thmr_panel.dart';
import '../../shared/widgets/track_cover.dart';
import 'large_screen_progress.dart';
import 'large_screen_widgets.dart';

class LargeScreenContent extends StatelessWidget {
  const LargeScreenContent(
      {super.key,
      required this.settings,
      required this.station,
      required this.phase,
      required this.playbackError,
      required this.header,
      required this.controls});

  final LargeScreenSettings settings;
  final StationUiState station;
  final PlaybackPhase phase;
  final String? playbackError;
  final Widget header;
  final Widget controls;

  @override
  Widget build(BuildContext context) {
    Widget canvas(BuildContext context, BoxConstraints outer) {
      final inset = settings.contentMargin;
      final hasTopWidgets = settings.widgets.any((w) => w.enabled && w.atTop);
      final hasBottomWidgets =
          settings.widgets.any((w) => w.enabled && !w.atTop);
      Widget widgets(bool atTop) => ConstrainedBox(
          constraints:
              BoxConstraints(maxHeight: math.max(40, outer.maxHeight * .12)),
          child: LargeScreenWidgetStrip(
              key: ValueKey(atTop),
              components: settings.widgets,
              station: station,
              atTop: atTop));
      final sideQueue =
          settings.queue == LargeScreenQueue.list && outer.maxWidth >= 1040;
      final hero = ThmrAnimatedContent(
          child: _Hero(
              key: ValueKey(settings.layout),
              settings: settings,
              station: station,
              phase: phase,
              playbackError: playbackError,
              fontSize: (outer.maxWidth * .036).clamp(28, 76)));
      return Padding(
        padding: EdgeInsets.all(inset),
        child: Column(children: [
          header,
          const SizedBox(height: 18),
          if (hasTopWidgets) ...[widgets(true), const SizedBox(height: 12)],
          Expanded(
              key: const ValueKey('large-screen-body'),
              child: sideQueue
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                          Expanded(child: hero),
                          const SizedBox(width: 16),
                          SizedBox(
                              width: (outer.maxWidth * .24).clamp(230, 360),
                              child: _QueuePanel(
                                  status: station.status,
                                  settings: settings,
                                  vertical: true)),
                        ])
                  : hero),
          if (settings.queue != LargeScreenQueue.hidden && !sideQueue) ...[
            const SizedBox(height: 14),
            SizedBox(
                height: settings.queue == LargeScreenQueue.list
                    ? math.min(190, outer.maxHeight * .23)
                    : (MediaQuery.textScalerOf(context).scale(60) + 45)
                        .clamp(100, outer.maxHeight * .32),
                child: _QueuePanel(
                    status: station.status,
                    settings: settings,
                    vertical: settings.queue == LargeScreenQueue.list)),
          ],
          if (hasBottomWidgets) ...[const SizedBox(height: 12), widgets(false)],
          if (settings.showControls) ...[
            const SizedBox(height: 12),
            SizedBox(
                key: const ValueKey('large-screen-controls-slot'),
                width: math.min(360, outer.maxWidth - inset * 2),
                child: controls),
          ],
        ]),
      );
    }

    // Keep the header, focus nodes and queue alive when framing changes.
    return BackdropGroup(
      child: Center(
        child: ConstrainedBox(
          key: const ValueKey('large-screen-centered-frame'),
          constraints: settings.framing == LargeScreenFraming.fit
              ? const BoxConstraints(maxWidth: 1560, maxHeight: 1000)
              : const BoxConstraints(),
          child: SizedBox.expand(
            child: LayoutBuilder(builder: (context, constraints) {
              final hasWidgets = settings.widgets.any((w) => w.enabled);
              final minimumHeight = math.max(
                      hasWidgets ? 720.0 : 440.0,
                      MediaQuery.textScalerOf(context)
                          .scale(hasWidgets ? 520 : 320)) +
                  math.max(0, settings.contentMargin - 32) * 2;
              return FittedBox(
                fit: BoxFit.scaleDown,
                child: SizedBox(
                  width: constraints.maxWidth,
                  height: math.max(constraints.maxHeight, minimumHeight),
                  child: LayoutBuilder(builder: canvas),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero(
      {super.key,
      required this.settings,
      required this.station,
      required this.phase,
      required this.playbackError,
      required this.fontSize});
  final LargeScreenSettings settings;
  final StationUiState station;
  final PlaybackPhase phase;
  final String? playbackError;
  final double fontSize;

  @override
  Widget build(BuildContext context) => ThmrPanel(
        enabled: settings.cardLayout,
        padding: const EdgeInsets.all(20),
        child: SizedBox.expand(
            child: LayoutBuilder(builder: (context, constraints) {
          final stacked = switch (settings.layout) {
            LargeScreenLayout.centered => true,
            LargeScreenLayout.adaptive => constraints.maxWidth < 660 ||
                constraints.maxWidth / constraints.maxHeight < 1.15,
            _ => false,
          };
          final gap =
              stacked ? 18.0 : (constraints.maxWidth * .04).clamp(20.0, 56.0);
          final size = math.max(
              1.0,
              stacked
                  ? math.min(constraints.maxWidth * .72,
                      math.max(1.0, (constraints.maxHeight - gap) * .5))
                  : math.min(
                      constraints.maxWidth * .44, constraints.maxHeight));
          final cover = _Cover(
              url: station.status?.current?.coverUrl ?? '',
              size: size,
              fit: settings.coverFit == LargeScreenCoverFit.cover
                  ? BoxFit.cover
                  : BoxFit.contain);
          final info = ThmrAnimatedContent(
              child: _TrackInfo(
                  key: ValueKey((
                    station.status?.current?.trackId,
                    station.status?.current?.startedAtMs,
                    station.status?.current?.title,
                    station.status?.current?.artist
                  )),
                  station: station,
                  phase: phase,
                  playbackError: playbackError,
                  fontSize: fontSize * settings.textScale,
                  centered: stacked,
                  showProgress: settings.showProgress));
          if (stacked) {
            return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  cover,
                  SizedBox(height: gap),
                  Flexible(child: info)
                ]);
          }
          return Row(children: [
            if (settings.layout != LargeScreenLayout.coverRight) ...[
              cover,
              SizedBox(width: gap)
            ],
            Expanded(child: info),
            if (settings.layout == LargeScreenLayout.coverRight) ...[
              SizedBox(width: gap),
              cover
            ],
          ]);
        })),
      );
}

class _Cover extends StatelessWidget {
  const _Cover({required this.url, required this.size, required this.fit});
  final String url;
  final double size;
  final BoxFit fit;
  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    final cacheWidth =
        (size * MediaQuery.devicePixelRatioOf(context)).round().clamp(1, 4096);
    Widget fallback() => Image.asset('assets/brand/cover-fallback.png',
        fit: fit, cacheWidth: cacheWidth);
    return Container(
      key: const ValueKey('large-screen-cover'),
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
          color: tokens.fieldBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: tokens.panelBorder)),
      child: ThmrAnimatedContent(
          alignment: Alignment.center,
          child: RepaintBoundary(
              key: ValueKey(url),
              child: Image(
                image: TrackCover.providerFor(url, cacheWidth: cacheWidth),
                fit: fit,
                gaplessPlayback: true,
                filterQuality: FilterQuality.medium,
                frameBuilder: (_, child, frame, synchronous) =>
                    frame != null || synchronous ? child : fallback(),
                errorBuilder: (_, __, ___) => fallback(),
              ))),
    );
  }
}

class _TrackInfo extends StatelessWidget {
  const _TrackInfo(
      {super.key,
      required this.station,
      required this.phase,
      required this.playbackError,
      required this.fontSize,
      required this.centered,
      required this.showProgress});
  final StationUiState station;
  final PlaybackPhase phase;
  final String? playbackError;
  final double fontSize;
  final bool centered;
  final bool showProgress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = station.status?.current;
    final title = current?.title.trim();
    final message = playbackError != null
        ? '播放异常，请检查网络后重试'
        : station.error != null
            ? station.status == null
                ? '暂时无法获取放送信息，正在重试'
                : '放送信息暂未更新，正在重试'
            : switch (phase) {
                PlaybackPhase.online => null,
                PlaybackPhase.idle => '尚未播放',
                PlaybackPhase.connecting => '正在连接',
                PlaybackPhase.buffering => '正在缓冲',
                PlaybackPhase.reconnecting => '正在重新连接',
              };
    return LayoutBuilder(
        builder: (context, constraints) => Center(
            heightFactor: 1,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: centered ? Alignment.center : Alignment.centerLeft,
              child: SizedBox(
                  width: constraints.maxWidth,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: centered
                        ? CrossAxisAlignment.center
                        : CrossAxisAlignment.start,
                    children: [
                      Wrap(
                          alignment: centered
                              ? WrapAlignment.center
                              : WrapAlignment.start,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 14,
                          runSpacing: 6,
                          children: [
                            Text('当前曲目',
                                style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.thmr.mutedInk,
                                    letterSpacing: 2)),
                            LiveBadge(active: phase == PlaybackPhase.online),
                          ]),
                      const SizedBox(height: 14),
                      Text(
                          title?.isNotEmpty == true
                              ? title!
                              : station.initialLoading && station.status == null
                                  ? '正在获取放送信息…'
                                  : '等待音乐响起',
                          key: const ValueKey('large-screen-title'),
                          textAlign:
                              centered ? TextAlign.center : TextAlign.left,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.headlineLarge?.copyWith(
                              fontSize: fontSize,
                              fontWeight: FontWeight.w800,
                              height: 1.2)),
                      if (current?.artist.trim().isNotEmpty == true) ...[
                        const SizedBox(height: 14),
                        Text(current!.artist,
                            textAlign:
                                centered ? TextAlign.center : TextAlign.left,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge?.copyWith(
                                fontSize: (fontSize * .45).clamp(18, 34),
                                color: theme.thmr.mutedInk)),
                      ],
                      if (showProgress) ...[
                        const SizedBox(height: 26),
                        LargeScreenProgress(
                            current: current, updatedAt: station.updatedAt),
                      ],
                      if (message != null) ...[
                        const SizedBox(height: 12),
                        Text(message,
                            style: theme.textTheme.bodySmall
                                ?.copyWith(color: theme.thmr.mutedInk)),
                      ],
                    ],
                  )),
            )));
  }
}

class _QueuePanel extends StatefulWidget {
  const _QueuePanel(
      {required this.status, required this.settings, required this.vertical});
  final StationStatus? status;
  final LargeScreenSettings settings;
  final bool vertical;
  @override
  State<_QueuePanel> createState() => _QueuePanelState();
}

class _QueuePanelState extends State<_QueuePanel> {
  final _scroll = ScrollController();
  @override
  void didUpdateWidget(covariant _QueuePanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status?.station.id != widget.status?.station.id ||
        oldWidget.vertical != widget.vertical) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _scroll.hasClients) _scroll.jumpTo(0);
      });
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    final vertical = widget.vertical;
    final queue = widget.status?.queue ?? const <QueueEntry>[];
    final count = settings.queue == LargeScreenQueue.next
        ? 1
        : settings.queue == LargeScreenQueue.list
            ? queue.length
            : settings.queueCount;
    final entries = queue.take(count).toList();
    final theme = Theme.of(context);
    return ThmrPanel(
      enabled: settings.cardLayout,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text('接下来',
              style: theme.textTheme.titleSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          if (vertical) ...[
            const Spacer(),
            Text('${queue.length} 首',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.thmr.mutedInk))
          ],
        ]),
        const SizedBox(height: 8),
        Expanded(
            child: entries.isEmpty
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: Text('等待下一首放送',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.thmr.mutedInk)))
                : LayoutBuilder(builder: (context, constraints) {
                    final visible = math.min(
                        entries.length, constraints.maxWidth < 600 ? 1 : 3);
                    final extent =
                        (constraints.maxWidth - (visible - 1) * 16) / visible;
                    return Scrollbar(
                      controller: _scroll,
                      thumbVisibility: vertical,
                      child: ListView.separated(
                        key: const ValueKey('large-screen-queue'),
                        controller: _scroll,
                        primary: false,
                        scrollDirection:
                            vertical ? Axis.vertical : Axis.horizontal,
                        itemCount: entries.length,
                        separatorBuilder: (_, __) => vertical
                            ? Divider(height: 18, color: theme.thmr.panelBorder)
                            : const SizedBox(width: 16),
                        itemBuilder: (context, index) {
                          final tile = _QueueTile(
                              track: entries[index],
                              index: index,
                              covers: settings.showQueueCovers);
                          return vertical
                              ? tile
                              : SizedBox(width: extent, child: tile);
                        },
                      ),
                    );
                  })),
      ]),
    );
  }
}

class _QueueTile extends StatelessWidget {
  const _QueueTile(
      {required this.track, required this.index, required this.covers});
  final QueueEntry track;
  final int index;
  final bool covers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(children: [
      if (covers) ...[
        TrackCover(url: track.coverUrl, size: 42, radius: 6),
        const SizedBox(width: 10)
      ],
      Text('#${index + 1}',
          style: theme.textTheme.labelMedium
              ?.copyWith(color: theme.colorScheme.primary)),
      const SizedBox(width: 10),
      Expanded(
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Text(track.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            if (track.artist.trim().isNotEmpty)
              Text(track.artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: theme.thmr.mutedInk)),
          ])),
    ]);
  }
}
