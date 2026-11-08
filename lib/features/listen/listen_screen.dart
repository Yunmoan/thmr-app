// Listen screen (home). Wide layout mirrors web home:
// hero banner on top, player column left, history/queue column right.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/radio_api.dart';
import '../../core/models/models.dart';
import '../../core/state/station_provider.dart';
import '../../core/state/radio_source_provider.dart';
import '../../core/theme/thmr_theme.dart';
import '../../shared/widgets/delay_fade_in.dart';
import '../../shared/widgets/thmr_panel.dart';
import 'widgets/bitrate_row.dart';
import 'widgets/now_playing_panel.dart';
import 'widgets/queue_strip.dart';
import 'widgets/side_info_column.dart';

/// 收听页(首页)。
class ListenScreen extends ConsumerWidget {
  const ListenScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final station = ref.watch(stationProvider);
    final status = station.status;
    final selecting = ref.watch(radioSourceProvider
        .select((source) => source.testing && !source.tested));

    return SafeArea(
      bottom: false,
      child: Column(children: [
        if (selecting)
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
            child: Row(children: [
              const SizedBox(
                  width: 15,
                  height: 15,
                  child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: 10),
              Expanded(
                  child: Text('正在比较两路播放源，完成后即可收听…',
                      style: Theme.of(context).textTheme.bodySmall)),
            ]),
          ),
        Expanded(child: LayoutBuilder(builder: (context, c) {
          final wide = c.maxWidth >= 980;
          if (wide && status != null) {
            return _WideLayout(status: status, error: station.error);
          }
          return _NarrowLayout(
            status: status,
            error: station.error,
            initialLoading: station.initialLoading,
            stationName: status?.station.name ?? '东方音乐电台 THMR',
          );
        })),
      ]),
    );
  }
}

// ---------------- wide (>= 980px): hero + two columns ----------------

class _WideLayout extends ConsumerWidget {
  const _WideLayout({required this.status, this.error});

  final StationStatus status;
  final Object? error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DelayFadeIn(child: _Hero(status: status)),
          if (error != null)
            _ErrorCard(
              error: error!,
              onRetry: () => ref.read(stationProvider.notifier).refresh(),
            ),
          const SizedBox(height: 16),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  flex: 5,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DelayFadeIn(
                          delay: const Duration(milliseconds: 70),
                          child: NowPlayingPanel(
                            status: status,
                            inlineBitrate: false,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const ThmrPanel(
                          padding: EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          child: BitrateRow(),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 330,
                  child: DelayFadeIn(
                    delay: const Duration(milliseconds: 110),
                    child: SideInfoColumn(
                      status: status,
                      updatedAt:
                          ref.watch(stationProvider.select((s) => s.updatedAt)),
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

/// Hero banner, mirrors web home hero section.
class _Hero extends StatelessWidget {
  const _Hero({required this.status});

  final StationStatus status;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    final accent = Theme.of(context).colorScheme.primary;
    final info = status.station;

    return ThmrPanel(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  info.public?.title ?? info.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .headlineMedium
                      ?.copyWith(fontWeight: FontWeight.w900, height: 1.15),
                ),
                if ((info.public?.description ?? '').isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    info.public!.description,
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
                    LiveBadge(active: info.enabled),
                    _Pill(label: '频道 ${info.id}'),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 24),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '实时在线听众',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: tokens.mutedInk),
              ),
              const SizedBox(height: 4),
              Text(
                '${status.listeners}',
                style: Theme.of(context).textTheme.displayMedium?.copyWith(
                  fontWeight: FontWeight.w900,
                  color: accent,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                '客户端',
                style: Theme.of(context)
                    .textTheme
                    .labelSmall
                    ?.copyWith(color: tokens.mutedInk),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: tokens.panelSoft,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: tokens.panelBorder),
      ),
      child: Text(
        label,
        style: Theme.of(context)
            .textTheme
            .labelSmall
            ?.copyWith(color: tokens.mutedInk, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ---------------- narrow (< 980px): single column ----------------

class _NarrowLayout extends ConsumerWidget {
  const _NarrowLayout({
    required this.status,
    required this.initialLoading,
    required this.stationName,
    this.error,
  });

  final StationStatus? status;
  final bool initialLoading;
  final String stationName;
  final Object? error;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = status;
    final content = RefreshIndicator(
      color: Theme.of(context).colorScheme.primary,
      onRefresh: () => ref.read(stationProvider.notifier).refresh(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        children: [
          if (st != null || error == null)
            _TopBar(stationName: stationName, status: status),
          if (error != null)
            _ErrorCard(
              error: error!,
              topSpacing: st == null ? 0 : 14,
              onRetry: () => ref.read(stationProvider.notifier).refresh(),
            ),
          if (st != null) ...[
            const SizedBox(height: 14),
            NowPlayingPanel(status: st),
            const SizedBox(height: 18),
            SectionHeader(
              title: '接下来',
              trailing: Text(
                '队列 ${st.queue.length} 首',
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: Theme.of(context).thmr.mutedInk),
              ),
            ),
            QueueStrip(status: st),
            const SizedBox(height: 24),
          ] else if (!initialLoading && error == null)
            const SizedBox(
              height: 320,
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
    return content;
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({required this.stationName, required this.status});

  final String stationName;
  final StationStatus? status;

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
              Text(
                stationName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800, height: 1.2),
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
            LiveBadge(active: status?.station.enabled ?? false),
            const SizedBox(height: 5),
            Text(
              '${status?.listeners ?? '-'} 人在听',
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: tokens.mutedInk),
            ),
          ],
        ),
      ],
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({
    required this.error,
    required this.onRetry,
    this.topSpacing = 14,
  });

  final Object error;
  final VoidCallback onRetry;
  final double topSpacing;

  String get _friendly {
    if (error is ApiException) {
      final e = error as ApiException;
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

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    return Padding(
      padding: EdgeInsets.only(top: topSpacing),
      child: ThmrPanel(
        child: Row(
          children: [
            Icon(Icons.cloud_off_rounded,
                color: Theme.of(context).colorScheme.error),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _friendly,
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
