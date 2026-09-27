import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/player/audio_engine.dart';

void main() {
  test('system media commands follow the registered player controls', () async {
    final commands = <String>[];
    registerMediaControls(
      play: () async => commands.add('play'),
      pause: () async => commands.add('pause'),
      stop: () async => commands.add('stop'),
    );
    addTearDown(unregisterMediaControls);

    await dispatchSystemMediaCommand(SystemMediaCommand.play);
    await dispatchSystemMediaCommand(SystemMediaCommand.pause);
    await dispatchSystemMediaCommand(SystemMediaCommand.stop);
    expect(commands, ['play', 'pause', 'stop']);
  });

  test('system media metadata identifies the track and its artwork', () {
    final item = mediaItemForTrack(
      trackId: '42',
      startedAtMs: 123,
      title: 'Song',
      artist: 'Artist',
      artUri: 'https://example.com/cover.png',
      durationSec: 210,
    );
    expect(item.id, 'thmr-42-123');
    expect(item.duration, const Duration(seconds: 210));
    expect(item.artUri, Uri.parse('https://example.com/cover.png'));
  });
}
