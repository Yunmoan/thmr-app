import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/player/spectrum_fft.dart';
import 'package:thmr_app/core/player/spectrum_linux.dart';

void main() {
  test('FFT identifies a tone, maps bounded bands and leaves silence still',
      () {
    const n = 2048, sampleRate = 44100, bin = 46;
    final pcm = Float32List.fromList(
        List.generate(n, (i) => 0.5 * math.sin(2 * math.pi * bin * i / n)));
    final magnitudes = pcmMagnitudes(pcm);
    expect(magnitudes[bin], closeTo(0.5, 0.001));
    expect(magnitudes[bin - 5], lessThan(0.001));
    final bands = logarithmicSpectrumBands(magnitudes, 64, sampleRate);
    expect(bands, everyElement(inInclusiveRange(0, 1)));
    expect(bands.reduce(math.max), greaterThan(0.8));
    final silence =
        logarithmicSpectrumBands(pcmMagnitudes(Float32List(n)), 64, sampleRate);
    expect(silence, everyElement(0));
  });

  test('sample-rate changes reset the PCM window instead of mixing streams',
      () {
    final decoder = PcmSpectrumDecoder();
    final tone = Float32List.fromList(
        List.generate(4096, (i) => math.sin(2 * math.pi * 1000 * i / 44100)));
    expect(decoder.add(tone, 1, 44100), isNotNull);
    expect(decoder.add(Float32List(100), 1, 48000), isNull);
    expect(decoder.add(Float32List(4096), 1, 48000), everyElement(0));
  });

  test(
      'missing library and rapid stop/start do not keep decoder isolates alive',
      () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) => request.response.close());
    final source = LinuxSpectrum.forTesting(
        () => Uri.parse('http://127.0.0.1:${server.port}/spectrum/test'),
        library: '/nonexistent/libthmr_mp3.so');
    addTearDown(() async {
      await source.dispose();
      await server.close(force: true);
    });
    source.start();
    source.stop();
    source.start();
    expect(await source.retry().timeout(const Duration(seconds: 5)), isFalse);
    expect(source.isUnavailable, isTrue);
    expect(source.poll(64), isNull);
    await source.dispose().timeout(const Duration(seconds: 3));
  }, skip: !Platform.isLinux);
}
