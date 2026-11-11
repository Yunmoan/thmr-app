import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/player/spectrum_android.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
        case 'magnitudes':
          expect(call.arguments, isNull);
          return {
            'sampleRate': 48000,
            'magnitudes': Float64List(1025)..fillRange(0, 1025, 0.5)
          };
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
    expect(source.poll(8)![3], inInclusiveRange(0.9, 1));
    expect(source.poll(110), hasLength(110));
    source.stop();
    source.stop();
    await Future<void>.delayed(Duration.zero);
    expect(calls, ['start', 'magnitudes', 'magnitudes', 'stop']);
  });

  test('changing the radio URL starts a new spectrum session', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var url = 'https://radio.test/one';
    final urls = <String>[];
    messenger.setMockMethodCallHandler(AndroidSpectrum.channel, (call) async {
      if (call.method == 'start') {
        urls.add((call.arguments as Map)['url'] as String);
        return 'ready';
      }
      return null;
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(AndroidSpectrum.channel, null));
    final source = AndroidSpectrum.forTesting(() => url);
    source.start();
    await Future<void>.delayed(Duration.zero);
    url = 'https://radio.test/two';
    expect(source.poll(64), isNull);
    await Future<void>.delayed(Duration.zero);
    expect(urls, ['https://radio.test/one', 'https://radio.test/two']);
    source.stop();
    await Future<void>.delayed(Duration.zero);
  });
}
