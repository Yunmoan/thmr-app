import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/network_failure.dart';
import '../../core/models/models.dart';
import '../../core/state/channel_provider.dart';
import '../../core/state/radio_source_provider.dart';
import '../../core/theme/thmr_theme.dart';
import '../../shared/widgets/network_notice.dart';
import '../../shared/widgets/thmr_panel.dart';
import '../../shared/widgets/track_cover.dart';
import '../listen/widgets/queue_strip.dart' show showQueueEntryDetail;

String? yesterdayPlaybackTime(CollectionItem item) {
  final timestamp = item.playedAtMs;
  if (timestamp == null || timestamp <= 0) return null;
  final time = DateTime.fromMillisecondsSinceEpoch(timestamp, isUtc: true)
      .add(const Duration(hours: 8));
  return '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}';
}

final _yesterdayPlaylistProvider =
    FutureProvider.autoDispose.family<List<CollectionItem>, String>((ref, id) {
  final api = ref.watch(radioApiProvider);
  final beijingTime = DateTime.now().toUtc().add(const Duration(hours: 8));
  final nextMidnight =
      DateTime.utc(beijingTime.year, beijingTime.month, beijingTime.day + 1);
  final timer = Timer(nextMidnight.difference(beijingTime), ref.invalidateSelf);
  ref.onDispose(timer.cancel);
  return api.yesterdayPlaylist(id);
});

class YesterdayPlaylist extends ConsumerStatefulWidget {
  const YesterdayPlaylist({super.key});

  @override
  ConsumerState<YesterdayPlaylist> createState() => _YesterdayPlaylistState();
}

class _YesterdayPlaylistState extends ConsumerState<YesterdayPlaylist> {
  String? _selectedChannelId;

  @override
  Widget build(BuildContext context) {
    // The home shell keeps inactive tabs mounted with their tickers disabled.
    if (!TickerMode.valuesOf(context).enabled) return const SizedBox.shrink();

    final catalog = ref.watch(channelCatalogProvider);
    final activeId = ref.watch(activeStationIdProvider);
    final channels = catalog.valueOrNull ??
        (catalog.hasError
            ? [RadioChannel(id: activeId, name: activeId)]
            : null);
    if (channels == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (channels.isEmpty) {
      return const Center(child: Text('暂无可用频道。'));
    }

    final channel =
        channels.where((entry) => entry.id == _selectedChannelId).firstOrNull ??
            channels.where((entry) => entry.id == activeId).firstOrNull ??
            channels.first;
    final provider = _yesterdayPlaylistProvider(channel.id);
    final playlist = ref.watch(provider);
    final count = playlist.asData?.value.length ?? 0;
    final theme = Theme.of(context);

    void refresh() {
      if (catalog.hasError) ref.invalidate(channelCatalogProvider);
      ref.invalidate(provider);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Semantics(
                label: '频道',
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: channel.id,
                  items: [
                    for (final entry in channels)
                      DropdownMenuItem(
                        value: entry.id,
                        child:
                            Text(entry.name, overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: channels.length > 1
                      ? (id) => setState(() => _selectedChannelId = id)
                      : null,
                ),
              ),
            ),
            if (playlist.hasValue && !playlist.hasError)
              IconButton(
                tooltip: '刷新昨日歌单',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: playlist.isLoading ? null : refresh,
              ),
          ],
        ),
        Text(
          '北京时间 · 按播放顺序'
          '${!playlist.isLoading && count > 0 ? ' · $count 次播放' : ''}',
          style:
              theme.textTheme.bodySmall?.copyWith(color: theme.thmr.mutedInk),
        ),
        const SizedBox(height: 12),
        Expanded(
          child: playlist.when(
            skipLoadingOnRefresh: false,
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => NetworkIssueView(
              networkFailure: isNetworkFailure(error),
              message: '暂时无法读取昨日歌单，请稍后重试。',
              onRetry: refresh,
            ),
            data: (items) {
              if (items.isEmpty) {
                return const Center(child: Text('昨日暂无播放记录。'));
              }
              return ListView.separated(
                key: ValueKey(channel.id),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = items[index];
                  final playedAt = yesterdayPlaybackTime(item);
                  return ThmrPanel(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    frost: false,
                    child: Material(
                      color: Colors.transparent,
                      child: ListTile(
                        contentPadding: EdgeInsets.zero,
                        onTap: () => showQueueEntryDetail(
                          context,
                          QueueEntry(
                            trackId: item.trackId,
                            title:
                                item.title.isEmpty ? item.trackId : item.title,
                            artist: item.artist.isEmpty ? '未知歌手' : item.artist,
                            coverUrl: item.coverUrl,
                            plannedStartMs: 0,
                            plannedEndMs: 0,
                            durationSec: item.durationSec ?? 0,
                          ),
                          index,
                          heading: '昨日歌单 #${index + 1}',
                          album: item.album,
                          durationLabel:
                              (item.durationSec ?? 0) > 0 ? null : '时长未知',
                          playbackLabel: playedAt == null
                              ? '播放时间未记录'
                              : '$playedAt 播放（北京时间）',
                        ),
                        leading: TrackCover(url: item.coverUrl, size: 46),
                        title: Text(
                          item.title.isEmpty ? item.trackId : item.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        isThreeLine: true,
                        subtitle: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(item.artist.isEmpty ? '未知歌手' : item.artist,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            Text(playedAt == null ? '播放时间未记录' : '$playedAt 播放',
                                style: theme.textTheme.labelSmall
                                    ?.copyWith(color: theme.thmr.mutedInk)),
                          ],
                        ),
                        trailing:
                            const Icon(Icons.chevron_right_rounded, size: 18),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
