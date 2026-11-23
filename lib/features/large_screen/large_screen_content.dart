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

const phoneLandscapeIllustrationWidth = .22;

class LargeScreenContent extends StatelessWidget {
  const LargeScreenContent(
      {super.key,
      required this.settings,
      required this.station,
      required this.phase,
      required this.playbackError,
      required this.header,
      required this.controls,
      this.phone = false});

  final LargeScreenSettings settings;
  final StationUiState station;
  final PlaybackPhase phase;
  final String? playbackError;
  final Widget header;
  final Widget controls;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    if (phone) return BackdropGroup(child: _phoneCanvas(context));

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
          fade: false,
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

    // 切换画面布局时，保留页眉、焦点节点和播放队列的状态。
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

  Widget _phoneCanvas(BuildContext context) {
    final landscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final horizontal = (settings.contentMargin * .55).clamp(12.0, 32.0);
    final vertical = (settings.contentMargin * .28).clamp(8.0, 18.0);
    final gap = landscape ? 12.0 : 16.0;
    final stacked = !landscape || settings.layout == LargeScreenLayout.centered;
    final coverRight = settings.layout == LargeScreenLayout.coverRight;
    final showQueue = settings.queue != LargeScreenQueue.hidden;
    final listQueue = settings.queue == LargeScreenQueue.list;
    final hasTopWidgets = settings.widgets.any((w) => w.enabled && w.atTop);
    final hasBottomWidgets = settings.widgets.any((w) => w.enabled && !w.atTop);
    final artWidth =
        MediaQuery.sizeOf(context).width * phoneLandscapeIllustrationWidth;

    return LayoutBuilder(builder: (context, constraints) {
      final gutter = landscape && settings.showIllustration
          ? math.min(artWidth, constraints.maxWidth * .35)
          : 0.0;
      final artOnRight = settings.illustrationPosition ==
          LargeScreenIllustrationPosition.right;
      return Padding(
        padding: EdgeInsets.fromLTRB(
          horizontal + (artOnRight ? 0 : gutter),
          vertical,
          horizontal + (artOnRight ? gutter : 0),
          vertical,
        ),
        child: Column(
          children: [
            header,
            SizedBox(height: gap),
            Expanded(
              child: LayoutBuilder(builder: (context, body) {
                final coverHeightFraction =
                    switch ((landscape, stacked, showQueue)) {
                  (false, _, _) => .38,
                  (_, true, _) => .44,
                  (_, _, true) => .52,
                  _ => .66,
                };
                final maxCoverWidth = body.maxWidth * (stacked ? .76 : .31);
                final coverSize = math.min(
                  maxCoverWidth,
                  (body.maxHeight * coverHeightFraction).clamp(
                    landscape ? 84.0 : 108.0,
                    landscape ? 210.0 : 304.0,
                  ),
                );
                final cover = _Cover(
                  url: station.status?.current?.coverUrl ?? '',
                  size: coverSize,
                  fit: settings.coverFit == LargeScreenCoverFit.cover
                      ? BoxFit.cover
                      : BoxFit.contain,
                );
                final info = _AnimatedTrackInfo(
                  station: station,
                  phase: phase,
                  playbackError: playbackError,
                  fontSize: (body.maxWidth * (landscape ? .052 : .082))
                          .clamp(22.0, 34.0) *
                      settings.textScale,
                  centered: stacked,
                  showProgress: settings.showProgress,
                  phone: true,
                );
                final hero = ThmrPanel(
                  enabled: settings.cardLayout,
                  padding: settings.cardLayout
                      ? EdgeInsets.all(gap)
                      : EdgeInsets.zero,
                  child: SizedBox(
                    width: double.infinity,
                    child: stacked
                        ? Column(children: [cover, SizedBox(height: gap), info])
                        : Row(
                            spacing: gap,
                            children: [
                              if (!coverRight) cover,
                              Expanded(child: info),
                              if (coverRight) cover,
                            ],
                          ),
                  ),
                );
                Widget strip(bool atTop) => LargeScreenWidgetStrip(
                      key: ValueKey(atTop),
                      components: settings.widgets,
                      station: station,
                      atTop: atTop,
                      singleColumn: !landscape,
                    );
                return KeyedSubtree(
                  key: ValueKey(station.status?.station.id),
                  child: CustomScrollView(
                    key: const ValueKey('large-screen-phone-scroll'),
                    primary: false,
                    slivers: [
                      SliverToBoxAdapter(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: listQueue ? 0 : body.maxHeight,
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            spacing: gap,
                            children: [
                              if (hasTopWidgets) strip(true),
                              hero,
                              if (!listQueue && showQueue)
                                _QueuePanel(
                                  status: station.status,
                                  settings: settings,
                                  vertical: false,
                                  phone: true,
                                ),
                              if (!listQueue && hasBottomWidgets) strip(false),
                            ],
                          ),
                        ),
                      ),
                      if (listQueue) ...[
                        SliverPadding(
                          padding: EdgeInsets.only(top: gap),
                          sliver: _PhoneQueueList(
                            status: station.status,
                            settings: settings,
                          ),
                        ),
                        if (hasBottomWidgets)
                          SliverPadding(
                            padding: EdgeInsets.only(top: gap),
                            sliver: SliverToBoxAdapter(child: strip(false)),
                          ),
                      ],
                    ],
                  ),
                );
              }),
            ),
            if (settings.showControls) ...[
              SizedBox(height: gap),
              SizedBox(
                key: const ValueKey('large-screen-controls-slot'),
                width: 360,
                child: controls,
              ),
            ],
          ],
        ),
      );
    });
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
          final info = _AnimatedTrackInfo(
            station: station,
            phase: phase,
            playbackError: playbackError,
            fontSize: fontSize * settings.textScale,
            centered: stacked,
            showProgress: settings.showProgress,
          );
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
    return Container(
      key: const ValueKey('large-screen-cover'),
      width: size,
      height: size,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
          color: tokens.fieldBg,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: tokens.panelBorder)),
      child: RepaintBoundary(
        child: SizedBox.expand(
          child: TrackCoverImage(
            url: url,
            cacheWidth: cacheWidth,
            fit: fit,
            filterQuality: FilterQuality.medium,
          ),
        ),
      ),
    );
  }
}

