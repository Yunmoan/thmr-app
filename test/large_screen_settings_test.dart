import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thmr_app/core/state/large_screen_settings.dart';
import 'package:thmr_app/core/theme/thmr_theme.dart';
import 'package:thmr_app/features/large_screen/large_screen_settings_panel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('all presentation preferences survive a fresh controller', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = LargeScreenSettingsController();
    await controller.ready;
    final chosen = const LargeScreenSettings().copyWith(
      layout: LargeScreenLayout.coverRight,
      queue: LargeScreenQueue.list,
      framing: LargeScreenFraming.fit,
      coverFit: LargeScreenCoverFit.cover,
      cardLayout: true,
      illustrationPosition: LargeScreenIllustrationPosition.left,
      themeMode: ThemeMode.dark,
      queueCount: 8,
      textScale: 1.3,
      showIllustration: false,
      showProgress: false,
      showQueueCovers: false,
      showControls: false,
      autoHideControls: false,
      startFullScreen: false,
    );
    await controller.update(chosen);
    final restored = LargeScreenSettingsController();
    await restored.ready;
    expect(restored.state.toJson(), chosen.toJson());
    controller.dispose();
    restored.dispose();
  });

  test('corrupt and out-of-range preferences fall back safely', () async {
    SharedPreferences.setMockInitialValues({'largeScreen': '{broken'});
    final invalid = LargeScreenSettingsController();
    await invalid.ready;
    expect(invalid.state.toJson(), const LargeScreenSettings().toJson());
    invalid.dispose();
    SharedPreferences.setMockInitialValues({
      'largeScreen': jsonEncode({
        'layout': 'unknown',
        'queue': 9,
        'queueCount': 999,
        'textScale': -1,
        'showProgress': 'false',
      })
    });
    final bounded = LargeScreenSettingsController();
    await bounded.ready;
    expect(bounded.state.layout, LargeScreenLayout.adaptive);
    expect(bounded.state.queue, LargeScreenQueue.strip);
    expect(bounded.state.queueCount, 8);
    expect(bounded.state.textScale, .8);
    expect(bounded.state.showProgress, isTrue);
    bounded.dispose();
  });

  test('a user selection wins over startup and rapid saves retain the last one',
      () async {
    SharedPreferences.setMockInitialValues({
      'largeScreen': jsonEncode({'layout': 'coverRight'})
    });
    final controller = LargeScreenSettingsController();
    await Future.wait([
      controller.update(
          const LargeScreenSettings(layout: LargeScreenLayout.centered)),
      controller.update(
          const LargeScreenSettings(layout: LargeScreenLayout.coverLeft)),
      controller.update(const LargeScreenSettings(
          layout: LargeScreenLayout.adaptive, queue: LargeScreenQueue.hidden)),
    ]);
    await controller.ready;
    final restored = LargeScreenSettingsController();
    await restored.ready;
    expect(restored.state.layout, LargeScreenLayout.adaptive);
    expect(restored.state.queue, LargeScreenQueue.hidden);
    expect(controller.state.toJson(), restored.state.toJson());
    controller.dispose();
    restored.dispose();
  });

  for (final width in [280.0, 760.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('settings choices fit $width px at text scale $scale',
          (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(width, 900);
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: ThmrTheme.light(),
            builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(scale)),
                child: child!),
            home: const Scaffold(
                body: SingleChildScrollView(child: LargeScreenSettingsPanel())),
          ),
        ));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('封面在右'));
        await tester.pumpAndSettle();
        expect(container.read(largeScreenSettingsProvider).layout,
            LargeScreenLayout.coverRight);
        await tester.ensureVisible(find.text('居中适应'));
        await tester.tap(find.text('居中适应'));
        await tester.pumpAndSettle();
        expect(container.read(largeScreenSettingsProvider).framing,
            LargeScreenFraming.fit);
        await tester.ensureVisible(find.text('隐藏'));
        await tester.tap(find.text('隐藏'));
        await tester.pumpAndSettle();
        expect(container.read(largeScreenSettingsProvider).queue,
            LargeScreenQueue.hidden);
        expect(find.text('队列曲目数'), findsNothing);
        await tester.ensureVisible(find.text('恢复默认'));
        await tester.tap(find.text('恢复默认'));
        await tester.pumpAndSettle();
        expect(container.read(largeScreenSettingsProvider).toJson(),
            const LargeScreenSettings().toJson());
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      });
    }
  }

  testWidgets('personalization entry opens a separate settings page',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
            theme: ThmrTheme.light(),
            home: const Scaffold(body: LargeScreenSettingsEntry()))));
    await tester.tap(find.text('大屏幕模式'));
    await tester.pumpAndSettle();
    expect(find.byType(LargeScreenSettingsPanel), findsOneWidget);
    expect(find.text('布局'), findsOneWidget);
    expect(find.text('大屏主题'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
