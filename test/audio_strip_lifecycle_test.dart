import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/player/spectrum.dart';
import 'package:thmr_app/features/listen/widgets/now_playing_panel.dart';

class _Spectrum extends SpectrumSource {
  int starts = 0;
  int stops = 0;
  int polls = 0;

  @override
  void start() => starts++;

  @override
  void stop() => stops++;

  @override
  Float32List poll(int bands) {
    polls++;
    return Float32List(bands)..fillRange(0, bands, polls.isEven ? 0.3 : 0.8);
  }
}

void main() {
  testWidgets('reduced motion suspends live spectrum and can resume it',
      (tester) async {
    final source = _Spectrum();
    final reduced = ValueNotifier(false);
    addTearDown(reduced.dispose);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => ValueListenableBuilder<bool>(
        valueListenable: reduced,
        builder: (_, value, __) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: value),
            child: child!),
      ),
      home: AudioStrip(playing: true, source: source),
    ));
    await tester.pump(const Duration(milliseconds: 60));
    expect(source.polls, greaterThan(0));
    reduced.value = true;
    await tester.pump();
    final polls = source.polls;
    await tester.pump(const Duration(seconds: 1));
    expect(source.polls, polls);
    expect(tester.binding.hasScheduledFrame, isFalse);
    reduced.value = false;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(source.polls, greaterThan(polls));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  const desktopPlatforms = TargetPlatformVariant({
    TargetPlatform.windows,
    TargetPlatform.linux,
    TargetPlatform.macOS,
  });

  testWidgets('visible spectrum keeps animating when the window loses focus',
      (tester) async {
    final source = _Spectrum();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    addTearDown(() {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    await tester.pumpWidget(MaterialApp(
      home: AudioStrip(playing: true, source: source),
    ));
    await tester.pump(const Duration(milliseconds: 60));
    expect(source.polls, greaterThan(0));
    final focusedPolls = source.polls;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 60));

    expect(source.stops, 0, reason: 'A visible unfocused window needs capture');
    expect(source.polls, greaterThan(focusedPolls),
        reason: 'The spectrum ticker must keep consuming live frames');

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    final hiddenPolls = source.polls;
    await tester.pump(const Duration(milliseconds: 120));
    expect(source.stops, 1);
    expect(source.polls, hiddenPolls);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(source.starts, 2);
    expect(source.polls, greaterThan(hiddenPolls));
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: desktopPlatforms);

  testWidgets(
      'an unfocused desktop strip respects page visibility and playback',
      (tester) async {
    final source = _Spectrum();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    addTearDown(() {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });

    Future<void> show({bool visible = true, bool playing = true}) async {
      await tester.pumpWidget(MaterialApp(
        home: TickerMode(
          enabled: visible,
          child: AudioStrip(playing: playing, source: source),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 60));
    }

    await show();
    expect(source.starts, 1);
    expect(source.polls, greaterThan(0));
    await show(visible: false);
    final hiddenPolls = source.polls;
    expect(source.stops, 1);
    await tester.pump(const Duration(milliseconds: 120));
    expect(source.polls, hiddenPolls);
    await show();
    expect(source.starts, 2);
    expect(source.polls, greaterThan(hiddenPolls));
    await show(playing: false);
    expect(source.stops, 2);
    final pausedPolls = source.polls;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 120));
    expect(source.starts, 2);
    expect(source.polls, pausedPolls);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: desktopPlatforms);

  testWidgets('a strip mounted while hidden waits until its window is visible',
      (tester) async {
    final source = _Spectrum();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    addTearDown(() {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    await tester.pumpWidget(MaterialApp(
      home: AudioStrip(playing: true, source: source),
    ));
    expect(source.starts, 0);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expect(source.starts, 1);
    expect(source.polls, greaterThan(0));
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: desktopPlatforms);

  testWidgets('mobile inactive state still suspends spectrum capture',
      (tester) async {
    final source = _Spectrum();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    addTearDown(() {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    });
    await tester.pumpWidget(MaterialApp(
      home: AudioStrip(playing: true, source: source),
    ));
    await tester.pump(const Duration(milliseconds: 60));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    final polls = source.polls;
    await tester.pump(const Duration(milliseconds: 120));
    expect(source.stops, 1);
    expect(source.polls, polls);
    await tester.pumpWidget(const SizedBox.shrink());
  },
      variant: const TargetPlatformVariant(
          {TargetPlatform.android, TargetPlatform.iOS}));
}
