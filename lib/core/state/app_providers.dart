import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../config.dart';
import '../models/models.dart';
import 'auth_provider.dart';
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

/// 我的收藏夹列表(登录后)。
final collectionsProvider = FutureProvider<List<Collection>>((ref) async {
  final auth = ref.watch(authProvider);
  if (!auth.signedIn) return const [];
  return ref.read(authProvider.notifier).api.collections();
});

/// 投票状态(公开接口;登录后带 myVote)。
final voteStatusProvider = FutureProvider.autoDispose<VoteStatus>((ref) async {
  ref.watch(stationProvider.select((s) => s.trackGeneration));
  final auth = ref.watch(authProvider.notifier);
  return auth.api.voteStatus(appConfig.stationId);
});
