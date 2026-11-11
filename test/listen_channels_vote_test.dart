import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thmr_app/core/api/radio_api.dart';
import 'package:thmr_app/core/api/thmr_api.dart';
import 'package:thmr_app/core/config.dart';
import 'package:thmr_app/core/models/models.dart';
import 'package:thmr_app/core/player/playback_controller.dart';
import 'package:thmr_app/core/state/app_providers.dart';
import 'package:thmr_app/core/state/auth_provider.dart';
import 'package:thmr_app/core/state/channel_provider.dart';
import 'package:thmr_app/core/state/radio_source_provider.dart';
import 'package:thmr_app/core/state/station_provider.dart';
import 'package:thmr_app/core/theme/thmr_colors.dart';
import 'package:thmr_app/features/listen/listen_screen.dart';
import 'package:thmr_app/features/listen/widgets/bitrate_row.dart';
import 'package:thmr_app/features/listen/widgets/channel_switcher.dart';
import 'package:thmr_app/features/listen/widgets/listener_stat.dart';
import 'package:thmr_app/features/listen/widgets/now_playing_panel.dart';
import 'package:thmr_app/features/listen/widgets/vote_panel.dart';

const _curated = 'touhou-curated';

StationStatus _status(String id) => StationStatus.fromJson({
      'station': {
        'id': id,
        'name': id == _curated ? '精选电台' : '东方音乐电台',
        'enabled': true,
        'bitrates': [
          for (final rate in [320, 128, 96])
            {'id': '${rate}k', 'bitrateKbps': rate, 'enabled': true},
        ],
      },
      'totals': {'listeners': id == _curated ? 4 : 13},
      'current': _track(id),
    });

Map<String, Object> _track(String id) => {
      'trackId': '$id-track',
      'startedAtMs': 12345,
      'title': id == _curated ? '精选曲目' : '综合曲目',
      'artist': 'THMR',
    };

class _Station extends StateNotifier<StationUiState> implements StationPoller {
  _Station(String id)
      : super(StationUiState(status: _status(id), initialLoading: false));

  @override
  Future<void> refresh() async {}
}

