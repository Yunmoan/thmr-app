import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/theme/thmr_theme.dart';
import 'package:thmr_app/shared/markdown/markdown_view.dart';

Widget _app(Widget child, {double textScale = 1}) => MaterialApp(
      theme: ThmrTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(12),
          child: child,
        ),
      ),
    );

void main() {
  testWidgets('渲染标题、段落、列表、代码块和引用', (tester) async {
    await tester.pumpWidget(_app(const MarkdownView(
      data: '### 本次构建\n\n'
          '修复了 **下载进度** 与 `重试` 逻辑。\n\n'
          '- 第一项\n- 第二项\n\n'
          '```dart\nfinal a = 1;\n```\n\n'
          '> 安装前请保存工作。',
    )));
    await tester.pumpAndSettle();
    expect(find.text('本次构建'), findsOneWidget);
    expect(find.text('修复了 下载进度 与 重试 逻辑。'), findsOneWidget);
    expect(find.text('第一项'), findsOneWidget);
    expect(find.text('第二项'), findsOneWidget);
    expect(find.text('final a = 1;'), findsOneWidget);
    expect(find.text('安装前请保存工作。'), findsOneWidget);
    expect(find.byType(SelectionArea), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('点击安全链接回调 Uri', (tester) async {
    final taps = <Uri>[];
    await tester.pumpWidget(_app(MarkdownView(
      data: '[发布页](https://example.com/release)',
      onLinkTap: taps.add,
    )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('发布页'));
    await tester.pump();
    expect(taps, [Uri.parse('https://example.com/release')]);
  });

  testWidgets('不安全的链接保留文本但不可点击', (tester) async {
    final taps = <Uri>[];
    await tester.pumpWidget(_app(MarkdownView(
      data: '[点击](javascript:alert(1))',
      onLinkTap: taps.add,
    )));
    await tester.pumpAndSettle();
    expect(find.text('点击'), findsOneWidget);
    await tester.tap(find.text('点击'));
    await tester.pump();
    expect(taps, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('为链接提供点击光标与下划线样式', (tester) async {
    await tester.pumpWidget(_app(const MarkdownView(
      data: '[发布页](https://example.com/release)',
      onLinkTap: _ignoreLink,
    )));
    await tester.pumpAndSettle();
    final span = tester.widget<Text>(find.text('发布页')).textSpan!;
    final link = (span as TextSpan).children!.single as TextSpan;
    expect(link.style?.decoration, TextDecoration.underline);
    expect(link.style?.color, ThmrTheme.light().colorScheme.primary);
    expect(link.recognizer, isNotNull);
  });

  testWidgets('空内容显示占位文本', (tester) async {
    await tester.pumpWidget(_app(const MarkdownView(
      data: '  \n\n',
      emptyText: '该版本未提供更新说明。',
    )));
    await tester.pumpAndSettle();
    expect(find.text('该版本未提供更新说明。'), findsOneWidget);
    expect(find.byType(SelectionArea), findsNothing);
  });

  testWidgets('窄屏和大字号下不溢出', (tester) async {
    tester.view.physicalSize = const Size(320, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(_app(
      const MarkdownView(
        data: '# 0.2.1\n\n'
            '### 桌面与大屏幕\n\n'
            '- Windows 在普通窗口和大屏幕模式之间切换更平滑，并保留普通页面的滚动位置与焦点。\n'
            '  - 嵌套说明 `thmr-app` 与 **粗体** 文本。\n'
            '1. 第一步\n2. 第二步\n\n'
            '```\nfinal result = await update.download();\n```\n\n'
            '> 引用一段较长的说明文字，用于检查窄屏下的换行表现。\n\n'
            '更新说明链接：[发布页](https://example.com/release)。',
        onLinkTap: _ignoreLink,
      ),
      textScale: 1.4,
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}

void _ignoreLink(Uri url) {}
