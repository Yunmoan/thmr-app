import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thmr_app/core/api/radio_api.dart';
import 'package:thmr_app/core/config.dart';
import 'package:thmr_app/core/models/models.dart';
import 'package:thmr_app/core/state/channel_provider.dart';
import 'package:thmr_app/core/state/radio_source_provider.dart';
import 'package:thmr_app/core/theme/thmr_theme.dart';
import 'package:thmr_app/features/collections/collections_screen.dart';
import 'package:thmr_app/features/collections/yesterday_playlist.dart';

const _curated = 'touhou-curated';

class _HistoryApi extends RadioApi {
  final requests = <String>[];
  bool curatedAvailable = false;

  @override
  Future<List<CollectionItem>> yesterdayPlaylist(String stationId) async {
    requests.add(stationId);
    if (stationId == _curated) {
      if (!curatedAvailable) throw ApiException(404, 'Not found');
      return [];
    }
    return [
      CollectionItem.fromJson({
        'id': '1',
        'stationId': stationId,
        'trackId': 'history',
        'title': '昨日曲目',
        'artist': 'THMR',
        'album': '昨日专辑',
        'durationSec': 120,
        'playedAtMs': DateTime.utc(2026, 11, 10, 16, 5).millisecondsSinceEpoch,
      }),
    ];
  }
}

void main() {
  testWidgets('guests can view yesterday and retry a different channel',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final api = _HistoryApi();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        radioApiProvider.overrideWithValue(api),
        channelCatalogProvider.overrideWith((ref) async => const [
              RadioChannel(id: _curated, name: '东方综合精选频道'),
              RadioChannel(id: AppConfig.defaultStationId, name: '东方综合频道'),
            ]),
      ],
      child: MaterialApp(
        theme: ThmrTheme.light(),
        home: const Scaffold(body: CollectionsScreen()),
      ),
    ));
    await tester.pumpAndSettle();

    expect(api.requests, [appConfig.stationId]);
    expect(find.text('昨日曲目'), findsOneWidget);
    expect(find.text('北京时间 · 按播放顺序 · 1 次播放'), findsOneWidget);
    expect(find.byTooltip('新建收藏夹'), findsNothing);
    expect(find.text('00:05 播放'), findsOneWidget);
    await tester.tap(find.text('昨日曲目'));
    await tester.pumpAndSettle();
    expect(find.text('昨日歌单 #1'), findsOneWidget);
    expect(find.text('昨日专辑'), findsOneWidget);
    expect(find.textContaining('00:05 播放（北京时间）'), findsOneWidget);
    Navigator.of(tester.element(find.text('昨日歌单 #1'))).pop();
    await tester.pumpAndSettle();

    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('东方综合精选频道').last);
    await tester.pumpAndSettle();

    expect(find.text('昨日曲目'), findsNothing);
    expect(find.text('暂时无法读取昨日歌单，请稍后重试。'), findsOneWidget);
    expect(find.text('昨日暂无播放记录。'), findsNothing);
    final container = ProviderScope.containerOf(
        tester.element(find.byType(CollectionsScreen)));
    expect(container.read(activeStationIdProvider), appConfig.stationId);

    api.curatedAvailable = true;
    await tester.tap(find.text('重试连接'));
    await tester.pumpAndSettle();
    expect(api.requests, [appConfig.stationId, _curated, _curated]);
    expect(find.text('昨日暂无播放记录。'), findsOneWidget);

    final now = DateTime.now().toUtc().add(const Duration(hours: 8));
    final nextMidnight = DateTime.utc(now.year, now.month, now.day + 1);
    await tester
        .pump(nextMidnight.difference(now) + const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(api.requests, [appConfig.stationId, _curated, _curated, _curated]);

    await tester.tap(find.text('我的列表'));
    await tester.pumpAndSettle();
    expect(find.text('尚未登录'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('legacy history does not invent a playback time', () {
    final item = CollectionItem.fromJson({'trackId': 'old'});
    expect(item.playedAtMs, isNull);
    expect(yesterdayPlaybackTime(item), isNull);
  });
}
