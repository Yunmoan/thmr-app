// Personal collections, public playback history and shared links.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/radio_api.dart';
import '../../core/api/network_failure.dart';
import '../../core/models/models.dart';
import '../../core/state/app_providers.dart';
import '../../core/state/auth_provider.dart';
import '../../core/theme/thmr_theme.dart';
import '../../shared/widgets/thmr_panel.dart';
import '../../shared/widgets/network_notice.dart';
import 'collection_detail.dart';
import 'shared_collection_screen.dart';
import 'yesterday_playlist.dart';

/// 收藏夹列表页。
class CollectionsScreen extends ConsumerStatefulWidget {
  const CollectionsScreen({super.key});

  @override
  ConsumerState<CollectionsScreen> createState() => _CollectionsScreenState();
}

class _CollectionsScreenState extends ConsumerState<CollectionsScreen> {
  bool? _showYesterday;

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    final collections = ref.watch(collectionsProvider);
    final offline = collections.valueOrNull?.offline ?? false;
    final showYesterday = _showYesterday ?? !auth.signedIn;
    final tokens = Theme.of(context).thmr;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('收藏夹',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.w800)),
                const Spacer(),
                IconButton(
                  tooltip: '查看他人分享',
                  icon: const Icon(Icons.link_rounded),
                  onPressed: offline ? null : () => _openShared(context),
                ),
                if (auth.signedIn && !showYesterday)
                  IconButton(
                    tooltip: '新建收藏夹',
                    icon: const Icon(Icons.create_new_folder_outlined),
                    onPressed: offline ? null : () => _newCollection(context),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('我的列表')),
                ButtonSegment(value: true, label: Text('昨日歌单')),
              ],
              selected: {showYesterday},
              showSelectedIcon: false,
              onSelectionChanged: (selection) =>
                  setState(() => _showYesterday = selection.single),
            ),
            const SizedBox(height: 12),
            if (showYesterday)
              const Expanded(child: YesterdayPlaylist())
            else if (!auth.signedIn)
              const Expanded(child: _SignedOutHint())
            else
              Expanded(
                child: collections.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => NetworkIssueView(
                    onRetry: () => ref.invalidate(collectionsProvider),
                    networkFailure: isNetworkFailure(e),
                  ),
                  data: (catalog) {
                    final list = catalog.collections;
                    if (list.isEmpty) {
                      return Column(
                        children: [
                          if (catalog.offline)
                            OfflineCacheBanner(
                              savedAt: catalog.savedAt,
                              onRetry: () =>
                                  ref.invalidate(collectionsProvider),
                            ),
                          Expanded(
                            child: Center(
                              child: Text(
                                catalog.offline
                                    ? '本机缓存中还没有收藏夹'
                                    : '还没有收藏夹,点右上角新建一个吧',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodyMedium
                                    ?.copyWith(color: tokens.mutedInk),
                              ),
                            ),
                          ),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        if (catalog.offline) ...[
                          OfflineCacheBanner(
                            savedAt: catalog.savedAt,
                            onRetry: () => ref.invalidate(collectionsProvider),
                          ),
                          const SizedBox(height: 10),
                        ],
                        Expanded(
                          child: RefreshIndicator(
                            onRefresh: () async {
                              ref.invalidate(collectionsProvider);
                              try {
                                await ref.read(collectionsProvider.future);
                              } catch (_) {}
                            },
                            child: ListView.separated(
                              physics: const AlwaysScrollableScrollPhysics(),
                              itemCount: list.length,
                              separatorBuilder: (_, __) =>
                                  const SizedBox(height: 10),
                              itemBuilder: (context, i) => _CollectionCard(
                                collection: list[i],
                                isDefault: i == 0,
                                readOnly: catalog.offline,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openShared(BuildContext context) async {
    final controller = TextEditingController();
    final slug = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('查看他人分享'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '粘贴分享链接或分享码'),
          onSubmitted: (v) => Navigator.pop(context, v),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('查看')),
        ],
      ),
    );
    if (slug == null || slug.isEmpty) return;
    if (!context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => SharedCollectionScreen(input: slug),
    ));
  }

  Future<void> _newCollection(BuildContext context) async {
    final controller = TextEditingController();
    final created = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('新建收藏夹'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 64,
          decoration: const InputDecoration(
            labelText: '名称(2–64 字符)',
            counterText: '',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('创建')),
        ],
      ),
    );
    if (created != true) return;
    final name = controller.text.trim();
    if (name.length < 2) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('名称至少 2 个字符')));
      return;
    }
    try {
      final api = ref.read(authProvider.notifier).api;
      await api.createCollection(name);
      ref.invalidate(collectionsProvider);
      ref.invalidate(favoritesStatusProvider);
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('创建失败:${e.message}')));
    } catch (error) {
      if (!context.mounted) return;
      if (isNetworkFailure(error)) ref.invalidate(collectionsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('创建失败，请检查网络连接后重试')),
      );
    }
  }
}

/// 未登录引导。
class _SignedOutHint extends StatelessWidget {
  const _SignedOutHint();

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: tokens.accentSoft,
              shape: BoxShape.circle,
              border: Border.all(color: tokens.panelBorder),
            ),
            child: Icon(Icons.person_off_outlined, size: 34, color: tokens.ink),
          ),
          const SizedBox(height: 14),
          Text('尚未登录',
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(color: tokens.ink, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('登录后，把喜欢的曲目收进幻想乡的歌单',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: tokens.mutedInk)),
        ],
      ),
    );
  }
}

/// 收藏夹卡片。
class _CollectionCard extends ConsumerWidget {
  const _CollectionCard({
    required this.collection,
    required this.isDefault,
    required this.readOnly,
  });

  final Collection collection;
  final bool isDefault;
  final bool readOnly;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('删除收藏夹'),
        content: Text(
            '确定删除「${collection.name}」及其中的 ${collection.itemCount} 首收藏吗？此操作无法撤销。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    try {
      await ref.read(authProvider.notifier).api.deleteCollection(collection.id);
      if (!context.mounted) return;
      ref.invalidate(collectionsProvider);
      ref.invalidate(favoritesStatusProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已删除「${collection.name}」')),
      );
    } on ApiException catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('删除失败：${e.message}')),
      );
    } catch (error) {
      if (!context.mounted) return;
      if (isNetworkFailure(error)) ref.invalidate(collectionsProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('删除失败，请检查网络连接后重试')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).thmr;
    return ThmrPanel(
      onTap: () async {
        await Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => CollectionDetailScreen(
            collectionId: collection.id,
            name: collection.name,
            preferOffline: readOnly,
          ),
        ));
        if (!readOnly) ref.invalidate(collectionsProvider);
      },
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: tokens.accentSoft,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              isDefault
                  ? Icons.favorite_rounded
                  : Icons.bookmark_outline_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(collection.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700)),
                    ),
                    if (isDefault) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: tokens.accentSoft,
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text('默认',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                    fontWeight: FontWeight.w700)),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  '${collection.itemCount} 首'
                  '${collection.share.enabled ? ' · 分享中' : ''}',
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: tokens.mutedInk),
                ),
              ],
            ),
          ),
          if (!isDefault && !readOnly)
            IconButton(
              tooltip: '删除收藏夹',
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => _delete(context, ref),
            ),
          Icon(Icons.chevron_right_rounded, color: tokens.mutedInk),
        ],
      ),
    );
  }
}