class _Playback extends StateNotifier<PlaybackState>
    implements PlaybackController {
  _Playback() : super(const PlaybackState());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RadioApi extends RadioApi {
  @override
  Future<int> siteListeners() async => 17;
}

class _AccountApi extends ThmrApi {
  bool enabled = true;
  Completer<void>? pendingMutation;
  final mutations = <(String, String)>[];
  final votes = <String>{};

  @override
  Future<ThmrUser> me() async => const ThmrUser(
        id: '1',
        naidsId: '1',
        username: 'listener',
        nickname: 'Listener',
        email: '',
        realnameVerified: false,
        createdAt: null,
        needsNickname: false,
      );

  @override
  Future<List<RadioChannel>> channels() async => RadioChannel.enabledFromJson([
        {'categorize': appConfig.stationId, 'name': '东方综合频道'},
        {'categorize': _curated, 'name': '东方综合精选频道', 'enabled': true},
        {'categorize': 'touhou-original', 'name': '东方原曲频道', 'enabled': false},
      ]);

  @override
  Future<bool> voteEnabled() async => enabled;

  @override
  Future<VoteStatus> voteStatus(String stationId) async => VoteStatus.fromJson({
        'stationId': stationId,
        'active': true,
        'current': _track(stationId),
        'round': {'votes': votes.contains(stationId) ? 1 : 0, 'threshold': 3},
        'myVote': votes.contains(stationId),
      });

  @override
  Future<bool> castVote(String stationId) async {
    mutations.add(('cast', stationId));
    await pendingMutation?.future;
    votes.add(stationId);
    return false;
  }

  @override
  Future<void> cancelVote(String stationId) async {
    mutations.add(('cancel', stationId));
    await pendingMutation?.future;
    votes.remove(stationId);
  }
}

void main() {
  testWidgets('the channel menu fits a narrow window and supports selection',
      (tester) async {
    tester.view.physicalSize = const Size(300, 660);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(
      overrides: [
        channelCatalogProvider.overrideWith((ref) async => [
              RadioChannel(id: appConfig.stationId, name: '东方综合频道'),
              const RadioChannel(id: _curated, name: '东方综合精选频道'),
              const RadioChannel(id: 'touhou-original', name: '东方原曲频道'),
              const RadioChannel(
                  id: 'touhou-instrumental', name: '东方纯音乐与器乐演奏精选特别放送频道'),
            ]),
      ],
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(
          extensions: [ThmrTokens.resolve(AccentTheme.cirno, Brightness.dark)],
        ),
        home: const Scaffold(
          body: Padding(
            padding: EdgeInsets.all(16),
            child:
                Align(alignment: Alignment.topLeft, child: ChannelSwitcher()),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.text('东方综合频道'), findsOneWidget);
    final trigger = find.byTooltip('切换频道');
    final triggerRect = tester.getRect(trigger);
    final first = find.byKey(ValueKey('channel-menu-${appConfig.stationId}'));
    final curated = find.byKey(const ValueKey('channel-menu-$_curated'));
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<String>), findsNWidgets(4));
    final row = tester.getRect(first);
    expect(row.left, closeTo(triggerRect.left, 8));
    expect(
        row.top, inInclusiveRange(triggerRect.bottom, triggerRect.bottom + 12));
    expect(row.height, lessThan(48));
    expect(row.right, lessThanOrEqualTo(292));
    expect(tester.takeException(), isNull);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(first, findsNothing);
    await tester.tap(trigger);
    await tester.pumpAndSettle();
    await tester.tap(curated);
    await tester.pumpAndSettle();
    expect(find.text('东方综合精选频道'), findsOneWidget);
    expect(first, findsNothing);
  });

  for (final width in [360.0, 430.0, 1100.0]) {
    testWidgets('channel switch and online voting at ${width.toInt()} px',
        (tester) async {
      tester.view.physicalSize = Size(width, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({'thmr_session_token': 'test'});
      final api = _AccountApi();

      await tester.pumpWidget(ProviderScope(
        overrides: [
          publicThmrApiProvider.overrideWithValue(api),
          radioApiProvider.overrideWithValue(_RadioApi()),
          authProvider.overrideWith((ref) => AuthController(client: api)),
          stationProvider.overrideWith(
              (ref) => _Station(ref.watch(activeStationIdProvider))),
          playbackProvider.overrideWith((ref) => _Playback()),
          favoritesStatusProvider.overrideWith((ref) async =>
              const FavoritesStatus(
                  favorited: false,
                  itemId: null,
                  collectionId: null,
                  collections: [])),
        ],
        child: MaterialApp(
          theme: ThemeData.dark().copyWith(
            extensions: [
              ThmrTokens.resolve(AccentTheme.cirno, Brightness.dark)
            ],
          ),
          home: const Scaffold(body: ListenScreen()),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('综合曲目'), findsOneWidget);
      expect(find.text('0 / 3 票'), findsOneWidget);
      final stats = find.byType(ListenerStat);
      final statRect = tester.getRect(stats);
      final channelListeners =
          find.text(width >= 980 ? '本频道实时在线听众' : '本频道 13 人在听').hitTestable();
      final siteListeners =
          find.text(width >= 980 ? '全站实时在线听众' : '全站 17 人在听').hitTestable();
      expect(channelListeners, findsOneWidget);
      expect(siteListeners, findsNothing);
      await tester.pump(const Duration(milliseconds: 4200));
      await tester.pumpAndSettle();
      expect(channelListeners, findsNothing);
      expect(siteListeners, findsOneWidget);
      expect(tester.getRect(stats), statRect);
      await tester.pump(const Duration(milliseconds: 4200));
      await tester.pumpAndSettle();
      expect(channelListeners, findsOneWidget);
      expect(siteListeners, findsNothing);

      final vote = find.byType(VotePanel);
      final bitrate = tester.getRect(find.byType(BitrateRow));
      final voteRect = tester.getRect(vote);
      if (width >= 980) {
        expect(voteRect.left, greaterThan(bitrate.right));
        expect(voteRect.center.dy, closeTo(bitrate.center.dy, 1));
      } else {
        expect(voteRect.top,
            greaterThan(tester.getBottomLeft(find.byType(NowPlayingPanel)).dy));
      }

      expect(find.text('东方原曲频道'), findsNothing);
      final switcher = find.byType(ChannelSwitcher);
      final current =
          find.descendant(of: switcher, matching: find.text('东方综合频道'));
      final curated = find.widgetWithText(TextButton, '东方综合精选频道');
      expect(curated, findsOneWidget);
      expect(tester.getCenter(curated).dy,
          closeTo(tester.getCenter(current).dy, 1));
      expect(tester.getSize(switcher).width, lessThan(width - 32));
      await tester.tap(curated);
      await tester.pumpAndSettle();
      expect(find.text('精选曲目'), findsOneWidget);
      expect(find.text('综合曲目'), findsNothing);

      api.pendingMutation = Completer<void>();
      await tester.tap(find.text('投一票'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, '投票中…'))
              .onPressed,
          isNull);
      expect(find.text('已投票'), findsNothing);
      api.pendingMutation!.complete();
      await tester.pumpAndSettle();
      expect(find.text('1 / 3 票'), findsOneWidget);
      expect(find.text('已投票'), findsOneWidget);

      api.pendingMutation = Completer<void>();
      await tester.tap(find.text('撤回'));
      await tester.pumpAndSettle();
      expect(
          tester
              .widget<FilledButton>(find.widgetWithText(FilledButton, '撤回中…'))
              .onPressed,
          isNull);
      api.pendingMutation!.complete();
      await tester.pumpAndSettle();
      expect(find.text('0 / 3 票'), findsOneWidget);
      expect(find.text('已撤回投票'), findsOneWidget);
      expect(api.mutations, [('cast', _curated), ('cancel', _curated)]);

      api.enabled = false;
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(vote, findsNothing);
      expect(find.byType(BitrateRow), findsOneWidget);

      api.enabled = true;
      await tester.pump(const Duration(seconds: 31));
      await tester.pumpAndSettle();
      expect(vote, findsOneWidget);
      api.enabled = false;
      await tester.tap(find.text('投一票'));
      await tester.pumpAndSettle();
      expect(vote, findsNothing);
      expect(api.mutations, hasLength(2));
      expect(tester.takeException(), isNull);
    });
  }
}
