import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/theme/thmr_motion.dart';
import 'package:thmr_app/shared/widgets/delay_fade_in.dart';
import 'package:thmr_app/shared/widgets/persistent_tab_page.dart';

class _MotionHost extends StatefulWidget {
  const _MotionHost({super.key});
  @override
  State<_MotionHost> createState() => _MotionHostState();
}

class _MotionHostState extends State<_MotionHost>
    with SingleTickerProviderStateMixin {
  late final controller = AnimationController(
      vsync: this,
      duration: ThmrMotion.duration,
      reverseDuration: ThmrMotion.exitDuration);
  bool reduced = false;
  void reduceMotion() => setState(() => reduced = true);
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
          home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Scaffold(
            body: ThmrFadeSlide(
                animation: controller,
                child: const TextField(key: ValueKey('persistent-input')))),
      ));
}

void main() {
  testWidgets(
      'portrait content remains centered in a square transition viewport',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Center(
            child: SizedBox.square(
      dimension: 240,
      child: ThmrAnimatedContent(
          alignment: Alignment.center,
          child: SizedBox(key: ValueKey('portrait'), width: 80, height: 160)),
    ))));
    expect(tester.getRect(find.byKey(const ValueKey('portrait'))).center,
        tester.getRect(find.byType(ThmrAnimatedContent)).center);
  });

  testWidgets(
      'size changes snap without re-layout errors and retain input state',
      (tester) async {
    final reduced = ValueNotifier(false);
    final height = ValueNotifier(100.0);
    addTearDown(reduced.dispose);
    addTearDown(height.dispose);
    await tester.pumpWidget(MaterialApp(
        home: ValueListenableBuilder(
            valueListenable: reduced,
            builder: (_, reduce, __) => MediaQuery(
                data: MediaQueryData(disableAnimations: reduce),
                child: Scaffold(
                    body: Align(
                        alignment: Alignment.topLeft,
                        child: ValueListenableBuilder(
                            valueListenable: height,
                            builder: (_, value, __) => ThmrAnimatedSize(
                                child: SizedBox(
                                    width: 250,
                                    height: value,
                                    child: const TextField())))))))));
    final input = tester.state(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'saved');
    height.value = 150;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    reduced.value = true;
    await tester.pump();
    height.value = 75;
    await tester.pump();
    expect(tester.getSize(find.byType(ThmrAnimatedSize)).height, 75);
    expect(tester.state(find.byType(TextField)), same(input));
    expect(find.text('saved'), findsOneWidget);
    expect(tester.takeException(), isNull);
    reduced.value = false;
    await tester.pumpAndSettle();
    expect(tester.state(find.byType(TextField)), same(input));
  });

  for (final reduced in [false, true]) {
    testWidgets('snackbars use shared entrance and exit with reduced=$reduced',
        (tester) async {
      late BuildContext pageContext;
      await tester.pumpWidget(MaterialApp(
          home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Scaffold(body: Builder(builder: (context) {
          pageContext = context;
          return const SizedBox.expand();
        })),
      )));
      final messenger = ScaffoldMessenger.of(pageContext);
      final shown = messenger.showThmrSnackBar(
          pageContext, const SnackBar(content: Text('saved')));
      await tester.pump();
      final animation =
          tester.widget<SnackBar>(find.byType(SnackBar)).animation!;
      expect(animation.value, reduced ? 1 : 0);
      if (!reduced) {
        await tester.pump(const Duration(milliseconds: 100));
        expect(animation.value, inExclusiveRange(0, 1));
        await tester.pump(ThmrMotion.duration);
      }
      shown.close();
      await tester.pump();
      if (!reduced) {
        await tester.pump(const Duration(milliseconds: 80));
        expect(animation.value, inExclusiveRange(0, 1));
      }
      await tester.pumpAndSettle();
      expect(find.text('saved'), findsNothing);
    });
  }

  testWidgets('reducing motion during a replacement finishes it immediately',
      (tester) async {
    final reduced = ValueNotifier(false);
    final selected = ValueNotifier(false);
    addTearDown(reduced.dispose);
    addTearDown(selected.dispose);
    await tester.pumpWidget(MaterialApp(
        home: ValueListenableBuilder(
      valueListenable: reduced,
      builder: (_, reduce, __) => MediaQuery(
        data: MediaQueryData(disableAnimations: reduce),
        child: Scaffold(
            body: ValueListenableBuilder(
                valueListenable: selected,
                builder: (_, second, __) => ThmrAnimatedContent(
                    child: Text(second ? 'second' : 'first',
                        key: ValueKey(second))))),
      ),
    )));
    selected.value = true;
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    reduced.value = true;
    await tester.pump();
    await tester.pump();
    expect(find.text('first'), findsNothing);
    final fade = find.descendant(
        of: find.byType(ThmrAnimatedContent),
        matching: find.byType(FadeTransition));
    expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
    expect(tester.binding.hasScheduledFrame, isFalse);
    reduced.value = false;
    await tester.pump();
    expect(find.text('first'), findsNothing);
    expect(tester.widget<FadeTransition>(fade).opacity.value, 1);
  });

  testWidgets('reversing a partial transition does not jump opacity',
      (tester) async {
    final host = GlobalKey<_MotionHostState>();
    await tester.pumpWidget(_MotionHost(key: host));
    final state = host.currentState!;
    double opacity() => tester
        .widget<FadeTransition>(find.byType(FadeTransition).last)
        .opacity
        .value;
    state.controller.forward();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final before = opacity();
    state.controller.reverse();
    await tester.pump();
    expect(opacity(), closeTo(before, .001));
    await tester.pump(const Duration(milliseconds: 30));
    final reverse = opacity();
    state.controller.forward();
    await tester.pump();
    expect(opacity(), closeTo(reverse, .001));
    await tester.pumpAndSettle();
    expect(opacity(), 1);
  });

  testWidgets('reducing motion preserves the current input subtree',
      (tester) async {
    final host = GlobalKey<_MotionHostState>();
    await tester.pumpWidget(_MotionHost(key: host));
    host.currentState!.controller.value = 1;
    await tester.pump();
    final input = tester.state(find.byType(TextField));
    await tester.enterText(find.byType(TextField), 'Touhou');
    host.currentState!.reduceMotion();
    await tester.pump();
    expect(tester.state(find.byType(TextField)), same(input));
    expect(find.text('Touhou'), findsOneWidget);
  });

  testWidgets('outgoing content keeps its original dimensions', (tester) async {
    final selected = ValueNotifier(false);
    addTearDown(selected.dispose);
    Widget body() => ValueListenableBuilder(
        valueListenable: selected,
        builder: (_, small, __) => ThmrAnimatedContent(
            child: SizedBox(
                key: ValueKey(small ? 'short-content' : 'long-content'),
                width: small ? 90 : 260,
                height: small ? 30 : 140)));
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Align(alignment: Alignment.topLeft, child: body()))));
    await tester.pumpAndSettle();
    final oldSize = tester.getSize(find.byKey(const ValueKey('long-content')));
    selected.value = true;
    await tester.pump();
    expect(tester.getSize(find.byKey(const ValueKey('long-content'))), oldSize);
    expect(
        tester.getSize(find.byType(ThmrAnimatedContent)), const Size(90, 30));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('long-content')), findsNothing);
  });

  testWidgets('delayed entrance does not hide content with reduced motion',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: Scaffold(
          body: DelayFadeIn(delay: Duration(seconds: 2), child: Text('ready'))),
    )));
    await tester.pump();
    expect(find.text('ready').hitTestable(), findsOneWidget);
    final opacity = find.descendant(
        of: find.byType(DelayFadeIn), matching: find.byType(AnimatedOpacity));
    if (opacity.evaluate().isNotEmpty) {
      expect(tester.widget<AnimatedOpacity>(opacity).opacity, 1);
    }
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('reduced tab transitions finish without a hidden ticker',
      (tester) async {
    final active = ValueNotifier(false);
    addTearDown(active.dispose);
    await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
      data: const MediaQueryData(disableAnimations: true),
      child: Scaffold(
          body: ValueListenableBuilder(
              valueListenable: active,
              builder: (_, value, __) =>
                  PersistentTabPage(active: value, child: const Text('tab')))),
    )));
    active.value = true;
    await tester.pump();
    await tester.pump();
    expect(find.text('tab'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });
}
