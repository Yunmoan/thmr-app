// Public shared collection viewer (web /share/:slug equivalent).
// 404 = unknown slug, 410 = share expired.

import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import '../../shared/widgets/loading_skeleton.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/api/radio_api.dart';
import '../../core/api/network_failure.dart';
import '../../core/config.dart';
import '../../core/models/models.dart';
import '../../core/state/auth_provider.dart';
import '../../core/theme/thmr_colors.dart';
import '../../core/theme/thmr_theme.dart';
import '../../shared/widgets/thmr_panel.dart';
import '../../shared/widgets/track_cover.dart';
import '../../shared/widgets/network_notice.dart';

/// Accept an official share URL or a bare share code, never an arbitrary URL.
String? parseShareSlug(String input) {
  final raw = input.trim();
  if (raw.isEmpty) return null;
  final uri = Uri.tryParse(raw);
  if (uri == null) return null;
  String slug;
  if (uri.hasScheme) {
    if (uri.scheme != 'https' || uri.host != Uri.parse(shareWebOrigin).host) {
      return null;
    }
    if (uri.pathSegments.length != 2 || uri.pathSegments.first != 'share') {
      return null;
    }
    slug = uri.pathSegments.last;
  } else if (raw.startsWith('/share/')) {
    final parts = uri.pathSegments;
    if (parts.length != 2 || parts.first != 'share') return null;
    slug = parts.last;
  } else {
    slug = raw;
  }
  return RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(slug) ? slug : null;
}

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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
      _statusCode = null;
    });
    final slug = parseShareSlug(widget.input);
    if (slug == null) {
      setState(() {
        _error = const FormatException('Invalid share link');
        _loading = false;
      });
      return;
    }
    try {
      final api = ref.read(authProvider.notifier).api;
      final (c, items) = await api.sharedCollection(slug);
      if (!mounted) return;
      setState(() {
        _collection = c;
        _items = items;
        _error = null;
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e;
        _statusCode = e.statusCode;
      });
    } catch (e) {
      debugPrint('Shared collection $slug failed: $e');
      if (!mounted) return;
      setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openInBrowser() async {
    final slug = parseShareSlug(widget.input);
    if (slug == null) return;
    try {
      final opened = await launchUrl(Uri.parse('$shareWebOrigin/share/$slug'),
          mode: LaunchMode.externalApplication);
      if (opened || !mounted) return;
    } catch (_) {
      if (!mounted) return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('无法打开浏览器，请检查设备是否安装浏览器')),
    );
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
      return const TrackListSkeleton(padding: EdgeInsets.all(18));
    }
    if (_error != null) {
      if (isNetworkFailure(_error!)) {
        final slug = parseShareSlug(widget.input);
        if (slug != null && (Platform.isAndroid || Platform.isIOS)) {
          return Column(
            children: [
              Material(
                color: tokens.panelSoft,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded,
                          size: 18, color: tokens.mutedInk),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text('接口连接失败，已切换网页查看',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: tokens.mutedInk)),
                      ),
                      IconButton(
                        tooltip: '重试接口',
                        onPressed: _load,
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                      IconButton(
                        tooltip: '在浏览器中打开',
                        onPressed: _openInBrowser,
                        icon: const Icon(Icons.open_in_browser_rounded),
                      ),
                    ],
                  ),
                ),
              ),
              Expanded(
                child: InAppWebView(
                  initialUrlRequest: URLRequest(
                    url: WebUri('$shareWebOrigin/share/$slug'),
                  ),
                ),
              ),
            ],
          );
        }
        return Column(
          children: [
            Expanded(
              child: NetworkIssueView(
                onRetry: _load,
                message: '无法连接 thmr.yunmoan.cn。请检查该网站能否在手机浏览器打开。',
              ),
            ),
            TextButton.icon(
              onPressed: _openInBrowser,
              icon: const Icon(Icons.open_in_browser_rounded),
              label: const Text('在浏览器中打开分享'),
            ),
            const SizedBox(height: 12),
          ],
        );
      }
      final invalid = _error is FormatException;
      final expired = _statusCode == 410;
      final missing = _statusCode == 404;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                expired
                    ? Icons.hourglass_bottom_rounded
                    : Icons.link_off_rounded,
                size: 40,
                color: tokens.mutedInk,
              ),
              const SizedBox(height: 12),
              Text(
                invalid
                    ? '请输入正确的分享码或官方分享链接'
                    : expired
                        ? '分享已过期,请让对方重新生成'
                        : (missing ? '分享不存在或链接有误' : '服务暂时无法加载分享'),
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
        Text(
            '${items.length} 首 · 由 ${_collection?.itemCount ?? items.length} 首分享',
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
