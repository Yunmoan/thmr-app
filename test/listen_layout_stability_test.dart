import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thmr_app/core/models/models.dart';
import 'package:thmr_app/core/player/playback_controller.dart';
import 'package:thmr_app/core/state/app_providers.dart';
import 'package:thmr_app/core/state/station_provider.dart';
import 'package:thmr_app/core/theme/thmr_theme.dart';
import 'package:thmr_app/features/listen/widgets/bitrate_row.dart';
import 'package:thmr_app/features/listen/widgets/now_playing_panel.dart';
import 'package:thmr_app/features/listen/widgets/queue_strip.dart';

final status = StationStatus.fromJson({
  'station': {
    'id': 'test',
    'name': '电台',
    'bitrates': [
      for (final rate in [320, 128, 96])
        {'id': '${rate}k', 'bitrateKbps': rate, 'enabled': true},
    ]
  },
  'current': {'trackId': 'one', 'title': '曲目', 'artist': '歌手'},
  'queue': [
    for (var i = 0; i < 6; i++) {'trackId': '$i', 'title': '曲目 $i'}
  ],
});

class _Station extends StateNotifier<StationUiState> implements StationPoller {
  _Station() : super(StationUiState(status: status, initialLoading: false));
  @override
  Future<void> refresh() async {}
}

class _Playback extends StateNotifier<PlaybackState>
    implements PlaybackController {
  _Playback() : super(const PlaybackState());
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('small player gives quality controls space below the divider',
      (tester) async {
    tester.view.physicalSize = const Size(375, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(
        overrides: [
          stationProvider.overrideWith((ref) => _Station()),
          playbackProvider.overrideWith((ref) => _Playback()),
        ],
        child: MaterialApp(
            theme: ThmrTheme.dark(),
            home: Scaffold(body: NowPlayingPanel(status: status)))));
    await tester.pumpAndSettle();
    final divider = tester.getRect(find.byType(Divider));
    final quality = tester.getRect(find.byType(BitrateRow));
    expect(quality.top - divider.bottom, greaterThanOrEqualTo(12));
    expect(tester.takeException(), isNull);
  });

  testWidgets('queue accepts vertical and horizontal wheels and releases edges',
      (tester) async {
    tester.view.physicalSize = const Size(375, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final page = ScrollController();
    addTearDown(page.dispose);
    await tester.pumpWidget(MaterialApp(
        theme: ThmrTheme.dark(),
        home: Scaffold(
            body: ListView(controller: page, children: [
          QueueStrip(status: status),
          const SizedBox(height: 1600),
        ]))));
    await tester.pumpAndSettle();
    final strip = find.descendant(
        of: find.byType(QueueStrip), matching: find.byType(ListView));
    final cards = tester.widget<ListView>(strip);
    final scrollable = tester.state<ScrollableState>(
        find.descendant(of: strip, matching: find.byType(Scrollable)));
    final position = tester.getCenter(strip);
    Future<void> wheel(Offset delta) async {
      await tester.sendEventToBinding(
          PointerScrollEvent(position: position, scrollDelta: delta));
      await tester.pumpAndSettle();
    }

    await wheel(const Offset(0, 100));
    expect(scrollable.position.pixels, 100);
    expect(page.offset, 0);
    await wheel(const Offset(80, 0));
    expect(scrollable.position.pixels, 180);
    scrollable.position.jumpTo(scrollable.position.maxScrollExtent);
    await wheel(const Offset(0, 100));
    expect(page.offset, 100);
    expect(cards.scrollDirection, Axis.horizontal);
    expect(tester.takeException(), isNull);
  });
}
