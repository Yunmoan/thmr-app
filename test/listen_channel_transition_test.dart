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

const _curated = 'touhou-curated';

StationStatus _status(String id, String title) => StationStatus.fromJson({
      'station': {'id': id, 'name': '东方音乐电台', 'enabled': true},
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
}

class _IdlePlayback extends StateNotifier<PlaybackState>
    implements PlaybackController {
  _IdlePlayback() : super(const PlaybackState());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RadioApi extends RadioApi {
  @override
  Future<int> siteListeners() async => 17;
}

void main() {
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

    initial.complete(_status(appConfig.stationId, '综合曲目'));
    await tester.pumpAndSettle();
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
