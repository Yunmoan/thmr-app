import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/player/spectrum.dart';
import 'package:thmr_app/core/player/spectrum_fft.dart';
import 'package:thmr_app/core/state/large_screen_settings.dart';
import 'package:thmr_app/core/theme/thmr_colors.dart';
import 'package:thmr_app/features/large_screen/large_screen_fluid_colors.dart';
import 'package:thmr_app/features/large_screen/large_screen_music_visual.dart';

class _Spectrum implements SpectrumSource {
  int starts = 0, stops = 0, polls = 0;
  double? level;

  @override
  void start() => starts++;

  @override
  void stop() => stops++;

  @override
  Float32List? poll(int bands) {
    polls++;
    final amplitude = level;
    if (amplitude == null) return null;
    return Float32List(bands)..fillRange(0, bands, amplitude);
  }
}

class _PcmToneSource implements SpectrumSource {
  static const _sampleRate = 48000;
  Float32List? _frame;

  void play(double frequency, double amplitude) {
    final samples = Float32List(_sampleRate ~/ 10);
    for (var i = 0; i < samples.length; i++) {
      samples[i] =
          amplitude * math.sin(2 * math.pi * frequency * i / _sampleRate);
    }
    _frame = PcmSpectrumDecoder().add(samples, 1, _sampleRate);
  }

  @override
  void start() {}

  @override
  void stop() {}

  @override
  Float32List? poll(int bands) {
    final frame = _frame;
    return frame == null
        ? null
        : logarithmicSpectrumBands(frame, bands, _sampleRate);
  }
}

class _TestArtwork extends ImageProvider<_TestArtwork> {
  const _TestArtwork(this.frame);

  final Future<ImageInfo> frame;

  @override
  Future<_TestArtwork> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture(this);

  @override
  ImageStreamCompleter loadImage(
          _TestArtwork key, ImageDecoderCallback decode) =>
      OneFrameImageStreamCompleter(key.frame);
}

Future<int> _rasterHash(WidgetTester tester, GlobalKey frame) async {
  final layer =
      frame.currentContext!.findRenderObject() as RenderRepaintBoundary;
  return (await tester.runAsync(() async {
    final image = await layer.toImage(pixelRatio: .5);
    try {
      final pixels = (await image.toByteData())!;
      return Object.hashAll(pixels.buffer.asUint32List());
    } finally {
      image.dispose();
    }
  }))!;
}

