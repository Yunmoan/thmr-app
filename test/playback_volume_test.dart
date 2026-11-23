import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:media_kit/media_kit.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thmr_app/core/models/models.dart';
import 'package:thmr_app/core/player/playback_controller.dart';
import 'package:thmr_app/core/player/shared_radio_stream.dart';

class _RecordingPlayer extends PlatformPlayer {
  _RecordingPlayer({this.decodeErrorOnOpen = false})
      : super(configuration: const PlayerConfiguration());

  final opened = <String>[];
  final bool decodeErrorOnOpen;
  int stops = 0;

  @override
  Future<void> open(Playable playable, {bool play = true}) async {
    opened.add((playable as Media).uri);
    state = state.copyWith(
        playing: play, position: Duration.zero, completed: false);
    playingController.add(play);
    if (decodeErrorOnOpen) decodeError();
  }

  void updatePosition(Duration position) {
    state = state.copyWith(position: position);
    positionController.add(position);
  }

  void decodeError() => errorController.add('Error decoding audio.');

  @override
  Future<void> pause() async {
    state = state.copyWith(playing: false);
    playingController.add(false);
  }

  @override
  Future<void> stop() async {
    stops++;
    await pause();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final platform in [TargetPlatform.iOS, TargetPlatform.macOS]) {
    test(
        '$platform playback supplies the shared radio stream to the spectrum decoder',
        () async {
      SharedPreferences.setMockInitialValues({});
      debugDefaultTargetPlatformOverride = platform;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      addTearDown(sharedRadioStream.dispose);
      final engine = _RecordingPlayer();
      addTearDown(engine.dispose);
      final controller =
          PlaybackController(player: Player(platformPlayer: engine));
      addTearDown(controller.dispose);
      await controller.tune('https://radio.test/radio/touhou/320k');
      final playerUri = Uri.parse(engine.opened.single);
      final spectrumUri = sharedRadioStream.spectrumUri!;
      expect(playerUri.host, '127.0.0.1');
      expect(playerUri.pathSegments.first, 'play');
      expect(spectrumUri.pathSegments.first, 'spectrum');
      expect(playerUri.pathSegments.last, spectrumUri.pathSegments.last);
      await controller.pause();
      expect(sharedRadioStream.spectrumUri, isNull);
      await controller.playFromSystem();
      expect(sharedRadioStream.spectrumUri, isNotNull);
      expect(sharedRadioStream.spectrumUri, isNot(spectrumUri));
      expect(engine.opened, hasLength(2));
    });
  }

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

  testWidgets(
      'a track-boundary decode log leaves a progressing stream connected',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    const url = 'https://radio.test/radio/touhou/320k';
    final engine = _RecordingPlayer();
    final controller =
        PlaybackController(player: Player(platformPlayer: engine));
    try {
      await controller.tune(url);
      await tester.pump();
      engine.updatePosition(const Duration(seconds: 10));
      engine.decodeError();
      await tester.pump();
      expect(controller.state.phase, PlaybackPhase.online);
      expect(controller.state.error, isNull);

      await tester.pump(const Duration(seconds: 1));
      engine.updatePosition(const Duration(seconds: 11));
      await tester.pump(const Duration(seconds: 4));
      expect(controller.state.phase, PlaybackPhase.online);
      expect(controller.state.error, isNull);
      expect(engine.opened, [url]);
    } finally {
      controller.dispose();
      await engine.dispose();
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('a stalled decoder reconnects with a bounded number of attempts',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    const url = 'https://radio.test/radio/touhou/320k';
    final engine = _RecordingPlayer(decodeErrorOnOpen: true);
    final controller =
        PlaybackController(player: Player(platformPlayer: engine));
    try {
      await controller.tune(url);
      await tester.pump();
      for (var attempt = 0; attempt < 4; attempt++) {
        for (var duplicate = 0; duplicate < 6; duplicate++) {
          engine.decodeError();
        }
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        expect(controller.state.phase, PlaybackPhase.reconnecting);
        expect(controller.state.error, contains('正在重新连接'));
        await tester.pump(const Duration(seconds: 1));
        expect(engine.opened, hasLength(attempt + 2));
      }
      await tester.pump(const Duration(seconds: 2));
      expect(controller.state.phase, PlaybackPhase.idle);
      expect(controller.state.error, contains('请稍后手动重试'));
      await tester.pump(const Duration(seconds: 10));
      expect(engine.opened, List.filled(5, url));
      expect(engine.stops, 1);
    } finally {
      controller.dispose();
      await engine.dispose();
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('changing stream or pausing cancels a pending decode check',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    const first = 'https://radio.test/radio/touhou/320k';
    const second = 'https://radio.test/radio/touhou-curated/128k';
    final engine = _RecordingPlayer();
    final controller =
        PlaybackController(player: Player(platformPlayer: engine));
    try {
      await controller.tune(first);
      engine.decodeError();
      await tester.pump();
      await controller.switchStation();
      await controller.updateStreamUrl(second);
      await tester.pump(const Duration(seconds: 4));
      expect(controller.state.phase, PlaybackPhase.online);
      expect(controller.state.error, isNull);

      engine.decodeError();
      await tester.pump();
      await controller.pause();
      await tester.pump(const Duration(seconds: 4));
      expect(controller.state.userPaused, isTrue);
      expect(controller.state.error, isNull);
      expect(engine.opened, [first, second]);
    } finally {
      controller.dispose();
      await engine.dispose();
    }
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
