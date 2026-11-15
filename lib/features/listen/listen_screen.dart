// Listen screen (home). Wide layout mirrors web home:
// hero banner on top, player column left, history/queue column right.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/radio_api.dart';
import '../../core/models/models.dart';
import '../../core/player/playback_controller.dart';
import '../../core/state/app_providers.dart';
import '../../core/state/channel_provider.dart';
import '../../core/state/station_provider.dart';
import '../../core/state/radio_source_provider.dart';
import '../../core/theme/thmr_theme.dart';
import '../../shared/widgets/thmr_panel.dart';
import '../../shared/widgets/status_notice.dart';
import 'widgets/bitrate_row.dart';
import 'widgets/channel_loading_skeleton.dart';
import 'widgets/channel_switcher.dart';
import 'widgets/listener_stat.dart';
import 'widgets/now_playing_panel.dart';
import 'widgets/queue_strip.dart';
import 'widgets/side_info_column.dart';
import 'widgets/vote_panel.dart';

/// 收听页(首页)。
class ListenScreen extends ConsumerStatefulWidget {
  const ListenScreen({super.key});

  @override
  ConsumerState<ListenScreen> createState() => _ListenScreenState();
}

class _ListenScreenState extends ConsumerState<ListenScreen> {
  StationUiState? _lastLoaded;

  @override
  Widget build(BuildContext context) {
    final station = ref.watch(stationProvider);
    final info = station.status?.station;
    final switching =
        info == null && station.initialLoading && _lastLoaded != null;
    if (info != null) _lastLoaded = station;
    // A channel switch keeps the existing surface and its scroll positions.
    // The real provider stays unchanged, so playback still waits for new data.
    final display = switching
        ? StationUiState(
            status: _lastLoaded!.status, updatedAt: _lastLoaded!.updatedAt)
        : station;
    final heading = display.status?.station;
    final source = ref.watch(radioSourceProvider);
    final selecting = source.testing && !source.tested;
    final failure = ref
        .watch(playbackProvider.select((state) => (state.error, state.phase)));
    final playbackError = failure.$2 == PlaybackPhase.idle ? null : failure.$1;
    final temporaryError = station.status != null &&
        station.error != null &&
        !_persistentStationError(station.error!);
    final message = temporaryError
        ? _stationErrorMessage(station.error!)
        : playbackError ??
            (switching
                ? '正在切换频道…'
                : selecting
                    ? '正在比较最优播放源，完成后即可收听…'
                    : source.notice);
    final busy =
        (switching || selecting) && !temporaryError && playbackError == null;

    return SafeArea(
      bottom: false,
      child: Stack(fit: StackFit.expand, children: [
        LayoutBuilder(builder: (context, c) {
          if (c.maxWidth >= 980) {
            return _WideLayout(
                station: display, heading: heading, switching: switching);
          }
          return _NarrowLayout(
              station: display, heading: heading, switching: switching);
        }),
        Positioned(
            bottom: 16,
            left: 16,
            right: 16,
            child: StatusNotice(
                message: message,
                busy: busy,
                duration: busy ? null : const Duration(seconds: 6),
                onRetry: temporaryError
                    ? () => ref.read(stationProvider.notifier).refresh()
                    : null)),
      ]),
    );
  }
}

// ---------------- wide (>= 980px): hero + two columns ----------------

class _WideLayout extends ConsumerWidget {
  const _WideLayout({
    required this.station,
    required this.heading,
    required this.switching,
  });

