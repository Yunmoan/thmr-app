// Collection detail: items, sorting, share toggle + link bar, export.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../shared/widgets/focus_outline.dart';
import '../../core/config.dart';
import '../../core/api/network_failure.dart';
import '../../core/models/models.dart';
import '../../core/state/app_providers.dart';
import '../../core/state/auth_provider.dart';
import '../../core/state/collection_cache.dart';
import '../../core/theme/thmr_colors.dart';
import '../../core/theme/thmr_theme.dart';
import '../../shared/widgets/thmr_panel.dart';
import '../../shared/widgets/track_cover.dart';
import '../../shared/widgets/network_notice.dart';
import '../listen/widgets/feedback_sheet.dart';

/// 收藏夹详情:条目列表 + 排序 + 分享开关 + 导出。
class CollectionDetailScreen extends ConsumerStatefulWidget {
  const CollectionDetailScreen({
    super.key,
    required this.collectionId,
    required this.name,
    this.preferOffline = false,
  });

  final String collectionId;
  final String name;
  final bool preferOffline;

  @override
  ConsumerState<CollectionDetailScreen> createState() =>
      _CollectionDetailScreenState();
}

class _CollectionDetailScreenState
    extends ConsumerState<CollectionDetailScreen> {
  String _sort = 'position';
  String _order = 'asc';
  Collection? _collection;
  List<CollectionItem>? _items;
  Object? _error;
  bool _loading = true;
  bool _offline = false;
  DateTime? _cachedAt;

  @override
  void initState() {
    super.initState();
    _load();
  }

  List<CollectionItem> _sortCached(List<CollectionItem> items) {
    final sorted = List<CollectionItem>.of(items);
    sorted.sort((a, b) {
      final comparison = switch (_sort) {
        'title' => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        'artist' => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()),
        'addedAt' => (a.addedAt ?? '').compareTo(b.addedAt ?? ''),
        _ => a.position.compareTo(b.position),
      };
      return comparison != 0 ? comparison : a.position.compareTo(b.position);
    });
    return _order == 'desc' ? sorted.reversed.toList() : sorted;
  }

  Future<void> _load({bool retryOnline = false}) async {
    if (!mounted) return;
    setState(() => _loading = true);
    final userId = ref.read(authProvider).user?.id;
    const cache = CollectionCache();
    if (userId != null && (widget.preferOffline || _offline) && !retryOnline) {
      final snapshot = await cache.readDetail(userId, widget.collectionId);
      if (!mounted) return;
      setState(() {
        _collection = snapshot?.collection;
        _items = snapshot == null ? null : _sortCached(snapshot.items);
        _cachedAt = snapshot?.savedAt;
        _offline = snapshot != null;
        _error = snapshot == null ? StateError('No cached detail') : null;
        _loading = false;
      });
      return;
    }
    try {
      final api = ref.read(authProvider.notifier).api;
      final (c, items) = await api.collectionDetail(widget.collectionId,
          sort: _sort, order: _order);
      if (!mounted) return;
      if (userId != null && ref.read(authProvider).user?.id == userId) {
        try {
          await cache.saveDetail(userId, c, items);
        } catch (_) {}
      }
      if (!mounted) return;
      setState(() {
        _collection = c;
        _items = items;
        _error = null;
        _offline = false;
        _cachedAt = null;
      });
    } catch (e) {
      final snapshot = userId != null && isNetworkFailure(e)
          ? await cache.readDetail(userId, widget.collectionId)
          : null;
      if (!mounted) return;
      setState(() {
        _collection = snapshot?.collection;
        _items = snapshot == null ? null : _sortCached(snapshot.items);
        _cachedAt = snapshot?.savedAt;
        _offline = snapshot != null;
        _error = snapshot == null ? e : null;
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markOfflineIfNetwork(Object error) async {
    if (!isNetworkFailure(error) || !mounted) return;
    final userId = ref.read(authProvider).user?.id;
    final snapshot = userId == null
        ? null
        : await const CollectionCache().readDetail(userId, widget.collectionId);
    if (!mounted) return;
    setState(() {
      _offline = true;
      _cachedAt = snapshot?.savedAt;
    });
  }

  Future<void> _removeItem(CollectionItem item) async {
    try {
      final api = ref.read(authProvider.notifier).api;
      await api.removeItem(widget.collectionId, item.id);
      if (!mounted) return;
      _load();
      ref.invalidate(collectionsProvider);
    } catch (error) {
      await _markOfflineIfNetwork(error);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('移除失败,稍后再试')));
    }
  }

  TrackRef _trackRef(CollectionItem item) => TrackRef(
        trackId: item.trackId,
        title: item.title,
        artist: item.artist,
        coverUrl: item.coverUrl,
      );

  String _copyableTrackInfo(CollectionItem item) {
    return trackSearchText(
      title: item.title,
      artist: item.artist,
      album: item.album,
    );
  }

  Future<void> _copyTrackInfo(CollectionItem item) async {
    await Clipboard.setData(
      ClipboardData(text: _copyableTrackInfo(item)),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('歌曲信息已复制')));
  }

  void _showFeedback(CollectionItem item) {
    showFeedbackSheet(
      context,
      track: _trackRef(item),
      stationId: item.stationId,
    );
  }

  Future<void> _export(BuildContext context, String format) async {
    try {
      final api = ref.read(authProvider.notifier).api;
      final content = await api.exportContent(widget.collectionId, format);
      if (!context.mounted) return;
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('导出 ${format.toUpperCase()}'),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: SelectableText(
                content.isEmpty ? '(空)' : content,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: content));
                Navigator.of(dialogContext).pop();
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('已复制到剪贴板')));
              },
              child: const Text('复制全部'),
            ),
            FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('关闭')),
          ],
        ),
      );
    } catch (error) {
      await _markOfflineIfNetwork(error);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('导出失败,稍后再试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    final share = _collection?.share;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(widget.name),
        actions: [
          PopupMenuButton<String>(
            tooltip: '排序',
            icon: const Icon(Icons.sort_rounded),
            onSelected: (v) {
              setState(() {
                _sort = v;
                _order = 'asc';
              });
              _load();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'position',
                  child: AncestorFocusOutline(child: Text('手动顺序'))),
              PopupMenuItem(
                  value: 'title',
                  child: AncestorFocusOutline(child: Text('曲名'))),
              PopupMenuItem(
                  value: 'artist',
                  child: AncestorFocusOutline(child: Text('艺术家'))),
              PopupMenuItem(
                  value: 'addedAt',
                  child: AncestorFocusOutline(child: Text('添加时间'))),
            ],
          ),
          PopupMenuButton<String>(
            tooltip: '导出',
            enabled: !_offline,
            icon: const Icon(Icons.ios_share_rounded),
            onSelected: (v) => _export(context, v),
            itemBuilder: (_) => const [
              PopupMenuItem(
                  value: 'json',
                  child: AncestorFocusOutline(child: Text('JSON'))),
              PopupMenuItem(
                  value: 'm3u',
                  child: AncestorFocusOutline(child: Text('M3U 播放列表'))),
              PopupMenuItem(
                  value: 'csv',
                  child: AncestorFocusOutline(child: Text('CSV'))),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
              child: Row(
                children: [
                  Text(
                    '${_collection?.itemCount ?? _items?.length ?? 0} 首',
                    style: Theme.of(context)
                        .textTheme
                        .bodySmall
                        ?.copyWith(color: tokens.mutedInk),
                  ),
                  const Spacer(),
                  if (share != null && !_offline)
                    _ShareToggle(
                      enabled: share.enabled,
                      onChanged: (v) async {
                        try {
                          final api = ref.read(authProvider.notifier).api;
                          await api.setShare(widget.collectionId, enabled: v);
                          _load();
                        } catch (error) {
                          await _markOfflineIfNetwork(error);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('操作失败,稍后再试')));
                        }
                      },
                    ),
                ],
              ),
            ),
            if (share != null &&
                !_offline &&
                share.enabled &&
                share.slug.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
                child: _ShareLinkBar(slug: share.slug),
              ),
            if (_offline)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 0),
                child: OfflineCacheBanner(
                  savedAt: _cachedAt,
                  onRetry: () => _load(retryOnline: true),
                ),
              ),
            Expanded(child: _buildList(context, tokens)),
          ],
        ),
      ),
    );
  }

  Widget _buildList(BuildContext context, ThmrTokens tokens) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return NetworkIssueView(
        onRetry: () => _load(retryOnline: true),
        hasCache: widget.preferOffline,
        networkFailure: widget.preferOffline || isNetworkFailure(_error!),
      );
    }
    final items = _items ?? const [];
    if (items.isEmpty) {
      return Center(
        child: Text('收藏夹还是空的 · 去「曲库」挑几首吧',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: tokens.mutedInk)),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.all(18),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final it = items[i];
        return ThmrPanel(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          frost: false,
          child: Row(
            children: [
              TrackCover(url: _offline ? '' : it.coverUrl, size: 46, radius: 8),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(it.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700, color: tokens.ink)),
                    Text(
                      '${it.artist}${it.album.isEmpty ? '' : ' · ${it.album}'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: tokens.mutedInk),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: [
                        _TrackItemAction(
                          icon: Icons.feedback_outlined,
                          label: '反馈',
                          onPressed: _offline ? null : () => _showFeedback(it),
                        ),
                        _TrackItemAction(
                          icon: Icons.copy_rounded,
                          label: '复制信息',
                          onPressed: () => _copyTrackInfo(it),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (it.durationSec != null)
                Text(formatDuration(it.durationSec),
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: tokens.mutedInk)),
              if (!_offline)
                IconButton(
                  tooltip: '移除',
                  icon: const Icon(Icons.bookmark_remove_outlined, size: 20),
                  onPressed: () => _removeItem(it),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TrackItemAction extends StatelessWidget {
  const _TrackItemAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        minimumSize: Size.zero,
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        textStyle: Theme.of(context).textTheme.labelSmall,
      ),
      icon: Icon(icon, size: 14),
      label: Text(label),
    );
  }
}

/// Share link bar: visible URL, copy to clipboard, system share sheet.
class _ShareLinkBar extends StatelessWidget {
  const _ShareLinkBar({required this.slug});

  final String slug;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    final url = '$shareWebOrigin/share/$slug';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: tokens.panelSoft,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tokens.panelBorder),
      ),
      child: Row(
        children: [
          Icon(Icons.link_rounded, size: 16, color: tokens.mutedInk),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              url,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: tokens.ink),
            ),
          ),
          IconButton(
            tooltip: '复制链接',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.copy_rounded, size: 16),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: url));
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('分享链接已复制')));
            },
          ),
          IconButton(
            tooltip: '系统分享',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.share_rounded, size: 16),
            onPressed: () => Share.share(url, subject: '东方音乐电台 THMR · 收藏夹分享'),
          ),
        ],
      ),
    );
  }
}

/// 分享开关。
class _ShareToggle extends StatelessWidget {
  const _ShareToggle({required this.enabled, required this.onChanged});

  final bool enabled;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('分享',
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
        FocusOutline(child: Switch(value: enabled, onChanged: onChanged)),
      ],
    );
  }
}
