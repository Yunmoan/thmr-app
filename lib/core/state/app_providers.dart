import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/network_failure.dart';
import '../api/thmr_api.dart';
import '../config.dart';
import '../models/models.dart';
import 'auth_provider.dart';
import 'channel_provider.dart';
import 'collection_cache.dart';
import 'station_provider.dart';

/// `GET /api/meta` — 投票阈值 / 收藏上限以此为准。
final metaProvider = FutureProvider<ThmrMeta>((ref) async {
  final auth = ref.watch(authProvider.notifier);
  return auth.api.meta();
});

/// 当前曲目的收藏状态，换曲时随 trackGeneration 重新查询。
final favoritesStatusProvider =
    FutureProvider.autoDispose<FavoritesStatus>((ref) async {
  final stationId = ref.watch(activeStationIdProvider);
  final trackId =
      ref.watch(stationProvider.select((s) => s.status?.current?.trackId));
  final userId = ref.watch(authProvider.select((s) => s.user?.id));
  if (trackId == null || userId == null) {
    return const FavoritesStatus(
        favorited: false, itemId: null, collectionId: null, collections: []);
  }
  return ref.read(authProvider.notifier).api.favoritesStatus(
        stationId: stationId,
        trackId: trackId,
      );
});

class CollectionCatalog {
  const CollectionCatalog(this.collections,
      {this.offline = false, this.savedAt});

  final List<Collection> collections;
  final bool offline;
  final DateTime? savedAt;
}

/// 收藏写入结束后同步目录与当前曲目的收藏标记，即使发起操作的弹窗已经关闭。
final writeCollectionProvider = Provider((ref) {
  var disposed = false;
  ref.onDispose(() => disposed = true);
  return (Future<void> Function(ThmrApi api) write) async {
    try {
      await write(ref.read(authProvider.notifier).api);
    } finally {
      // 重复收藏或响应中断时，服务端的实际状态也可能已经改变。
      if (!disposed) {
        ref.invalidate(collectionsProvider);
        ref.invalidate(favoritesStatusProvider);
      }
    }
  };
});

/// 我的收藏夹。请求因网络问题无法完成时，以同一账号最近一次成功取得的快照提供只读访问。
final collectionsProvider = FutureProvider<CollectionCatalog>((ref) async {
  final auth = ref.watch(authProvider);
  final userId = auth.user?.id;
  if (userId == null) return const CollectionCatalog([]);
  const cache = CollectionCache();
  final generation = cache.generation(userId);
  var disposed = false;
  ref.onDispose(() => disposed = true);
  bool current() => !disposed && cache.generation(userId) == generation;
  final api = ref.read(authProvider.notifier).api;
  try {
    final list = await api.collections();
    if (current() && ref.read(authProvider).user?.id == userId) {
      try {
        await cache.saveList(userId, list);
      } catch (_) {
        // 本地写入失败时，继续向界面返回已经取得的在线结果。
      }
      unawaited(_warmCollectionDetails(api, userId, list, current));
    }
    return CollectionCatalog(list);
  } catch (error) {
    if (isNetworkFailure(error)) {
      final snapshot = await cache.readList(userId);
      if (snapshot != null) {
        return CollectionCatalog(snapshot.collections,
            offline: true, savedAt: snapshot.savedAt);
      }
    }
    rethrow;
  }
});

Future<void> _warmCollectionDetails(ThmrApi api, String userId,
    List<Collection> collections, bool Function() current) async {
  const cache = CollectionCache();
  for (final folder in collections) {
    if (!current()) return;
    try {
      final existing = await cache.readDetail(userId, folder.id);
      if (existing != null &&
          existing.collection.itemCount == folder.itemCount &&
          existing.collection.updatedAt == folder.updatedAt &&
          DateTime.now().difference(existing.savedAt) <
              const Duration(minutes: 30)) {
        continue;
      }
      final (detail, items) = await api.collectionDetail(folder.id);
      if (!current()) return;
      await cache.saveDetail(userId, detail, items);
    } catch (_) {
      // 列表已可展示，详情预取失败时由详情页自行加载。
      return;
    }
  }
}

final voteEnabledProvider = FutureProvider.autoDispose<bool>((ref) {
  if (!appConfig.featuresVote) return false;
  final api = ref.watch(publicThmrApiProvider);
  return _pollVote(ref, const Duration(seconds: 30), api.voteEnabled);
});

/// 换台、换曲或切换登录身份时立即刷新，其余时间轮询票数。
final voteStatusProvider = FutureProvider.autoDispose<VoteStatus>((ref) {
  final stationId = ref.watch(activeStationIdProvider);
  ref.watch(stationProvider.select((s) => s.trackGeneration));
  ref.watch(authProvider.select((s) => s.user?.id));
  final api = ref.watch(authProvider.notifier).api;
  return _pollVote(
      ref, const Duration(seconds: 8), () => api.voteStatus(stationId));
});

Future<T> _pollVote<T>(
    Ref ref, Duration interval, Future<T> Function() load) async {
  Timer? timer;
  var disposed = false;
  ref.onDispose(() {
    disposed = true;
    timer?.cancel();
  });
  try {
    return await load();
  } finally {
    if (!disposed) timer = Timer(interval, ref.invalidateSelf);
  }
}