  final StationUiState station;
  final StationInfo? heading;
  final bool switching;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = station.status;
    final error = station.error;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Hero(status: status, heading: heading, switching: switching),
          if (error != null &&
              (status == null || _persistentStationError(error)))
            _ErrorCard(
              error: error,
              onRetry: () => ref.read(stationProvider.notifier).refresh(),
            ),
          const SizedBox(height: 16),
          Expanded(
            child: _ChannelSurface(
              switching: switching,
              child: status == null
                  ? _ChannelPlaceholder(
                      loading: station.initialLoading,
                      switching: switching,
                      wide: true,
                      showVote: _showVote(ref))
                  : Row(
                      key: const ValueKey('wide-channel-content'),
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 5,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.only(bottom: 24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                NowPlayingPanel(
                                  status: status,
                                  inlineBitrate: false,
                                  switching: switching,
                                ),
                                const SizedBox(height: 12),
                                _DesktopControls(
                                    status: status, switching: switching),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        SizedBox(
                          width: 330,
                          child: SideInfoColumn(
                            status: status,
                            updatedAt: station.updatedAt,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

bool _showVote(WidgetRef ref) => ref
    .watch(voteEnabledProvider.select((value) => value.asData?.value == true));

class _DesktopControls extends ConsumerWidget {
  const _DesktopControls({required this.status, required this.switching});

  final StationStatus status;
  final bool switching;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showVote = _showVote(ref);
    final showBitrate = status.station.enabledBitrates.isNotEmpty;
    final quality = ThmrPanel(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Align(
        alignment: Alignment.centerLeft,
        widthFactor: 1,
        heightFactor: 1,
        child: BitrateRow(status: status),
      ),
    );

    if (!showVote) return showBitrate ? quality : const SizedBox.shrink();
    final vote = VotePanel(
        key: ValueKey(status.station.id), status: status, switching: switching);
    if (!showBitrate) return vote;
    return LayoutBuilder(builder: (context, constraints) {
      final voteWidth = (constraints.maxWidth - 8) / 2;
      return IntrinsicHeight(
          child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: quality),
          const SizedBox(width: 8),
          Expanded(
              child: VotePanel(
                  key: ValueKey(status.station.id),
                  status: status,
                  switching: switching,
                  availableWidth: voteWidth)),
        ],
      ));
    });
  }
}

/// Hero banner, mirrors web home hero section.
class _Hero extends StatelessWidget {
  const _Hero({
    required this.status,
    required this.heading,
    required this.switching,
  });

  final StationStatus? status;
  final StationInfo? heading;
  final bool switching;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    final info = status?.station;
    final title = heading?.public?.title ?? heading?.name ?? '东方音乐电台 THMR';
    final description = heading?.public?.description ?? '';

    final panel = ThmrPanel(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _ChannelTransition(
                  child: Text(
                    title,
                    key: ValueKey(title),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .headlineMedium
                        ?.copyWith(fontWeight: FontWeight.w900, height: 1.15),
                  ),
                ),
                if (description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: tokens.mutedInk),
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    LiveBadge(
                        active: info?.enabled ?? false, switching: switching),
                    ChannelSwitcher(station: info),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          ListenerStat(listeners: status?.listeners),
        ],
      ),
    );
    return MediaQuery.disableAnimationsOf(context)
        ? panel
        : AnimatedSize(
            duration: const Duration(milliseconds: 220),
            alignment: Alignment.topLeft,
            child: panel);
  }
}

// ---------------- narrow (< 980px): single column ----------------

class _NarrowLayout extends ConsumerWidget {
  const _NarrowLayout({
    required this.station,
    required this.heading,
    required this.switching,
  });

