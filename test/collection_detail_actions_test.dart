import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thmr_app/core/api/thmr_api.dart';
import 'package:thmr_app/core/models/models.dart';
import 'package:thmr_app/core/state/auth_provider.dart';
import 'package:thmr_app/core/state/app_providers.dart';
import 'package:thmr_app/core/state/collection_cache.dart';
import 'package:thmr_app/core/theme/thmr_theme.dart';
import 'package:thmr_app/features/collections/collection_detail.dart';

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
  itemCount: 1,
  createdAt: null,
  updatedAt: null,
  share: ShareInfo(enabled: true, slug: 'favorites', expiresAt: null),
);

const _item = CollectionItem(
  id: 'item-1',
  stationId: 'touhou',
  trackId: 'track-1',
  position: 0,
  title: '幽雅に咲かせ、墨染の桜',
  artist: '上海アリス幻樂団',
  album: '蓬莱人形',
  durationSec: 240,
  coverUrl: '',
  addedAt: null,
);

class _FakeApi extends ThmrApi {
  @override
  Future<ThmrUser?> me() async => _user;

  @override
  Future<(Collection, List<CollectionItem>)> collectionDetail(
    String cid, {
    String sort = 'position',
    String order = 'asc',
  }) async =>
      (_collection, const [_item]);
}

class _SortingApi extends _FakeApi {
  final byTitle = Completer<(Collection, List<CollectionItem>)>();
  final byArtist = Completer<(Collection, List<CollectionItem>)>();
  bool removed = false;

  @override
  Future<(Collection, List<CollectionItem>)> collectionDetail(String cid,
      {String sort = 'position', String order = 'asc'}) async {
    if (removed) return (_collection, <CollectionItem>[]);
    if (sort == 'title') return byTitle.future;
    if (sort == 'artist') return byArtist.future;
    return super.collectionDetail(cid, sort: sort, order: order);
  }

  @override
  Future<void> removeItem(String cid, String itemId) async => removed = true;
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
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
      'latest sort owns the list and cache; removing an item refreshes favorites',
      (tester) async {
    SharedPreferences.setMockInitialValues({'thmr_session_token': 'token-a'});
    final api = _SortingApi();
    final container = ProviderContainer(overrides: [
      authProvider.overrideWith((ref) => AuthController(client: api)),
      favoritesStatusProvider.overrideWith(
          (ref) async => FavoritesStatus.fromJson({'favorited': !api.removed})),
    ]);
    addTearDown(container.dispose);
    await _waitForAuth(container);
    final favorite = container.listen(favoritesStatusProvider, (_, __) {});
    addTearDown(favorite.close);
    expect((await container.read(favoritesStatusProvider.future)).favorited,
        isTrue);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThmrTheme.light(),
          home: const CollectionDetailScreen(
              collectionId: 'favorites', name: '收藏'),
        )));
    await tester.pumpAndSettle();
    Future<void> sortBy(String label) async {
      await tester.tap(find.byTooltip('排序'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.text(label).last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
    }

    await sortBy('曲名');
    await sortBy('艺术家');
    api.byArtist.complete((_collection, [_item]));
    await tester.pumpAndSettle();
    api.byTitle.complete((_collection, <CollectionItem>[]));
    await tester.pumpAndSettle();
    expect(find.text(_item.title), findsOneWidget);
    final cached =
        await const CollectionCache().readDetail(_user.id, _collection.id);
    expect(cached?.items.single.id, _item.id);
    await tester.tap(find.byTooltip('移除'));
    await tester.pumpAndSettle();
    expect(find.text(_item.title), findsNothing);
    expect((await container.read(favoritesStatusProvider.future)).favorited,
        isFalse);
  });

  testWidgets('collection track can be copied and reported', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    SharedPreferences.setMockInitialValues({'thmr_session_token': 'token-a'});
    String? clipboardText;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboardText = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    final container = ProviderContainer(overrides: [
      authProvider.overrideWith((ref) => AuthController(client: _FakeApi())),
    ]);
    addTearDown(container.dispose);
    await _waitForAuth(container);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThmrTheme.light(),
          home: const CollectionDetailScreen(
            collectionId: 'favorites',
            name: '收藏',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('反馈'), findsOneWidget);
    expect(find.text('复制信息'), findsOneWidget);

    const shareChannel = MethodChannel('dev.fluttercommunity.plus/share');
    final messenger = tester.binding.defaultBinaryMessenger;
    Map? share;
    messenger.setMockMethodCallHandler(shareChannel, (call) async {
      share = call.arguments as Map;
      return '';
    });
    addTearDown(() => messenger.setMockMethodCallHandler(shareChannel, null));
    final button = find.widgetWithIcon(IconButton, Icons.share_rounded);
    final bounds = tester.getRect(button);
    await tester.tap(button);
    await tester.pump();
    expect(share?['originX'], bounds.left);
    expect(share?['originY'], bounds.top);
    expect(share?['originWidth'], bounds.width);
    expect(share?['originHeight'], bounds.height);

    await tester.tap(find.text('复制信息'));
    await tester.pump();
    expect(
      clipboardText,
      '幽雅に咲かせ、墨染の桜 - 上海アリス幻樂団 · 蓬莱人形',
    );
    expect(find.text('歌曲信息已复制'), findsOneWidget);

    await tester.tap(find.text('反馈'));
    await tester.pumpAndSettle();
    expect(find.text('曲目反馈'), findsOneWidget);
    expect(find.text('正在反馈:幽雅に咲かせ、墨染の桜'), findsOneWidget);
  });
}
