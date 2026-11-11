import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/player/adaptive_spectrum.dart';
import 'package:thmr_app/core/player/spectrum_fft.dart';

Float32List bandwidth(double cutoff, {int rate = 48000, int size = 2048}) {
  return Float32List.fromList(List.generate(size ~/ 2 + 1,
      (bin) => bin > 0 && bin * rate / size <= cutoff ? 0.02 : 1e-7));
}

void feed(AdaptiveSpectrum spectrum, Float32List frame, int first, int last,
    {int rate = 48000}) {
  for (var tick = first; tick <= last; tick++) {
    spectrum.add(frame, rate, Duration(milliseconds: tick * 50));
  }
}

void main() {
  for (final cutoff in [8000.0, 12000.0, 16000.0]) {
    test('$cutoff Hz cutoff fills the useful width after sustained evidence',
        () {
      final spectrum = AdaptiveSpectrum();
      final frame = bandwidth(cutoff);
      feed(spectrum, frame, 0, 50);
      expect(spectrum.upperHz, 24000); // no contraction for a short passage
      feed(spectrum, frame, 51, 180);
      expect(spectrum.upperHz, closeTo(cutoff * 1.15, 150));
      for (final count in [28, 64, 110]) {
        final bars = spectrum.bands(count)!;
        expect(bars, everyElement(inInclusiveRange(0, 1)));
        expect(bars.where((v) => v > 0.1).length, greaterThan(count * 0.9));
      }
    });
  }

  test(
      'full bandwidth has no empty tail at any supported bar count or FFT size',
      () {
    for (final size in [1024, 2048]) {
      for (final rate in [22050, 44100, 48000, 96000]) {
        final spectrum = AdaptiveSpectrum();
        feed(spectrum, bandwidth(rate / 2, rate: rate, size: size), 0, 100,
            rate: rate);
        expect(spectrum.upperHz, rate / 2);
        for (final count in [28, 64, 110, 128]) {
          expect(spectrum.bands(count), everyElement(greaterThan(0.1)));
        }
      }
    }
  });

  test('high-frequency recovery expands within one second', () {
    final spectrum = AdaptiveSpectrum();
    feed(spectrum, bandwidth(8000), 0, 180);
    final oldUpper = spectrum.upperHz;
    feed(spectrum, bandwidth(24000), 181, 200);
    expect(spectrum.upperHz, greaterThan(23000));
    expect(spectrum.upperHz, greaterThan(oldUpper));
  });

  test('silence, near-silence and polling freeze the learned range', () {
    final spectrum = AdaptiveSpectrum();
    feed(spectrum, bandwidth(8000), 0, 180);
    final upper = spectrum.upperHz;
    feed(spectrum, Float32List(1025), 181, 280);
    expect(spectrum.upperHz, upper);
    expect(spectrum.bands(64), everyElement(0));
    feed(spectrum, Float32List(1025)..fillRange(0, 1025, 1e-6), 281, 380);
    for (var i = 0; i < 200; i++) {
      spectrum.bands(i.isEven ? 28 : 110);
    }
    expect(spectrum.upperHz, upper);
  });

  test('a missing frame gap or silence interrupts contraction evidence', () {
    final spectrum = AdaptiveSpectrum();
    final frame = bandwidth(8000);
    feed(spectrum, frame, 0, 50);
    feed(spectrum, frame, 250, 290);
    expect(spectrum.upperHz, 24000);
    spectrum.add(Float32List(1025), 48000, const Duration(milliseconds: 14550));
    feed(spectrum, frame, 292, 340);
    expect(spectrum.upperHz, 24000);
  });

  test(
      'noise specks do not keep a low-pass stream expanded; bass keeps a floor',
      () {
    final spectrum = AdaptiveSpectrum();
    final frame = bandwidth(8000);
    frame[950] = 0.1; // isolated spike above the useful bandwidth
    feed(spectrum, frame, 0, 180);
    expect(spectrum.upperHz, lessThan(9500));
    final bass = AdaptiveSpectrum();
    feed(bass, bandwidth(200), 0, 240);
    expect(bass.upperHz, inInclusiveRange(4000, 4100));
  });

  test('sample-rate, FFT-size and source resets start at full bandwidth', () {
    final spectrum = AdaptiveSpectrum();
    feed(spectrum, bandwidth(8000), 0, 180);
    spectrum.add(
        bandwidth(8000, rate: 44100), 44100, const Duration(seconds: 10));
    expect(spectrum.upperHz, 22050);
    spectrum.add(bandwidth(8000, rate: 44100, size: 1024), 44100,
        const Duration(milliseconds: 10050));
    expect(spectrum.upperHz, 22050);
    spectrum.reset();
    expect(spectrum.bands(64), isNull);
    expect(spectrum.upperHz, 0);
  });

  test(
      'windowed PCM tones recover their bandwidth before normalization and AGC',
      () {
    const size = 2048, rate = 48000;
    final pcm = Float32List(size);
    for (final bin in [4, 16, 48, 96, 160, 320]) {
      for (var i = 0; i < size; i++) {
        pcm[i] += 0.02 * math.sin(2 * math.pi * bin * i / size);
      }
    }
    final frame = pcmMagnitudes(pcm);
    final plain = AdaptiveSpectrum(), agc = AdaptiveSpectrum(autoGain: true);
    feed(plain, frame, 0, 180);
    feed(agc, frame, 0, 180);
    expect(plain.upperHz, closeTo(8700, 150));
    expect(agc.upperHz, plain.upperHz);
    expect(agc.bands(110), everyElement(inInclusiveRange(0, 1)));
    frame[1000] = double.nan;
    frame[1001] = double.infinity;
    agc.add(frame, rate, const Duration(milliseconds: 9050));
    expect(agc.bands(110), everyElement(inInclusiveRange(0, 1)));
    agc.add(Float32List(1025), rate, const Duration(milliseconds: 9100));
    expect(agc.bands(110), everyElement(0));
  });
}
