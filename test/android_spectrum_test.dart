import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/player/spectrum_android.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Visualizer FFT bytes are decoded as signed complex bins', () {
    final silence = spectrumBandsFromFft(Uint8List(32), 8);
    expect(silence.every((band) => band == 0), isTrue);

    final positive = Uint8List(32)..[2] = 64;
    final negative = Uint8List(32)..[2] = 192;
    final plus = spectrumBandsFromFft(positive, 8);
    final minus = spectrumBandsFromFft(negative, 8);
    expect(plus.any((band) => band > 0), isTrue);
    expect(minus, orderedEquals(plus));
  });

  test('permission grant starts capture and receives typed FFT data', () async {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    var starts = 0;
    var stops = 0;
    var granted = false;
    messenger.setMockMethodCallHandler(AndroidSpectrum.channel, (call) async {
      switch (call.method) {
        case 'start':
          starts++;
          return granted ? 'ready' : 'permissionRequired';
        case 'requestPermission':
          granted = true;
          return true;
        case 'fft':
          return Uint8List(32)..[2] = 64;
        case 'stop':
          stops++;
          return true;
      }
      return null;
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(AndroidSpectrum.channel, null));

    final source = AndroidSpectrum.tryCreate()!;
    source.start();
    source.start();
    await Future<void>.delayed(Duration.zero);
    expect(starts, 1);
    expect(source.status, AndroidSpectrumStatus.permissionRequired);
    expect(await source.requestAccess(), isTrue);
    expect(starts, 2);
    expect(source.poll(8), isNull);
    await Future<void>.delayed(Duration.zero);
    expect(source.poll(8)!.any((band) => band > 0), isTrue);

    source.stop();
    expect(stops, 0);
    source.stop();
    await Future<void>.delayed(Duration.zero);
    expect(stops, 1);
  });
}
