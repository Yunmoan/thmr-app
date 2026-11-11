import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thmr_app/core/models/models.dart';
import 'package:thmr_app/core/player/playback_controller.dart';

class _RecordingPlayer extends PlatformPlayer {
  _RecordingPlayer() : super(configuration: const PlayerConfiguration());

  final opened = <String>[];
  int stops = 0;

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    opened.add((playable as Media).uri);
    playingController.add(play);
  }

  @override
  Future<void> pause() async => playingController.add(false);

  @override
  Future<void> stop() async {
    stops++;
    playingController.add(false);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('muting restores the previous nonzero volume', () {
    var state = const PlaybackState().copyWith(volume: 70);
    state = state.copyWith(volume: state.volumeAfterMuteToggle);
    expect(state.volume, 0);
    expect(state.lastAudibleVolume, 70);

    state = state.copyWith(volume: state.volumeAfterMuteToggle);
    expect(state.volume, 70);

    state = state.copyWith(volume: 35);
    state = state.copyWith(volume: state.volumeAfterMuteToggle);
    expect(state.volumeAfterMuteToggle, 35);
  });

  test('track search text includes available fields only', () {
    expect(
      trackSearchText(title: '曲名', artist: '艺术家'),
      '曲名 - 艺术家',
    );
    expect(
      trackSearchText(title: ' 曲名 ', artist: '', album: ' 专辑 '),
      '曲名 · 专辑',
    );
  });

  test('channel changes continue active playback and preserve a manual pause',
      () async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    const first = 'https://radio.test/radio/touhou/320k';
    const second = 'https://radio.test/radio/touhou-curated/128k';
    final engine = _RecordingPlayer();
    addTearDown(engine.dispose);
    var selectedUrl = first;
    final controller = PlaybackController(
      streamUrl: () => selectedUrl,
      player: Player(platformPlayer: engine),
    );
    addTearDown(controller.dispose);

    await controller.tune(first);
    await controller.switchStation();
    await controller.switchStation();
    expect(engine.stops, 1);
    expect(controller.state.phase, PlaybackPhase.connecting);
    selectedUrl = second;
    await controller.updateStreamUrl(second);
    expect(engine.opened, [first, second]);

    await controller.pause();
    await controller.switchStation();
    selectedUrl = first;
    await controller.updateStreamUrl(first);
    expect(controller.state.userPaused, isTrue);
    expect(engine.opened, [first, second]);
    await controller.playFromSystem();
    expect(engine.opened, [first, second, first]);
  });
}
