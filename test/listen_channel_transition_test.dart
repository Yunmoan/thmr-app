import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thmr_app/core/api/radio_api.dart';
import 'package:thmr_app/core/config.dart';
import 'package:thmr_app/core/models/models.dart';
import 'package:thmr_app/core/player/playback_controller.dart';
import 'package:thmr_app/core/state/app_providers.dart';
import 'package:thmr_app/core/state/channel_provider.dart';
import 'package:thmr_app/core/state/radio_source_provider.dart';
import 'package:thmr_app/core/state/station_provider.dart';
import 'package:thmr_app/core/theme/thmr_colors.dart';
import 'package:thmr_app/features/listen/listen_screen.dart';
import 'package:thmr_app/features/listen/widgets/channel_switcher.dart';
import 'package:thmr_app/features/listen/widgets/now_playing_panel.dart';
import 'package:thmr_app/features/listen/widgets/channel_loading_skeleton.dart';
import 'package:thmr_app/shared/widgets/status_notice.dart';

const _curated = 'touhou-curated';

StationStatus _status(String id, String title) => StationStatus.fromJson({
      'station': {
        'id': id,
        'name': '东方音乐电台',
        'enabled': true,
        'public': {'title': '东方音乐电台', 'description': '持续放送幻想乡的音乐。'}
      },
      'totals': {'listeners': 12},
      'current': {'trackId': '$id-track', 'startedAtMs': 12345, 'title': title},
    });

class _DelayedStation extends StateNotifier<StationUiState>
    implements StationPoller {
  _DelayedStation(Future<StationStatus> status)
      : super(const StationUiState()) {
    unawaited(status.then((value) {
      if (mounted) {
        state = StationUiState(status: value, initialLoading: false);
      }
    }));
  }

  @override
  Future<void> refresh() async {}

  void update(StationUiState value) => state = value;
}

