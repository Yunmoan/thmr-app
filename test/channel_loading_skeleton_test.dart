import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/theme/thmr_colors.dart';
import 'package:thmr_app/features/listen/widgets/channel_loading_skeleton.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final width in [320.0, 430.0, 1100.0]) {
      testWidgets(
          'channel skeleton fits $width in $brightness without a ticker',
          (tester) async {
        tester.view.physicalSize = Size(width, 660);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        await tester.pumpWidget(MaterialApp(
          theme: ThemeData(
              brightness: brightness,
              extensions: [ThmrTokens.resolve(AccentTheme.reimu, brightness)]),
          home: const Scaffold(
              body: Padding(
            padding: EdgeInsets.all(16),
            child: ChannelLoadingSkeleton(switching: true),
          )),
        ));
        await tester.pumpAndSettle();
        expect(find.bySemanticsLabel('正在切换频道…'), findsOneWidget);
        expect(find.text('正在切换频道…'), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byKey(const ValueKey('skeleton-player')), findsOneWidget);
        expect(
            find.byKey(const ValueKey('skeleton-control-0')), findsOneWidget);
        expect(find.byKey(const ValueKey('skeleton-history')),
            width >= 900 ? findsOneWidget : findsNothing);
        expect(find.byKey(const ValueKey('skeleton-queue')),
            width >= 900 ? findsOneWidget : findsNothing);
        expect(tester.binding.hasScheduledFrame, isFalse);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      });
    }
  }
}