class _AnimatedTrackInfo extends StatelessWidget {
  const _AnimatedTrackInfo({
    required this.station,
    required this.phase,
    required this.playbackError,
    required this.fontSize,
    required this.centered,
    required this.showProgress,
    this.phone = false,
  });

  final StationUiState station;
  final PlaybackPhase phase;
  final String? playbackError;
  final double fontSize;
  final bool centered;
  final bool showProgress;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final track = station.status?.current;
    return ThmrAnimatedContent(
      child: _TrackInfo(
        key: ValueKey(
            (track?.trackId, track?.startedAtMs, track?.title, track?.artist)),
        station: station,
        phase: phase,
        playbackError: playbackError,
        fontSize: fontSize,
        centered: centered,
        showProgress: showProgress,
        phone: phone,
      ),
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
      required this.showProgress,
      required this.phone});
  final StationUiState station;
  final PlaybackPhase phase;
  final String? playbackError;
  final double fontSize;
  final bool centered;
  final bool showProgress;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = station.status?.current;
    final title = current?.title.trim();
    final artist = current?.artist.trim();
    final align = centered ? TextAlign.center : TextAlign.start;
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
    final titleText = Text(
      title?.isNotEmpty == true
          ? title!
          : station.initialLoading && station.status == null
              ? '正在获取放送信息…'
              : '等待音乐响起',
      key: const ValueKey('large-screen-title'),
      textAlign: align,
      maxLines: phone ? 3 : 4,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.headlineLarge?.copyWith(
        fontSize: fontSize,
        fontWeight: FontWeight.w800,
        height: 1.2,
      ),
    );
    final artistText = Text(
      artist ?? '',
      textAlign: align,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.titleLarge?.copyWith(
        fontSize: phone
            ? (fontSize * .52).clamp(14.0, 20.0)
            : (fontSize * .45).clamp(18.0, 34.0),
        color: theme.thmr.mutedInk,
      ),
    );
    final live = LiveBadge(active: phase == PlaybackPhase.online);
    final progress =
        LargeScreenProgress(current: current, updatedAt: station.updatedAt);
    final messageStyle =
        theme.textTheme.bodySmall?.copyWith(color: theme.thmr.mutedInk);

    if (phone) {
      final showMessage = message != null &&
          (phase != PlaybackPhase.idle ||
              playbackError != null ||
              station.error != null);
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            centered ? CrossAxisAlignment.center : CrossAxisAlignment.start,
        children: [
          titleText,
          if (artist?.isNotEmpty == true) ...[
            const SizedBox(height: 4),
            artistText,
          ],
          const SizedBox(height: 8),
          Wrap(
            alignment: centered ? WrapAlignment.center : WrapAlignment.start,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              live,
              if (showMessage)
                Text(message, style: messageStyle, textAlign: align),
            ],
          ),
          if (showProgress) ...[const SizedBox(height: 12), progress],
        ],
      );
    }

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
                      Text('当前曲目',
                          textAlign:
                              centered ? TextAlign.center : TextAlign.left,
                          style: theme.textTheme.labelMedium?.copyWith(
                              color: theme.thmr.mutedInk, letterSpacing: 2)),
                      const SizedBox(height: 14),
                      titleText,
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          if (artist?.isNotEmpty == true) ...[
                            Expanded(child: artistText),
                            const SizedBox(width: 12),
                          ],
                          live,
                        ],
                      ),
                      if (showProgress) ...[
                        const SizedBox(height: 26),
                        progress,
                      ],
                      // @Aoralsfout：始终保留消息框，无消息时使用空字符串，
                      // 避免消息变化引发布局跳动。
                      const SizedBox(height: 12),
                      Text(message ?? '', style: messageStyle),
                    ],
                  )),
            )));
  }
}