class _IdlePlayback extends StateNotifier<PlaybackState>
    implements PlaybackController {
  _IdlePlayback() : super(const PlaybackState());

  void update(PlaybackState value) => state = value;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RadioApi extends RadioApi {
  @override
  Future<int> siteListeners() async => 17;
}

class _Sources extends RadioSourceController {
  void update(RadioSourceState value) => state = value;
}

void main() {
  for (final width in [375.0, 1100.0]) {
    testWidgets('transient notices leave home content in place at $width',
        (tester) async {
      tester.view.physicalSize = Size(width, 960);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final status = _status(appConfig.stationId, '当前曲目');
      final poller = _DelayedStation(Future.value(status));
      final sources = _Sources();
      final playback = _IdlePlayback();
      await tester.pumpWidget(ProviderScope(
          overrides: [
            channelCatalogProvider.overrideWith((ref) async =>
                [RadioChannel(id: appConfig.stationId, name: '综合频道')]),
            radioApiProvider.overrideWithValue(_RadioApi()),
            stationProvider.overrideWith((ref) => poller),
            radioSourceProvider.overrideWith((ref) => sources),
            playbackProvider.overrideWith((ref) => playback),
            voteEnabledProvider.overrideWith((ref) async => false),
          ],
          child: MaterialApp(
              theme: ThemeData.dark().copyWith(extensions: [
                ThmrTokens.resolve(AccentTheme.cirno, Brightness.dark)
              ]),
              home: const Scaffold(body: ListenScreen()))));
      await tester.pumpAndSettle();
      final playerRect = tester.getRect(find.byType(NowPlayingPanel));
      final selectorRect = tester.getRect(find.byType(ChannelSwitcher));
      final focus = FocusManager.instance.primaryFocus;
      void unchanged() {
        expect(tester.getRect(find.byType(NowPlayingPanel)), playerRect);
        expect(tester.getRect(find.byType(ChannelSwitcher)), selectorRect);
        expect(FocusManager.instance.primaryFocus, same(focus));
      }

      sources.update(const RadioSourceState(testing: true));
      await tester.pump();
      expect(find.text('正在比较最优播放源，完成后即可收听…'), findsOneWidget);
      unchanged();
      sources.update(const RadioSourceState(tested: true));
      await tester.pumpAndSettle();
      expect(find.text('正在比较最优播放源，完成后即可收听…'), findsNothing);
      unchanged();
      poller.update(StationUiState(
          status: status, initialLoading: false, error: Exception('offline')));
      await tester.pump();
      expect(find.text('网络连接失败,正在自动重试…'), findsOneWidget);
      expect(find.text('立即重试'), findsNothing);
      unchanged();
      await tester.pump(const Duration(seconds: 7));
      expect(find.text('网络连接失败,正在自动重试…'), findsNothing);
      unchanged();
      poller.update(StationUiState(status: status, initialLoading: false));
      playback.update(const PlaybackState(
          phase: PlaybackPhase.reconnecting, error: '播放连接失败，请重试'));
      await tester.pump();
      expect(
          find.descendant(
              of: find.byType(StatusNotice), matching: find.text('播放连接失败，请重试')),
          findsOneWidget);
      unchanged();
      playback.update(const PlaybackState());
      await tester.pump();
      unchanged();
      playback.update(const PlaybackState(error: '连续重连失败,请稍后手动重试'));
      await tester.pump();
      expect(find.text('连续重连失败,请稍后手动重试'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(StatusNotice),
              matching: find.text('连续重连失败,请稍后手动重试')),
          findsNothing);
      playback.update(const PlaybackState());
      poller.update(
          StationUiState(initialLoading: false, error: Exception('offline')));
      await tester.pumpAndSettle();
      expect(find.text('立即重试'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('desktop channel changes keep the selector mounted while loading',
      (tester) async {
    tester.view.physicalSize = const Size(1100, 850);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});

    final initial = Completer<StationStatus>();
    final incoming = Completer<StationStatus>();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        channelCatalogProvider.overrideWith((ref) async => [
              RadioChannel(id: appConfig.stationId, name: '综合频道'),
              const RadioChannel(id: _curated, name: '精选频道'),
            ]),
        radioApiProvider.overrideWithValue(_RadioApi()),
        stationProvider.overrideWith((ref) => _DelayedStation(
              ref.watch(activeStationIdProvider) == _curated
                  ? incoming.future
                  : initial.future,
            )),
        playbackProvider.overrideWith((ref) => _IdlePlayback()),
        voteEnabledProvider.overrideWith((ref) async => false),
      ],
      child: MaterialApp(
        theme: ThemeData.dark().copyWith(
          extensions: [ThmrTokens.resolve(AccentTheme.cirno, Brightness.dark)],
        ),
        home: const Scaffold(body: ListenScreen()),
      ),
    ));

    await tester.pumpAndSettle();
    initial.complete(_status(appConfig.stationId, '综合曲目'));
    await tester.pumpAndSettle();
    final descriptionRect = tester.getRect(find.text('持续放送幻想乡的音乐。'));
    final channelRow = find
        .ancestor(of: find.byType(ChannelSwitcher), matching: find.byType(Wrap))
        .first;
    expect(tester.getRect(channelRow).top - descriptionRect.bottom,
        closeTo(12, 1));
    final switcher = find.byType(ChannelSwitcher);
    final headerElement = tester.element(switcher);
    final player = find.byType(NowPlayingPanel);
    final oldPlayerElement = tester.element(player);
    final playButton = find.descendant(of: player, matching: find.text('播放'));
    final loading = find.byType(ChannelLoadingSkeleton);
    expect(find.text('综合曲目'), findsOneWidget);
    expect(playButton.hitTestable(), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '精选频道'));
    await tester.pump();
    expect(tester.element(switcher), same(headerElement));
    expect(loading, findsOneWidget);
    expect(tester.element(player), same(oldPlayerElement));
    expect(playButton.hitTestable(), findsNothing);

    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();
    expect(player, findsNothing);
    expect(loading, findsOneWidget);
    expect(tester.element(switcher), same(headerElement));

    incoming.complete(_status(_curated, '精选曲目'));
    await tester.pumpAndSettle();
    expect(find.text('精选曲目'), findsOneWidget);
    expect(find.text('综合曲目'), findsNothing);
    expect(playButton.hitTestable(), findsOneWidget);
    expect(loading, findsNothing);
    expect(tester.element(switcher), same(headerElement));
    expect(tester.takeException(), isNull);
  });
}
