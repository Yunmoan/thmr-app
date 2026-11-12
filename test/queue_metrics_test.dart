import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/models/models.dart';
import 'package:thmr_app/core/theme/thmr_colors.dart';
import 'package:thmr_app/features/listen/widgets/side_info_column.dart';

void main() {
  testWidgets('queue columns retain alignment and follow text scaling',
      (tester) async {
    tester.view.physicalSize = const Size(480, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final status = StationStatus.fromJson({
      'station': {'id': 'test', 'enabled': true},
      'queue': [
        for (var i = 0; i < 200; i++)
          {
            'trackId': '$i',
            'title': 'Track $i',
            'artist': 'THMR',
            'durationSec': i == 199 ? 3600 : 120,
            'plannedStartMs':
                DateTime.utc(2026, 11, 12, 12, i).millisecondsSinceEpoch,
          },
      ],
    });

    Future<void> show(Brightness brightness, double scale) async {
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
          brightness: brightness,
          extensions: [ThmrTokens.resolve(AccentTheme.reimu, brightness)],
        ),
        home: MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(scale)),
          child: Scaffold(body: SideInfoColumn(status: status)),
        ),
      ));
      await tester.pumpAndSettle();
    }

    await show(Brightness.light, 1);
    final index = find.text('#1');
    final time = find.text('02:00').first;
    final originalIndexWidth = tester.getSize(index).width;
    final originalTimeWidth = tester.getSize(time).width;
    final originalTitleLeft = tester.getTopLeft(find.text('Track 0')).dx;
    expect(originalIndexWidth, greaterThan(0));

    await show(Brightness.dark, 1);
    expect(tester.getSize(index).width, originalIndexWidth);
    expect(tester.getSize(time).width, originalTimeWidth);
    expect(tester.getTopLeft(find.text('Track 0')).dx, originalTitleLeft);

    await show(Brightness.dark, 1.5);
    expect(tester.getSize(index).width, greaterThan(originalIndexWidth));
    expect(tester.getSize(time).width, greaterThan(originalTimeWidth));
    await tester.binding.handleSystemMessage({'type': 'fontsChange'});
    await tester.pump();
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 11));
    await tester.binding.handleSystemMessage({'type': 'fontsChange'});
    expect(tester.takeException(), isNull);
  });
}
