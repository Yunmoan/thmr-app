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

  testWidgets('spectrum frame widget allocations over one second',
      (tester) async {
    final source = _Spectrum();
    await tester.pumpWidget(MaterialApp(
      home: AudioStrip(playing: true, source: source),
    ));
    final paint = find.descendant(
        of: find.byType(AudioStrip), matching: find.byType(CustomPaint));
    final painters = <CustomPainter?>{};
    for (var i = 0; i < 21; i++) {
      await tester.pump(const Duration(milliseconds: 50));
      painters.add(tester.widget<CustomPaint>(paint).painter);
    }
    expect(painters.length, 1,
        reason: 'FFT frames should repaint without rebuilding the widgets');
    expect(source.polls, 21,
        reason: 'The original spectrum cadence must stay unchanged');
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('hidden and backgrounded spectra stop sampling', (tester) async {
    final source = _Spectrum();
    final visible = ValueNotifier(true);
    addTearDown(visible.dispose);
    await tester.pumpWidget(MaterialApp(
      home: ValueListenableBuilder(
        valueListenable: visible,
        child: AudioStrip(playing: true, source: source),
        builder: (context, enabled, child) =>
            TickerMode(enabled: enabled, child: child!),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 60));
    final foregroundPolls = source.polls;
    expect(foregroundPolls, greaterThan(0));
    visible.value = false;
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(source.polls, foregroundPolls);
    expect(source.stops, 1);
    visible.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(source.starts, 2);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    await tester.pump();
    final hiddenPolls = source.polls;
    await tester.pump(const Duration(seconds: 1));
    expect(source.polls, hiddenPolls);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(source.starts, 3);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
