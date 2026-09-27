// Collection detail: items, sorting, share toggle + link bar, export.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/config.dart';
import '../../core/models/models.dart';
import '../../core/state/app_providers.dart';
import '../../core/state/auth_provider.dart';
import '../../core/theme/thmr_colors.dart';
import '../../core/theme/thmr_theme.dart';
import '../../shared/widgets/thmr_panel.dart';
import '../../shared/widgets/track_cover.dart';

/// 收藏夹详情:条目列表 + 排序 + 分享开关 + 导出。
class CollectionDetailScreen extends ConsumerStatefulWidget {
  const CollectionDetailScreen({
    super.key,
    required this.collectionId,
    required this.name,
  });

  final String collectionId;
  final String name;

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(authProvider.notifier).api;
      final (c, items) =
          await api.collectionDetail(widget.collectionId, sort: _sort, order: _order);
      setState(() {
        _collection = c;
        _items = items;
        _error = null;
      });
    } catch (e) {
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _removeItem(CollectionItem item) async {
    try {
      final api = ref.read(authProvider.notifier).api;
      await api.removeItem(widget.collectionId, item.id);
      _load();
      ref.invalidate(collectionsProvider);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('移除失败,稍后再试')));
    }
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
                ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('已复制到剪贴板')));
              },
              child: const Text('复制全部'),
            ),
            FilledButton(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: const Text('关闭')),
          ],
        ),
      );
    } catch (_) {
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
              PopupMenuItem(value: 'position', child: Text('手动顺序')),
              PopupMenuItem(value: 'title', child: Text('曲名')),
              PopupMenuItem(value: 'artist', child: Text('艺术家')),
              PopupMenuItem(value: 'addedAt', child: Text('添加时间')),
            ],
          ),
          PopupMenuButton<String>(
            tooltip: '导出',
            icon: const Icon(Icons.ios_share_rounded),
            onSelected: (v) => _export(context, v),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'json', child: Text('JSON')),
              PopupMenuItem(value: 'm3u', child: Text('M3U 播放列表')),
              PopupMenuItem(value: 'csv', child: Text('CSV')),
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
                  if (share != null)
                    _ShareToggle(
                      enabled: share.enabled,
                      onChanged: (v) async {
                        try {
                          final api = ref.read(authProvider.notifier).api;
                          await api.setShare(widget.collectionId, enabled: v);
                          _load();
                        } catch (_) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('操作失败,稍后再试')));
                        }
                      },
                    ),
                ],
              ),
            ),
            if (share != null && share.enabled && share.slug.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
                child: _ShareLinkBar(slug: share.slug),
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
      return Center(
        child: TextButton.icon(
          onPressed: _load,
          icon: const Icon(Icons.refresh_rounded),
          label: const Text('加载失败,点此重试'),
        ),
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
              TrackCover(url: it.coverUrl, size: 46, radius: 8),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(it.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .titleSmall
                            ?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: tokens.ink)),
                    Text(
                      '${it.artist}${it.album.isEmpty ? '' : ' · ${it.album}'}',
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
              if (it.durationSec != null)
                Text(formatDuration(it.durationSec),
                    style: Theme.of(context)
                        .textTheme
                        .labelSmall
                        ?.copyWith(color: tokens.mutedInk)),
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
            onPressed: () =>
                Share.share(url, subject: '东方音乐电台 THMR · 收藏夹分享'),
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
        Switch(value: enabled, onChanged: onChanged),
      ],
    );
  }
}
