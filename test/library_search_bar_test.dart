import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/platform/mobile_presentation.dart';
import 'package:thmr_app/core/theme/thmr_theme.dart';
import 'package:thmr_app/features/library/library_screen.dart';

void main() {
  testWidgets('曲库搜索框支持清空与独立圆角排序按钮', (tester) async {
    tester.view.physicalSize = const Size(375, 812);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(ProviderScope(
      overrides: [
        iosIsPadProvider.overrideWith((ref) async => false),
      ],
      child: MaterialApp(
        theme: ThmrTheme.light(),
        home: const Scaffold(body: LibraryScreen()),
      ),
    ));
    await tester.pumpAndSettle();

    // 初始无清空按钮，输入文字后出现并可一键清空。
    expect(find.byTooltip('清空'), findsNothing);
    await tester.enterText(find.byType(TextField), 'Bad Apple');
    await tester.pump();
    expect(find.byTooltip('清空'), findsOneWidget);

    await tester.tap(find.byTooltip('清空'));
    await tester.pump();
    expect(tester.widget<TextField>(find.byType(TextField)).controller?.text,
        isEmpty);
    expect(find.byTooltip('清空'), findsNothing);

    // 独立排序按钮可打开排序菜单并切换状态。
    await tester.tap(find.byTooltip('排序'));
    await tester.pumpAndSettle();
    expect(find.text('按艺术家'), findsOneWidget);
    await tester.tap(find.text('按艺术家'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));
}
