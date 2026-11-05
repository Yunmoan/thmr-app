import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/theme/thmr_theme.dart';
import 'package:thmr_app/features/account/about_panel.dart';

void main() {
  for (final brightness in [Brightness.light, Brightness.dark]) {
    for (final width in [320.0, 920.0]) {
      testWidgets('关于区域在 $brightness、${width.toInt()}px 下可阅读', (tester) async {
        tester.view.physicalSize = Size(width, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final theme = brightness == Brightness.dark
            ? ThmrTheme.dark()
            : ThmrTheme.light();
        await tester.pumpWidget(MaterialApp(
          theme: theme,
          home: const Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(12),
                child: AboutPanel(version: '0.1.3'),
              ),
            ),
          ),
        ));
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('客户端 · v0.1.3'), findsOneWidget);
        expect(find.text('云默安'), findsOneWidget);
        expect(find.text('1094578162'), findsOneWidget);
        final title = tester.widget<Text>(find.text('版权与服务'));
        expect(title.style?.color, theme.thmr.ink);
      });
    }
  }

  test('深色主题的错误色对比度和选项文字', () {
    final dark = ThmrTheme.dark(AccentTheme.marisa);
    expect(dark.colorScheme.error, isNot(dark.colorScheme.primary));
    expect(_contrast(dark.colorScheme.error, dark.colorScheme.onError),
        greaterThanOrEqualTo(4.5));
    expect(dark.chipTheme.labelStyle?.color, dark.thmr.ink);
    expect(
      dark.segmentedButtonTheme.style?.foregroundColor
          ?.resolve({WidgetState.selected}),
      dark.thmr.ink,
    );
  });
}

double _contrast(Color a, Color b) {
  final light = a.computeLuminance() > b.computeLuminance() ? a : b;
  final dark = identical(light, a) ? b : a;
  return (light.computeLuminance() + 0.05) / (dark.computeLuminance() + 0.05);
}
