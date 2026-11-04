import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/player/spectrum_android.dart';
import 'package:thmr_app/features/listen/widgets/now_playing_panel.dart';

void main() {
  testWidgets('Android spectrum retry action fits a narrow play bar',
      (tester) async {
    tester.view.physicalSize = const Size(120, 100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(AndroidSpectrum.channel, (call) async {
      if (call.method == 'start') return 'unavailable';
      if (call.method == 'stop') return true;
      return null;
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(AndroidSpectrum.channel, null));

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 100,
          child: AudioStrip(
            playing: true,
            source: AndroidSpectrum.forTesting(() => 'https://radio.test/live'),
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('频谱'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}
