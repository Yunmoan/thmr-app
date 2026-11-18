import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/player/spectrum.dart';
import 'package:thmr_app/core/state/large_screen_settings.dart';
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
    return amplitude == null
        ? null
        : (Float32List(bands)..fillRange(0, bands, amplitude));
  }
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
  testWidgets('all three scenes render real spectrum and clear on silence',
      (tester) async {
    await tester.runAsync(() async {
      await ui.FragmentProgram.fromAsset('shaders/large_screen_music.frag');
    });
    final source = _Spectrum();
    final frame = GlobalKey();
    Future<void> mount(LargeScreenMusicEffect effect, {bool playing = true}) =>
        tester.pumpWidget(MaterialApp(
          theme: ThemeData.dark(),
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
    }
    expect(scenes.length, 3);
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
