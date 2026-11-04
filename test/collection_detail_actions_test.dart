import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thmr_app/core/api/thmr_api.dart';
import 'package:thmr_app/core/models/models.dart';
import 'package:thmr_app/core/state/auth_provider.dart';
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
  share: ShareInfo(enabled: false, slug: '', expiresAt: null),
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