class _QueuePanel extends StatefulWidget {
  const _QueuePanel({
    required this.status,
    required this.settings,
    required this.vertical,
    this.phone = false,
  });
  final StationStatus? status;
  final LargeScreenSettings settings;
  final bool vertical;
  final bool phone;
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
    final empty =
        Align(alignment: Alignment.centerLeft, child: _emptyQueue(context));
    Widget tile(int index) => _QueueTile(
        track: entries[index], index: index, covers: settings.showQueueCovers);
    Widget divider() => Divider(height: 18, color: theme.thmr.panelBorder);
    final list = entries.isEmpty
        ? empty
        : LayoutBuilder(builder: (context, constraints) {
            final visible =
                math.min(entries.length, constraints.maxWidth < 600 ? 1 : 3);
            final extent =
                (constraints.maxWidth - (visible - 1) * 16) / visible;
            return Scrollbar(
              controller: _scroll,
              thumbVisibility: vertical,
              child: ListView.separated(
                key: const ValueKey('large-screen-queue'),
                controller: _scroll,
                primary: false,
                scrollDirection: vertical ? Axis.vertical : Axis.horizontal,
                itemCount: entries.length,
                separatorBuilder: (_, __) =>
                    vertical ? divider() : const SizedBox(width: 16),
                itemBuilder: (context, index) => vertical
                    ? tile(index)
                    : SizedBox(width: extent, child: tile(index)),
              ),
            );
          });
    return ThmrPanel(
      enabled: settings.cardLayout,
      padding: EdgeInsets.symmetric(
        horizontal: 16,
        vertical: widget.phone ? 6 : 10,
      ),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _QueueHeading(count: vertical ? queue.length : null),
            const SizedBox(height: 8),
            if (widget.phone)
              SizedBox(
                height: math.max(
                    44, MediaQuery.textScalerOf(context).scale(38) + 4),
                child: list,
              )
            else
              Expanded(child: list),
          ]),
    );
  }
}

class _PhoneQueueList extends StatelessWidget {
  const _PhoneQueueList({required this.status, required this.settings});

  final StationStatus? status;
  final LargeScreenSettings settings;

  @override
  Widget build(BuildContext context) {
    final queue = status?.queue ?? const <QueueEntry>[];
    final tokens = Theme.of(context).thmr;
    final cards = settings.cardLayout;
    Widget section(Widget child) => ThmrPanel(
          enabled: cards,
          padding: cards
              ? const EdgeInsets.symmetric(horizontal: 16, vertical: 6)
              : EdgeInsets.zero,
          child: child,
        );

    return SliverPadding(
      padding: cards
          ? EdgeInsets.zero
          : const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      sliver: SliverMainAxisGroup(slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(bottom: queue.isEmpty ? 0 : 8),
            child: section(Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _QueueHeading(count: queue.length),
                if (queue.isEmpty) ...[
                  const SizedBox(height: 8),
                  _emptyQueue(context),
                ],
              ],
            )),
          ),
        ),
        if (queue.isNotEmpty)
          SliverList.separated(
            key: const ValueKey('large-screen-queue'),
            itemCount: queue.length,
            itemBuilder: (context, index) => section(_QueueTile(
              track: queue[index],
              index: index,
              covers: settings.showQueueCovers,
            )),
            separatorBuilder: (_, __) => cards
                ? const SizedBox(height: 6)
                : Divider(height: 18, color: tokens.panelBorder),
          ),
      ]),
    );
  }
}

class _QueueHeading extends StatelessWidget {
  const _QueueHeading({this.count});

  final int? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(children: [
      Flexible(
        child: Text('接下来',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700)),
      ),
      if (count != null) ...[
        const Spacer(),
        Text('$count 首',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.thmr.mutedInk)),
      ],
    ]);
  }
}

Widget _emptyQueue(BuildContext context) {
  final theme = Theme.of(context);
  return Text('等待下一首放送',
      style: theme.textTheme.bodySmall?.copyWith(color: theme.thmr.mutedInk));
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
