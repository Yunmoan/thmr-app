import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/models/models.dart';
import 'package:thmr_app/core/player/playback_controller.dart';
import 'package:thmr_app/core/state/station_provider.dart';
import 'package:thmr_app/core/theme/thmr_theme.dart';
import 'package:thmr_app/shared/widgets/player_dock_bar.dart';

class _StationStub extends StateNotifier<StationUiState>
    implements StationPoller {
  _StationStub()
      : super(const StationUiState(
          initialLoading: false,
          status: StationStatus(
            station: StationInfo(
              id: 'touhou',
              name: '东方综合频道',
              enabled: true,
              public: null,
              streamAuthEnabled: false,
              bitrates: [],
            ),
            listeners: 12,
            uniqueIps: 10,
            current: CurrentTrack(
              trackId: 't1',
              title: 'U.N.オーエンは彼女なのか？(Long Arrange)',
              artist: 'ZUN / 幻想乡同人乐团',
              coverUrl: '',
              startedAtMs: 0,
              expectedEndMs: 0,
              positionSec: 0,
              durationSec: 240,
            ),
            previous: null,
            queue: [],
          ),
        ));

  @override
  Future<void> refresh() async {}
}

class _PlaybackStub extends StateNotifier<PlaybackState>
    implements PlaybackController {
  _PlaybackStub() : super(const PlaybackState(phase: PlaybackPhase.idle));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets('窄屏底部播放条可点击曲目区域打开播放器且无文字按钮挤压', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    var opened = 0;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        stationProvider.overrideWith((ref) => _StationStub()),
        playbackProvider.overrideWith((ref) => _PlaybackStub()),
      ],
      child: MaterialApp(
        theme: ThmrTheme.light(),
        home: Scaffold(
          bottomNavigationBar: PlayerDockBar(
            compact: true,
            onOpenPlayer: () => opened++,
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('打开播放器'), findsNothing);
    expect(find.byTooltip('打开播放器'), findsOneWidget);

    await tester.tap(find.textContaining('U.N.オーエン'));
    await tester.pump();
    expect(opened, 1);

    await tester.tap(find.byTooltip('打开播放器'));
    await tester.pump();
    expect(opened, 2);
  });
}
