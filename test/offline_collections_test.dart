import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thmr_app/core/api/thmr_api.dart';
import 'package:thmr_app/core/models/models.dart';
import 'package:thmr_app/core/state/app_providers.dart';
import 'package:thmr_app/core/state/auth_provider.dart';
import 'package:thmr_app/core/theme/thmr_theme.dart';
import 'package:thmr_app/features/collections/collections_screen.dart';

const _user = ThmrUser(
  id: 'account-a',
  naidsId: 'naids-a',
  username: 'alice',
  nickname: 'Alice',
  email: '',
  realnameVerified: false,
  createdAt: null,
  needsNickname: false,
);

const _collection = Collection(
  id: 'favorites',
  name: '收藏',
  description: '',
  position: 0,
  itemCount: 0,
  createdAt: null,
  updatedAt: null,
  share: ShareInfo(enabled: false, slug: '', expiresAt: null),
);

const _secondCollection = Collection(
  id: 'other',
  name: '夜雀歌单',
  description: '',
  position: 1,
  itemCount: 0,
  createdAt: null,
  updatedAt: null,
  share: ShareInfo(enabled: false, slug: '', expiresAt: null),
);

class _FakeApi extends ThmrApi {
  bool offline = false;
  bool includeExtra = false;

  @override
  Future<ThmrUser?> me() async {
    if (offline) throw _connectionError();
    return _user;
  }

  @override
  Future<List<Collection>> collections() async {
    if (offline) throw _connectionError();
    return [_collection, if (includeExtra) _secondCollection];
  }

  @override
  Future<(Collection, List<CollectionItem>)> collectionDetail(String cid,
          {String sort = 'position', String order = 'asc'}) async =>
      (_collection, <CollectionItem>[]);

  DioException _connectionError() => DioException(
        requestOptions: RequestOptions(path: '/api/me/collections'),
        type: DioExceptionType.connectionError,
      );
}

Future<void> _waitForAuth(ProviderContainer container) async {
  final ready = Completer<void>();
  final subscription = container.listen<AuthState>(authProvider, (_, next) {
    if (next.initialized && !ready.isCompleted) ready.complete();
  }, fireImmediately: true);
  await ready.future.timeout(const Duration(seconds: 2));
  subscription.close();
}

void main() {
  test('network loss serves the saved list and restores the account on restart',
      () async {
    SharedPreferences.setMockInitialValues({'thmr_session_token': 'token-a'});
    final api = _FakeApi();
    final container = ProviderContainer(overrides: [
      authProvider.overrideWith((ref) => AuthController(client: api)),
    ]);
    await _waitForAuth(container);
    final online = await container.read(collectionsProvider.future);
    expect(online.offline, isFalse);
    expect(online.collections.single.name, '收藏');

    api.offline = true;
    container.invalidate(collectionsProvider);
    final cached = await container.read(collectionsProvider.future);
    expect(cached.offline, isTrue);
    expect(cached.collections.single.id, 'favorites');
    expect(cached.savedAt, isNotNull);
    container.dispose();

    final restarted = ProviderContainer(overrides: [
      authProvider.overrideWith((ref) => AuthController(client: api)),
    ]);
    await _waitForAuth(restarted);
    expect(restarted.read(authProvider).user?.id, 'account-a');
    expect((await restarted.read(collectionsProvider.future)).offline, isTrue);
    restarted.dispose();
  });

  testWidgets('offline collection screen shows cache and disables mutations',
      (tester) async {
    SharedPreferences.setMockInitialValues({'thmr_session_token': 'token-a'});
    final api = _FakeApi()..includeExtra = true;
    final online = ProviderContainer(overrides: [
      authProvider.overrideWith((ref) => AuthController(client: api)),
    ]);
    await _waitForAuth(online);
    await online.read(collectionsProvider.future);
    online.dispose();

    api.offline = true;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        authProvider.overrideWith((ref) => AuthController(client: api)),
      ],
      child: MaterialApp(
        theme: ThmrTheme.light(),
        home: const Scaffold(body: CollectionsScreen()),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('离线浏览缓存'), findsOneWidget);
    expect(find.text('夜雀歌单'), findsOneWidget);
    final createButton = find.ancestor(
      of: find.byTooltip('新建收藏夹'),
      matching: find.byType(IconButton),
    );
    expect(tester.widget<IconButton>(createButton).onPressed, isNull);
    expect(find.byTooltip('删除收藏夹'), findsNothing);
  });
}
