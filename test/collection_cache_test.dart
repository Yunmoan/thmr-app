import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thmr_app/core/api/network_failure.dart';
import 'package:thmr_app/core/models/models.dart';
import 'package:thmr_app/core/state/collection_cache.dart';

void main() {
  const folder = Collection(
    id: 'favorites',
    name: '收藏',
    description: '',
    position: 0,
    itemCount: 1,
    createdAt: null,
    updatedAt: '2026-09-27T00:00:00Z',
    share: ShareInfo(enabled: false, slug: '', expiresAt: null),
  );
  const track = CollectionItem(
    id: 'item-1',
    stationId: 'main',
    trackId: 'track-1',
    position: 0,
    title: 'Necro Fantasia',
    artist: 'ZUN',
    album: '',
    durationSec: 220,
    coverUrl: '',
    addedAt: null,
  );

  test('collection snapshots survive cache recreation and stay account-scoped',
      () async {
    SharedPreferences.setMockInitialValues({});
    const cache = CollectionCache();
    await cache.saveList('user-a', [folder]);
    await cache.saveDetail('user-a', folder, [track]);

    final list = await const CollectionCache().readList('user-a');
    final detail =
        await const CollectionCache().readDetail('user-a', 'favorites');
    expect(list?.collections.single.name, '收藏');
    expect(detail?.items.single.title, 'Necro Fantasia');
    expect(list?.savedAt, isNotNull);
    expect(await cache.readList('user-b'), isNull);
    expect(await cache.readDetail('user-b', 'favorites'), isNull);

    await cache.clearUser('user-a');
    expect(await cache.readList('user-a'), isNull);
    expect(await cache.readDetail('user-a', 'favorites'), isNull);
  });

  test('removing a folder from the online list prunes its offline detail',
      () async {
    SharedPreferences.setMockInitialValues({});
    const cache = CollectionCache();
    await cache.saveList('user-a', [folder]);
    await cache.saveDetail('user-a', folder, [track]);
    await cache.saveList('user-a', []);
    expect(await cache.readDetail('user-a', 'favorites'), isNull);
  });

  test('network failures are distinguished from HTTP responses', () {
    final request = RequestOptions(path: '/api/me/collections');
    expect(isNetworkFailure(const SocketException('offline')), isTrue);
    expect(
      isNetworkFailure(DioException(
        requestOptions: request,
        type: DioExceptionType.connectionTimeout,
      )),
      isTrue,
    );
    expect(
      isNetworkFailure(DioException(
        requestOptions: request,
        type: DioExceptionType.badResponse,
        response: Response(requestOptions: request, statusCode: 401),
      )),
      isFalse,
    );
  });
}
