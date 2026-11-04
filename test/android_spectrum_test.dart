import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/player/spectrum_android.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('native PCM spectrum levels map to normalized bands', () {
    final levels =
        spectrumBandsFromLevels(Uint8List.fromList([0, 128, 255]), 4);
    expect(levels[0], 0);
    expect(levels[1], closeTo(128 / 255, 0.0001));
    expect(levels[2], 1);
    expect(levels[3], 0);
  });

  test('decodes the app radio URL without requesting microphone access',
      () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <String>[];
    messenger.setMockMethodCallHandler(AndroidSpectrum.channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'start':
          expect(
              call.arguments, {'url': 'https://radio.example.test/live.mp3'});
          return 'ready';
        case 'bands':
          expect(call.arguments, {'bands': 8});
          return Uint8List.fromList([0, 64, 128, 255, 0, 0, 0, 0]);
        case 'stop':
          return true;
      }
      return null;
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(AndroidSpectrum.channel, null));

    final source =
        AndroidSpectrum.forTesting(() => 'https://radio.example.test/live.mp3');
    source.start();
    source.start();
    await Future<void>.delayed(Duration.zero);
    expect(source.status, AndroidSpectrumStatus.ready);
    expect(source.poll(8), isNull);
    await Future<void>.delayed(Duration.zero);
    expect(source.poll(8)![3], 1);
    source.stop();
    source.stop();
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['start', 'bands', 'bands', 'stop']);
  });
}
