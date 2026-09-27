// Public shared collection viewer (web /share/:slug equivalent).
// 404 = unknown slug, 410 = share expired.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/radio_api.dart';
import '../../core/models/models.dart';
import '../../core/state/auth_provider.dart';
import '../../core/theme/thmr_colors.dart';
import '../../core/theme/thmr_theme.dart';
import '../../shared/widgets/thmr_panel.dart';
import '../../shared/widgets/track_cover.dart';

class SharedCollectionScreen extends ConsumerStatefulWidget {
  const SharedCollectionScreen({super.key, required this.input});

  /// Raw share link or bare slug.
  final String input;

  @override
  ConsumerState<SharedCollectionScreen> createState() =>
      _SharedCollectionScreenState();
}

class _SharedCollectionScreenState
    extends ConsumerState<SharedCollectionScreen> {
  Collection? _collection;
  List<CollectionItem>? _items;
  Object? _error;
  int? _statusCode;
  bool _loading = true;

  String get _slug {
    final raw = widget.input.trim();
    const marker = '/share/';
    final i = raw.indexOf(marker);
    if (i >= 0) {
      final tail = raw.substring(i + marker.length);
      return tail.split('?').first.split('/').first;
    }
    return raw;
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final api = ref.read(authProvider.notifier).api;
      final (c, items) = await api.sharedCollection(_slug);
      setState(() {
        _collection = c;
        _items = items;
        _error = null;
      });
    } on ApiException catch (e) {
      setState(() {
        _error = e;
        _statusCode = e.statusCode;
      });
    } catch (e) {
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    return Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        title: Text(_collection?.name ?? '他人分享'),
        actions: [
          IconButton(
            tooltip: '刷新',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _load,
          ),
        ],
      ),
      body: _buildBody(context, tokens),
    );
  }

  Widget _buildBody(BuildContext context, ThmrTokens tokens) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      final expired = _statusCode == 410;
      final missing = _statusCode == 404;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                expired ? Icons.hourglass_bottom_rounded : Icons.link_off_rounded,
                size: 40,
                color: tokens.mutedInk,
              ),
              const SizedBox(height: 12),
              Text(
                expired ? '分享已过期,请让对方重新生成' : (missing ? '分享不存在或链接有误' : '加载失败,请检查网络'),
                textAlign: TextAlign.center,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: tokens.mutedInk),
              ),
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded, size: 16),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    final items = _items ?? const [];
    final desc = _collection?.description ?? '';
    return ListView(
      padding: const EdgeInsets.all(18),
      children: [
        if (desc.isNotEmpty)
          Text(
            desc,
            style: Theme.of(context)
                .textTheme
                .bodySmall
                ?.copyWith(color: tokens.mutedInk),
          ),
        const SizedBox(height: 12),
        Text('${items.length} 首 · 由 ${_collection?.itemCount ?? items.length} 首分享',
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: tokens.mutedInk)),
        const SizedBox(height: 12),
        for (final it in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ThmrPanel(
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
                                ?.copyWith(fontWeight: FontWeight.w700)),
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
                ],
              ),
            ),
          ),
      ],
    );
  }
}