void main() {
  testWidgets('each scene uses the character palette and clears on silence',
      (tester) async {
    await tester.runAsync(() async {
      await ui.FragmentProgram.fromAsset('shaders/large_screen_music.frag');
    });
    final source = _Spectrum();
    final frame = GlobalKey();
    Future<void> mount(LargeScreenMusicEffect effect,
            {bool playing = true, ThmrTokens tokens = ThmrTokens.reimuDark}) =>
        tester.pumpWidget(MaterialApp(
          theme: ThemeData.dark().copyWith(extensions: [tokens]),
          themeAnimationDuration: Duration.zero,
          home: Center(
            child: RepaintBoundary(
              key: frame,
              child: SizedBox(
                width: 480,
                height: 270,
                child: ColoredBox(
                  color: const Color(0xff15151e),
                  child: LargeScreenMusicVisual(
                    effect: effect,
                    intensity: .85,
                    lowPower: false,
                    playing: playing,
                    source: source,
                  ),
                ),
              ),
            ),
          ),
        ));

    await mount(LargeScreenMusicEffect.aurora);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 64));
    expect(source.starts, 1);
    expect(source.polls, greaterThan(0));
    final quiet = await _rasterHash(tester, frame);
    final scenes = <int>{};
    for (final effect in LargeScreenMusicEffect.values.skip(1)) {
      source.level = .7;
      await mount(effect);
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 34));
      }
      final rendered = await _rasterHash(tester, frame);
      expect(rendered, isNot(quiet), reason: effect.name);
      scenes.add(rendered);
      await mount(effect, tokens: ThmrTokens.marisaDark);
      expect(await _rasterHash(tester, frame), isNot(rendered),
          reason: '${effect.name} needs to reflect a new character palette');
    }
    expect(scenes.length, 5);
    expect(source.starts, 1, reason: 'style changes reuse the live source');

    source.level = null;
    for (var i = 0; i < 64; i++) {
      await tester.pump(const Duration(milliseconds: 34));
    }
    expect(await _rasterHash(tester, frame), quiet);
    await mount(LargeScreenMusicEffect.prism, playing: false);
    await tester.pumpAndSettle();
    expect(source.stops, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('mirrored spectrum plots real PCM and responds to quiet tones',
      (tester) async {
    final source = _PcmToneSource()..play(140, .75);
    final frame = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: RepaintBoundary(
          key: frame,
          child: SizedBox(
            width: 480,
            height: 272,
            child: LargeScreenMusicVisual(
              effect: LargeScreenMusicEffect.spectrum,
              intensity: 1,
              lowPower: false,
              playing: true,
              source: source,
            ),
          ),
        ),
      ),
    ));
    Future<({int left, int right, int top, int bottom})> visibleBars() async {
      for (var i = 0; i < 32; i++) {
        await tester.pump(const Duration(milliseconds: 34));
      }
      final layer =
          frame.currentContext!.findRenderObject() as RenderRepaintBoundary;
      return (await tester.runAsync(() async {
        final image = await layer.toImage(pixelRatio: .5);
        try {
          final pixels = (await image.toByteData())!;
          final centerX = image.width ~/ 2;
          final centerY = image.height ~/ 2;
          var left = 0, right = 0, top = 0, bottom = 0;
          for (var y = 0; y < image.height; y++) {
            for (var x = 0; x < image.width; x++) {
              final alpha = pixels.getUint8((y * image.width + x) * 4 + 3);
              if (alpha < 16) continue;
              if (x < centerX) {
                left++;
              } else {
                right++;
              }
              if (y < centerY) {
                top++;
              } else {
                bottom++;
              }
            }
          }
          return (left: left, right: right, top: top, bottom: bottom);
        } finally {
          image.dispose();
        }
      }))!;
    }

    final bass = await visibleBars();
    expect(bass.left, greaterThan(100));
    expect(bass.right, 0);
    expect(bass.top, closeTo(bass.bottom, 40));
    source.play(6000, .00046);
    final treble = await visibleBars();
    expect(treble.right, greaterThan(0));
    expect(treble.left, 0);
    expect(treble.top, closeTo(treble.bottom, 3));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'fluid follows the current artwork and falls back on load failure',
      (tester) async {
    final frame = GlobalKey();
    Future<void> mount(ImageProvider<Object>? artwork) => tester.pumpWidget(
          MaterialApp(
            theme:
                ThemeData.dark().copyWith(extensions: [ThmrTokens.reimuDark]),
            home: RepaintBoundary(
              key: frame,
              child: LargeScreenFluidArtwork(
                artwork: artwork,
                builder: (_, colors) => LargeScreenMusicVisual(
                  effect: LargeScreenMusicEffect.fluid,
                  intensity: 1,
                  lowPower: false,
                  playing: false,
                  source: null,
                  artworkColors: colors,
                ),
              ),
            ),
          ),
        );
    Future<Color> sample() async {
      final layer =
          frame.currentContext!.findRenderObject() as RenderRepaintBoundary;
      return (await tester.runAsync(() async {
        final image = await layer.toImage(pixelRatio: .05);
        try {
          final bytes = (await image.toByteData(
              format: ui.ImageByteFormat.rawStraightRgba))!;
          final i = (image.width + 1) * 4;
          return Color.fromARGB(255, bytes.getUint8(i), bytes.getUint8(i + 1),
              bytes.getUint8(i + 2));
        } finally {
          image.dispose();
        }
      }))!;
    }

    Future<ImageInfo> solidCover(Color color) async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawPaint(Paint()..color = color);
      final picture = recorder.endRecording();
      final image = (await tester.runAsync(() => picture.toImage(32, 32)))!;
      picture.dispose();
      return ImageInfo(image: image);
    }

    Future<Color> waitForColor(bool Function(Color) matches) async {
      for (var i = 0; i < 24; i++) {
        await tester.pump(const Duration(milliseconds: 80));
        final color = await sample();
        if (matches(color)) return color;
      }
      throw StateError('The expected artwork color did not render');
    }

    await tester.runAsync(
        () => ui.FragmentProgram.fromAsset('shaders/large_screen_music.frag'));
    await mount(null);
    await tester.pumpAndSettle();
    final fallback = await sample();
    final first = Completer<ImageInfo>();
    await mount(_TestArtwork(first.future));
    final next = Completer<ImageInfo>();
    await mount(_TestArtwork(next.future));
    final staleImage = await solidCover(const Color(0xff0820ff));
    first.complete(staleImage);
    await tester.pump();
    expect(await sample(), fallback);
    next.complete(await solidCover(const Color(0xff06d883)));
    final green = await waitForColor((c) => c.g > c.r + .1);
    expect(green, isNot(fallback));

    final broken = Completer<ImageInfo>();
    await mount(_TestArtwork(broken.future));
    broken.completeError(StateError('cover cannot be decoded'));
    await waitForColor((c) => c == fallback);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('each fluid preset moves the gradient along its own trajectory',
      (tester) async {
    await tester.runAsync(
        () => ui.FragmentProgram.fromAsset('shaders/large_screen_music.frag'));
    final frame = GlobalKey();
    final endFrames = <int>{};
    for (final preset in LargeScreenFluidMotion.values.skip(1)) {
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: frame,
            child: SizedBox(
              width: 480,
              height: 270,
              child: LargeScreenMusicVisual(
                key: ValueKey(preset),
                effect: LargeScreenMusicEffect.fluid,
                intensity: .8,
                lowPower: false,
                playing: true,
                source: null,
                fluidMotion: preset,
              ),
            ),
          ),
        ),
      ));
      await tester.pump();
      final start = await _rasterHash(tester, frame);
      for (var i = 0; i < 28; i++) {
        await tester.pump(const Duration(milliseconds: 34));
      }
      final end = await _rasterHash(tester, frame);
      expect(end, isNot(start), reason: preset.name);
      endFrames.add(end);
    }
    expect(endFrames.length, 3);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('low-power cadence and hidden or reduced-motion capture',
      (tester) async {
    final source = _Spectrum()..level = .6;
    Future<void> mount({
      bool visible = true,
      bool reduced = false,
      bool lowPower = false,
    }) =>
        tester.pumpWidget(MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: TickerMode(
              enabled: visible,
              child: LargeScreenMusicVisual(
                effect: LargeScreenMusicEffect.prism,
                intensity: .6,
                lowPower: lowPower,
                playing: true,
                source: source,
              ),
            ),
          ),
        ));
    Future<int> pollsPerSecond() async {
      final before = source.polls;
      for (var i = 0; i < 60; i++) {
        await tester.pump(const Duration(milliseconds: 17));
      }
      return source.polls - before;
    }

    await mount();
    expect(await pollsPerSecond(), inInclusiveRange(28, 31));
    await mount(lowPower: true);
    expect(await pollsPerSecond(), inInclusiveRange(14, 16));
    expect(source.starts, 1);

    await mount(visible: false);
    expect(source.stops, 1);
    expect(await pollsPerSecond(), 0);
    await mount(reduced: true);
    expect(source.starts, 1);
    await mount();
    expect(source.starts, 2);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    expect(source.stops, 2);
    await tester.pump();
    expect(await pollsPerSecond(), 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    expect(source.starts, 3);
    await tester.pumpWidget(const SizedBox.shrink());
    expect(source.stops, 3);
  });
}
