// Collections list page: folders, new-folder dialog, shared-links viewer.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/radio_api.dart';
import '../../core/models/models.dart';
import '../../core/state/app_providers.dart';
import '../../core/state/auth_provider.dart';
import '../../core/theme/thmr_theme.dart';
import '../../shared/widgets/thmr_panel.dart';
import 'collection_detail.dart';
import 'shared_collection_screen.dart';

/// 收藏夹列表页。
class CollectionsScreen extends ConsumerWidget {
  const CollectionsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    final collections = ref.watch(collectionsProvider);
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
                  onPressed: () => _openShared(context),
                ),
                if (auth.signedIn)
                  IconButton(
                    tooltip: '新建收藏夹',
                    icon: const Icon(Icons.create_new_folder_outlined),
                    onPressed: () => _newCollection(context, ref),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (!auth.signedIn)
              const _SignedOutHint()
            else
              Expanded(
                child: collections.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(
                    child: TextButton.icon(
                      onPressed: () => ref.invalidate(collectionsProvider),
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('加载失败,点此重试'),
                    ),
                  ),
                  data: (list) {
                    if (list.isEmpty) {
                      return Center(
                        child: Text('还没有收藏夹,点右上角新建一个吧',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(color: tokens.mutedInk)),
                      );
                    }
                    return RefreshIndicator(
                      onRefresh: () async =>
                          ref.invalidate(collectionsProvider),
                      child: ListView.separated(
                        itemCount: list.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, i) => _CollectionCard(
                            collection: list[i], isDefault: i == 0),
                      ),
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

  Future<void> _newCollection(BuildContext context, WidgetRef ref) async {
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
    }
  }
}

/// 未登录引导(立绘 + 文案)。
class _SignedOutHint extends ConsumerWidget {
  const _SignedOutHint();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = Theme.of(context).thmr;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(
            opacity: 0.55,
            child: Image.asset('assets/brand/background_alt.png',
                height: 200, fit: BoxFit.contain),
          ),
          const SizedBox(height: 10),
          Text('登录后,把喜欢的曲目收进幻想乡的歌单',
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
  const _CollectionCard({required this.collection, required this.isDefault});

  final Collection collection;
  final bool isDefault;

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
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('删除失败，请稍后重试')),
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
          ),
        ));
        ref.invalidate(collectionsProvider);
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
          if (!isDefault)
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
