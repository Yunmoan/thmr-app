import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/player/spectrum.dart';
import 'package:thmr_app/features/listen/widgets/now_playing_panel.dart';

class _Spectrum extends SpectrumSource {
  int starts = 0, stops = 0, polls = 0;

  @override
  void start() => starts++;

  @override
  void stop() => stops++;

  @override
  Float32List poll(int bands) {
    polls++;
    return Float32List.fromList(
        List.generate(bands, (i) => ((i + polls) % 11) / 10));
  }
}

void main() {
  for (final brightness in Brightness.values) {
    testWidgets('spectrum appearance and envelope in ${brightness.name}',
        (tester) async {
      tester.view.physicalSize = const Size(360, 80);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final playing = ValueNotifier(true);
      addTearDown(playing.dispose);
      final source = _Spectrum();
      final key = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: RepaintBoundary(
          key: key,
          child: Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: ValueListenableBuilder(
                  valueListenable: playing,
                  builder: (context, value, child) =>
                      AudioStrip(playing: value, source: source),
                ),
              ),
            ),
          ),
        ),
      ));
      final target = find.byKey(key);
      await expectLater(target,
          matchesGoldenFile('goldens/spectrum_${brightness.name}_initial.png'));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      await expectLater(target,
          matchesGoldenFile('goldens/spectrum_${brightness.name}_playing.png'));
      playing.value = false;
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }
      await expectLater(target,
          matchesGoldenFile('goldens/spectrum_${brightness.name}_paused.png'));
      expect(source.starts, 1);
      expect(source.stops, 1);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('playing spectrum samples at about 20 frames per second',
      (tester) async {
    final source = _Spectrum();
    await tester.pumpWidget(MaterialApp(
      home: AudioStrip(playing: true, source: source),
    ));
    await tester.pump(const Duration(milliseconds: 10));
    final initialPolls = source.polls;
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 10));
    }
    expect(source.polls - initialPolls, inInclusiveRange(19, 21));
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