  final StationUiState station;
  final StationInfo? heading;
  final bool switching;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = station.status;
    final error = station.error;
    final showVote = st != null && _showVote(ref);
    return RefreshIndicator(
      color: Theme.of(context).colorScheme.primary,
      onRefresh: () async {
        ref.invalidate(channelCatalogProvider);
        await ref.read(stationProvider.notifier).refresh();
      },
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          _TopBar(
            stationName: heading?.name ?? '东方音乐电台 THMR',
            status: st,
            switching: switching,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: ChannelSwitcher(station: st?.station),
          ),
          if (error != null && (st == null || _persistentStationError(error)))
            _ErrorCard(
              error: error,
              onRetry: () => ref.read(stationProvider.notifier).refresh(),
            ),
          const SizedBox(height: 14),
          _ChannelSurface(
            switching: switching,
            child: st == null
                ? _ChannelPlaceholder(
                    loading: station.initialLoading,
                    switching: switching,
                    wide: false,
                    showVote: _showVote(ref))
                : Column(
                    key: const ValueKey('narrow-channel-content'),
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      NowPlayingPanel(status: st, switching: switching),
                      if (showVote) ...[
                        const SizedBox(height: 12),
                        VotePanel(
                            key: ValueKey(st.station.id),
                            status: st,
                            switching: switching),
                      ],
                      const SizedBox(height: 18),
                      SectionHeader(
                        title: '接下来',
                        trailing: Text(
                          '队列 ${st.queue.length} 首',
                          style: Theme.of(context)
                              .textTheme
                              .labelMedium
                              ?.copyWith(
                                  color: Theme.of(context).thmr.mutedInk),
                        ),
                      ),
                      QueueStrip(status: st),
                      const SizedBox(height: 24),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.stationName,
    required this.status,
    required this.switching,
  });

  final String stationName;
  final StationStatus? status;
  final bool switching;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.asset('assets/brand/logo.png', width: 38, height: 38),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ChannelTransition(
                child: Text(
                  stationName,
                  key: ValueKey(stationName),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800, height: 1.2),
                ),
              ),
              Text(
                'Touhou Music Radio',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: tokens.mutedInk,
                      letterSpacing: 2,
                    ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            LiveBadge(
                active: status?.station.enabled ?? false, switching: switching),
            const SizedBox(height: 5),
            ListenerStat(listeners: status?.listeners, compact: true),
          ],
        ),
      ],
    );
  }
}

/// Keep pending channel data out of focus, hit testing and announcements while
/// retaining the same rendered subtree until the new status is ready.
class _ChannelSurface extends StatelessWidget {
  const _ChannelSurface({required this.switching, required this.child});

  final bool switching;
  final Widget child;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        ignoring: switching,
        child: ExcludeFocus(
            excluding: switching,
            child: ExcludeSemantics(
                excluding: switching,
                child: TickerMode(
                    enabled: !switching,
                    child: _ChannelTransition(child: child)))),
      );
}

class _ChannelTransition extends StatelessWidget {
  const _ChannelTransition({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;

    Widget layer(Widget transition, {required bool outgoing}) {
      return TickerMode(
        key: transition.key,
        enabled: !outgoing,
        child: IgnorePointer(
          ignoring: outgoing,
          child: ExcludeFocus(
            excluding: outgoing,
            child: ExcludeSemantics(
              excluding: outgoing,
              child: BackdropGroup(child: transition),
            ),
          ),
        ),
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 230),
      reverseDuration: const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (current, previous) => Stack(
        alignment: AlignmentDirectional.topStart,
        children: [
          for (final outgoing in previous) layer(outgoing, outgoing: true),
          if (current != null) layer(current, outgoing: false),
        ],
      ),
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: child,
      ),
      child: child,
    );
  }
}

class _ChannelPlaceholder extends StatelessWidget {
  const _ChannelPlaceholder(
      {required this.loading,
      required this.switching,
      required this.wide,
      required this.showVote});

  final bool loading;
  final bool switching;
  final bool wide;
  final bool showVote;

  @override
  Widget build(BuildContext context) {
    if (!loading) return const SizedBox.shrink();
    return ChannelLoadingSkeleton(
        switching: switching, wide: wide, showVote: showVote);
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.error,
    required this.onRetry,
  });

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: ThmrPanel(
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded,
                color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _stationErrorMessage(error),
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: tokens.mutedInk),
              ),
            ),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded, size: 16),
              label: const Text('立即重试'),
            ),
          ],
        ),
      ),
    );
  }
}

String _stationErrorMessage(Object error) {
  if (error is ApiException) {
    final e = error;
    switch (e.statusCode) {
      case 503:
        return '电台暂未开放放送(维护或休眠中),稍后自动重试。';
      case 404:
        return '未找到该电台,请检查频道 ID 配置。';
      default:
        return '服务返回异常(${e.statusCode}),正在自动重试。';
    }
  }
  return '网络连接失败,正在自动重试…';
}

bool _persistentStationError(Object error) =>
    error is ApiException && [400, 401, 403, 404].contains(error.statusCode);
