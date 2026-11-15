import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thmr_app/core/theme/thmr_theme.dart';
import 'package:thmr_app/features/account/account_screen.dart';
import 'package:thmr_app/shared/widgets/input_help.dart';
import 'package:thmr_app/shared/widgets/thmr_panel.dart';

void main() {
  for (final width in [280.0, 600.0]) {
    for (final scale in [1.0, 2.0]) {
      for (final gamepad in [false, true]) {
        testWidgets(
            'legend columns align at $width px, $scale x, gamepad=$gamepad',
            (tester) async {
          await tester.pumpWidget(MaterialApp(
            theme: ThmrTheme.light(),
            home: Scaffold(
                body: SingleChildScrollView(
                    child: SizedBox(
              width: width,
              child: MediaQuery(
                  data: MediaQueryData(textScaler: TextScaler.linear(scale)),
                  child: InputHelpLegend(gamepad: gamepad)),
            ))),
          ));
          await tester.pumpAndSettle();
          final ids = gamepad
              ? [
                  'move',
                  'activate',
                  'back',
                  'play',
                  'search',
                  'previous',
                  'next',
                  'scroll',
                  'mute',
                  'help'
                ]
              : [
                  'next',
                  'previous',
                  'move',
                  'activate',
                  'pages',
                  'search',
                  'play',
                  'mute',
                  'volume',
                  'back',
                  'limits',
                  'help'
                ];
          double? textLeft;
          for (final id in ids) {
            final row = find.byKey(ValueKey('input-help-$id'));
            final prompt = find.descendant(
                of: row, matching: find.byType(InputPromptGroup));
            final glyphs =
                find.descendant(of: prompt, matching: find.byType(Wrap));
            expect(tester.getCenter(glyphs).dx,
                closeTo(tester.getCenter(prompt).dx, .01));
            final description =
                find.descendant(of: row, matching: find.byType(Text)).last;
            final left = tester.getTopLeft(description).dx;
            textLeft ??= left;
            expect(left, closeTo(textLeft, .01));
            expect(tester.widget<Text>(description).textAlign, TextAlign.start);
          }
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('key chords and their descriptions are read as one row',
      (tester) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: SizedBox(
                    width: 600, child: InputHelpLegend(gamepad: false))))));
    await tester.pumpAndSettle();
    final row = find.bySemanticsLabel(RegExp('Ctrl 加 F'));
    expect(row, findsOneWidget);
    expect(tester.getSemantics(row).getSemanticsData().label,
        contains('打开曲库并定位搜索框'));
    semantics.dispose();
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets(
      'settings help is a separate section below updates and before about',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: ThmrTheme.light(),
            home: const Scaffold(body: AccountScreen()))));
    await tester.pumpAndSettle();
    final list = tester.widget<ListView>(find.byType(ListView).first);
    final children =
        (list.childrenDelegate as SliverChildListDelegate).children;
    final help =
        children.indexWhere((w) => w is SectionHeader && w.title == '操作帮助');
    final network =
        children.indexWhere((w) => w is SectionHeader && w.title == '播放与网络');
    final about =
        children.indexWhere((w) => w is SectionHeader && w.title == '关于');
    expect(help, greaterThan(network));
    expect(about, greaterThan(help));
    expect(children[help + 1], isA<InputHelpCard>());
    expect(find.text('键盘与手柄操作（F1）'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  for (final platform in TargetPlatform.values) {
    testWidgets('settings help visibility on $platform', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(ProviderScope(
          child: MaterialApp(
        theme: ThmrTheme.light(),
        home: const Scaffold(body: AccountScreen()),
      )));
      await tester.pumpAndSettle();
      final list = tester.widget<ListView>(find.byType(ListView).first);
      final children =
          (list.childrenDelegate as SliverChildListDelegate).children;
      final mobile =
          platform == TargetPlatform.android || platform == TargetPlatform.iOS;
      expect(children.whereType<InputHelpCard>().length, mobile ? 0 : 1);
      expect(children.whereType<SectionHeader>().any((w) => w.title == '操作帮助'),
          !mobile);
      await tester.pumpWidget(const SizedBox.shrink());
    }, variant: TargetPlatformVariant.only(platform));
  }

  testWidgets('dialog switches legends and stays usable with large text',
      (tester) async {
    tester.view.physicalSize = const Size(360, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(
      builder: (_, child) => MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: child!),
      home: Builder(
          builder: (context) => Scaffold(
              body: TextButton(
                  onPressed: () => showInputHelp(context),
                  child: const Text('open')))),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('手柄'));
    await tester.pumpAndSettle();
    expect(find.text('按方向移动焦点'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(InputHelpDialog), findsNothing);
  });
}
