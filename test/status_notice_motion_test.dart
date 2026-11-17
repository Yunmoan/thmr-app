import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/theme/thmr_motion.dart';
import 'package:thmr_app/shared/widgets/status_notice.dart';
import 'package:thmr_app/shared/widgets/message_body.dart';

void main() {
  for (final brightness in Brightness.values) {
    for (final width in [360.0, 1280.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('message styles match at $brightness / $width / $scale',
            (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(width, 800);
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final message = ValueNotifier<String?>('状态消息');
          addTearDown(message.dispose);
          late BuildContext pageContext;
          await tester.pumpWidget(MaterialApp(
            theme: ThemeData(brightness: brightness),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: Scaffold(body: Builder(builder: (context) {
              pageContext = context;
              return Stack(children: [
                Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: ValueListenableBuilder(
                        valueListenable: message,
                        builder: (_, value, __) =>
                            StatusNotice(message: value, duration: null))),
              ]);
            })),
          ));
          await tester.pumpAndSettle();
          final statusRect = tester.getRect(find.byType(MessageBody));
          final statusStyle =
              DefaultTextStyle.of(tester.element(find.text('状态消息'))).style;
          message.value = null;
          await tester.pumpAndSettle();
          ScaffoldMessenger.of(pageContext).showThmrSnackBar(
              pageContext, const SnackBar(content: Text('提示消息')));
          await tester.pumpAndSettle();
          expect(tester.getRect(find.byType(MessageBody)), statusRect);
          final messageStyle =
              DefaultTextStyle.of(tester.element(find.text('提示消息'))).style;
          expect(messageStyle.color, statusStyle.color);
          expect(messageStyle.fontSize, statusStyle.fontSize);
          tester.view.physicalSize = const Size(320, 800);
          await tester.pumpAndSettle();
          expect(tester.getSize(find.byType(MessageBody)).width, 288);
          await tester.tap(find.byTooltip('关闭提示'));
          await tester.pumpAndSettle();
          expect(find.text('提示消息'), findsNothing);
          expect(tester.takeException(), isNull);
        });
      }
    }
  }

  testWidgets('unified messages preserve actions and callbacks',
      (tester) async {
    late BuildContext pageContext;
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Builder(builder: (context) {
      pageContext = context;
      return const SizedBox.expand();
    }))));
    var visible = false;
    var acted = false;
    final controller = ScaffoldMessenger.of(pageContext).showThmrSnackBar(
        pageContext,
        SnackBar(
          content: const Text('已更新'),
          onVisible: () => visible = true,
          action: SnackBarAction(label: '撤回', onPressed: () => acted = true),
        ));
    await tester.pumpAndSettle();
    expect(visible, isTrue);
    await tester.pump(const Duration(seconds: 10));
    expect(find.text('已更新'), findsOneWidget);
    await tester.tap(find.text('撤回'));
    await tester.pumpAndSettle();
    expect(acted, isTrue);
    expect(await controller.closed, SnackBarClosedReason.action);
  });

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
