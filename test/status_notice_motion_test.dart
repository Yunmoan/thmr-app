import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/theme/thmr_motion.dart';
import 'package:thmr_app/shared/widgets/status_notice.dart';

void main() {
  Future<void> mount(WidgetTester tester, Widget child,
          {bool reduced = false}) =>
      tester.pumpWidget(MaterialApp(
          builder: (context, page) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
              child: page!),
          home: Scaffold(body: Center(child: child))));

  testWidgets('message enters gradually and retains content throughout exit',
      (tester) async {
    await mount(tester, const StatusNotice(message: '连接已恢复', duration: null));
    final motion = find
        .descendant(
            of: find.byType(ThmrFadeSlide),
            matching: find.byType(FadeTransition))
        .first;
    expect(tester.widget<FadeTransition>(motion).opacity.value, 0);
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.widget<FadeTransition>(motion).opacity.value,
        inExclusiveRange(0, 1));
    await tester.pump(ThmrMotion.duration);
    expect(tester.widget<FadeTransition>(motion).opacity.value, 1);
    await tester.tap(find.byTooltip('关闭提示'));
    await tester.pump();
    expect(find.text('连接已恢复'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 80));
    expect(tester.widget<FadeTransition>(motion).opacity.value,
        inExclusiveRange(0, 1));
    await tester.pump(ThmrMotion.exitDuration);
    expect(find.text('连接已恢复'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a new message during exit cannot be removed by the old exit',
      (tester) async {
    final message = ValueNotifier<String?>('第一条提示');
    addTearDown(message.dispose);
    await mount(
        tester,
        ValueListenableBuilder(
            valueListenable: message,
            builder: (_, value, __) =>
                StatusNotice(message: value, duration: null)));
    await tester.pumpAndSettle();
    message.value = null;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    message.value = '第二条提示';
    await tester.pumpAndSettle();
    expect(find.text('第二条提示'), findsOneWidget);
    expect(find.text('第一条提示'), findsNothing);
    await tester.pump(const Duration(seconds: 2));
    expect(find.text('第二条提示'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('expiry has an exit animation and null messages cancel timers',
      (tester) async {
    final message = ValueNotifier<String?>('短暂提示');
    addTearDown(message.dispose);
    await mount(
        tester,
        ValueListenableBuilder(
            valueListenable: message,
            builder: (_, value, __) => StatusNotice(
                message: value, duration: const Duration(seconds: 1))));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('短暂提示'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('短暂提示'), findsNothing);
    message.value = '新的提示';
    await tester.pumpAndSettle();
    message.value = null;
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 3));
    expect(find.text('新的提示'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'reduced motion has immediate visibility and no spinning indicator',
      (tester) async {
    final message = ValueNotifier<String?>('正在连接');
    addTearDown(message.dispose);
    await mount(
        tester,
        ValueListenableBuilder(
            valueListenable: message,
            builder: (_, value, __) =>
                StatusNotice(message: value, busy: true, duration: null)),
        reduced: true);
    await tester.pumpAndSettle();
    expect(find.text('正在连接'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(tester.binding.hasScheduledFrame, isFalse);
    message.value = null;
    await tester.pump();
    expect(find.text('正在连接'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
