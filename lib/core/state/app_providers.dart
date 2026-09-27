import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/network_failure.dart';
import '../api/thmr_api.dart';
import '../config.dart';
import '../models/models.dart';
import 'auth_provider.dart';
import 'collection_cache.dart';
import 'station_provider.dart';

/// `GET /api/meta` — 投票阈值 / 收藏上限以此为准。
final metaProvider = FutureProvider<ThmrMeta>((ref) async {
  final auth = ref.watch(authProvider.notifier);
  return auth.api.meta();
});

/// 当前曲收藏状态(9.1)— 跟随 trackGeneration 在换曲后自动重查。
final favoritesStatusProvider =
    FutureProvider.autoDispose<FavoritesStatus>((ref) async {
  // 依赖换曲计数:换曲 → invalidate
  ref.watch(stationProvider.select((s) => s.trackGeneration));
  final auth = ref.watch(authProvider);
  if (!auth.signedIn) {
    return const FavoritesStatus(
        favorited: false, itemId: null, collectionId: null, collections: []);
  }
  final st = ref.watch(stationProvider).status;
  final cur = st?.current;
  if (cur == null) {
    return const FavoritesStatus(
        favorited: false, itemId: null, collectionId: null, collections: []);
  }
  return ref.read(authProvider.notifier).api.favoritesStatus(
        stationId: appConfig.stationId,
        trackId: cur.trackId,
      );
});

class CollectionCatalog {
  const CollectionCatalog(this.collections,
      {this.offline = false, this.savedAt});

  final List<Collection> collections;
  final bool offline;
  final DateTime? savedAt;
}

/// My collections, with the last successful account-scoped snapshot as a
/// read-only fallback when a request cannot reach the server.
final collectionsProvider = FutureProvider<CollectionCatalog>((ref) async {
  final auth = ref.watch(authProvider);
  final userId = auth.user?.id;
  if (userId == null) return const CollectionCatalog([]);
  const cache = CollectionCache();
  final api = ref.read(authProvider.notifier).api;
  try {
    final list = await api.collections();
    if (ref.read(authProvider).user?.id == userId) {
      try {
        await cache.saveList(userId, list);
      } catch (_) {
        // A storage failure must not hide a successful online response.
      }
      unawaited(_warmCollectionDetails(api, userId, list));
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

Future<void> _warmCollectionDetails(
    ThmrApi api, String userId, List<Collection> collections) async {
  const cache = CollectionCache();
  final generation = cache.generation(userId);
  for (final folder in collections) {
    if (cache.generation(userId) != generation) return;
    try {
      final existing = await cache.readDetail(userId, folder.id);
      if (existing != null &&
          existing.collection.updatedAt == folder.updatedAt &&
          DateTime.now().difference(existing.savedAt) <
              const Duration(minutes: 30)) {
        continue;
      }
      final (detail, items) = await api.collectionDetail(folder.id);
      if (cache.generation(userId) != generation) return;
      await cache.saveDetail(userId, detail, items);
    } catch (_) {
      // Prefetch is best-effort. The visible list is already available.
      return;
    }
  }
}

/// 投票状态(公开接口;登录后带 myVote)。
final voteStatusProvider = FutureProvider.autoDispose<VoteStatus>((ref) async {
  ref.watch(stationProvider.select((s) => s.trackGeneration));
  final auth = ref.watch(authProvider.notifier);
  return auth.api.voteStatus(appConfig.stationId);
});
