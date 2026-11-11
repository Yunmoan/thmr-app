import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/radio_api.dart';
import '../../core/api/network_failure.dart';
import '../../core/models/models.dart';
import '../../core/state/auth_provider.dart';
import '../../core/state/channel_provider.dart';
import '../../core/theme/thmr_colors.dart';
import '../../core/theme/thmr_theme.dart';
import '../../shared/widgets/thmr_panel.dart';
import '../../shared/widgets/track_cover.dart';
import '../../shared/widgets/network_notice.dart';

const _sortOptions = <(String, String)>[
  ('title', '按曲名'),
  ('artist', '按艺术家'),
  ('path', '按路径'),
  ('duration-desc', '时长 · 长→短'),
  ('duration-asc', '时长 · 短→长'),
];

/// 曲库搜索(经账号后端代理 Radio 后端)。
class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  final _controller = TextEditingController();
  String _sort = 'title';
  List<LibraryTrack>? _results;
  Object? _error;
  bool _loading = false;
  int _searchRevision = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final auth = ref.read(authProvider);
    if (!auth.signedIn) return;
    final stationId = ref.read(activeStationIdProvider);
    final revision = ++_searchRevision;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = ref.read(authProvider.notifier).api;
      final tracks = await api.searchTracks(
        stationId: stationId,
        q: _controller.text.trim(),
        sort: _sort,
        pageSize: 100,
      );
      if (!mounted || revision != _searchRevision) return;
      setState(() => _results = tracks);
    } catch (e) {
      if (!mounted || revision != _searchRevision) return;
      setState(() => _error = e);
    } finally {
      if (mounted && revision == _searchRevision) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final stationId = ref.watch(activeStationIdProvider);
    ref.listen(activeStationIdProvider, (_, __) {
      if (_results == null && _error == null && !_loading) return;
      _searchRevision++;
      setState(() {
        _results = null;
        _error = null;
        _loading = false;
      });
      _search();
    });
    final auth = ref.watch(authProvider);
    final tokens = Theme.of(context).thmr;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Column(
          children: [
            Text('THMR 音乐数据库',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 12),
            // 搜索行
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _search(),
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.search_rounded),
                      hintText: '搜索曲名 / 艺术家 / 专辑…',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                PopupMenuButton<String>(
                  initialValue: _sort,
                  tooltip: '排序',
                  onSelected: (v) {
                    setState(() => _sort = v);
                    _search();
                  },
                  itemBuilder: (_) => [
                    for (final (v, label) in _sortOptions)
                      PopupMenuItem(value: v, child: Text(label)),
                  ],
                  icon: const Icon(Icons.sort_rounded),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (!auth.signedIn)
              Expanded(
                child: _NotSignedIn(onSignInHint: () {}),
              )
            else
              Expanded(
                child: _buildBody(context, tokens, stationId),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ThmrTokens tokens, String stationId) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return NetworkIssueView(
        onRetry: _search,
        networkFailure: isNetworkFailure(_error!),
        message: isNetworkFailure(_error!) ? '曲库搜索需要联网。请检查网络连接后重试。' : null,
      );
    }
    final results = _results;
    if (results == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Opacity(
              opacity: 0.5,
              child: Image.asset('assets/brand/logo.png', width: 88),
            ),
            const SizedBox(height: 14),
            Text('输入关键词,探索幻想乡的曲库',
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: tokens.mutedInk)),
          ],
        ),
      );
    }
    if (results.isEmpty) {
      return Center(
        child: Text('没有找到相关曲目',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: tokens.mutedInk)),
      );
    }
    return ListView.separated(
      itemCount: results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) =>
          _LibraryTile(track: results[i], stationId: stationId),
    );
  }
}

class _LibraryTile extends ConsumerWidget {
  const _LibraryTile({required this.track, required this.stationId});

  final LibraryTrack track;
  final String stationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).thmr;
    return ThmrPanel(
      onTap: () => _showAddDialog(context, ref),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          TrackCover(url: track.coverUrl, size: 46, radius: 8),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.w700)),
                Text(
                  '${track.artist}${track.album.isEmpty ? '' : ' · ${track.album}'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: tokens.mutedInk),
                ),
              ],
            ),
          ),
          if (track.durationSec != null)
            Text(
              formatDuration(track.durationSec),
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: tokens.mutedInk,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          IconButton(
            tooltip: '添加到收藏夹',
            icon: const Icon(Icons.bookmark_add_outlined, size: 20),
            onPressed: () => _showAddDialog(context, ref),
          ),
        ],
      ),
    );
  }

  void _showAddDialog(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => _AddToCollectionSheet(track: track, stationId: stationId),
    );
  }
}

/// 添加到收藏夹(选夹)。
class _AddToCollectionSheet extends ConsumerStatefulWidget {
  const _AddToCollectionSheet({required this.track, required this.stationId});

  final LibraryTrack track;
  final String stationId;

  @override
  ConsumerState<_AddToCollectionSheet> createState() =>
      _AddToCollectionSheetState();
}

class _AddToCollectionSheetState extends ConsumerState<_AddToCollectionSheet> {
  List<Collection>? _collections;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final api = ref.read(authProvider.notifier).api;
      final collections = await api.collections();
      if (!mounted) return;
      setState(() => _collections = collections);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '收藏夹加载失败');
    }
  }

  Future<void> _add(Collection c) async {
    setState(() => _busy = true);
    try {
      final api = ref.read(authProvider.notifier).api;
      await api.addToCollection(c.id,
          stationId: widget.stationId, trackId: widget.track.trackId);
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('已加入「${c.name}」')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content:
              Text(e.statusCode == 409 ? '已在该收藏夹中' : '添加失败:${e.message}')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('网络异常,稍后再试')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final collections = _collections;
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 4, 22, 10),
            child: Text('添加到收藏夹',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800)),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(22),
              child: Text(_error!),
            )
          else if (collections == null)
            const Padding(
              padding: EdgeInsets.all(28),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            ...collections.map(
              (c) => ListTile(
                leading: Icon(
                  c.share.enabled
                      ? Icons.bookmark_rounded
                      : Icons.bookmark_border_rounded,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(c.name),
                subtitle: Text('${c.itemCount} 首'),
                onTap: _busy ? null : () => _add(c),
              ),
            ),
          const SizedBox(height: 10),
        ],
      ),
    );
  }
}

class _NotSignedIn extends StatelessWidget {
  const _NotSignedIn({required this.onSignInHint});

  final VoidCallback onSignInHint;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline_rounded, size: 40, color: tokens.mutedInk),
          const SizedBox(height: 12),
          Text('曲库搜索需要登录后使用',
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: tokens.mutedInk)),
        ],
      ),
    );
  }
}
