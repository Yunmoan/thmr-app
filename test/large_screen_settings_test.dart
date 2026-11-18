import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thmr_app/core/state/large_screen_settings.dart';
import 'package:thmr_app/core/theme/thmr_theme.dart';
import 'package:thmr_app/features/large_screen/large_screen_settings_panel.dart';
import 'package:thmr_app/shared/widgets/thmr_slider.dart';

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
      keepScreenOn: true,
      musicEffect: LargeScreenMusicEffect.fluid,
      musicEffectIntensity: .9,
      musicEffectLowPower: true,
      fluidMotion: LargeScreenFluidMotion.tide,
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
        'musicEffect': 'missing-effect',
        'musicEffectIntensity': 2,
        'fluidMotion': 'broken-motion',
      })
    });
    final bounded = LargeScreenSettingsController();
    await bounded.ready;
    expect(bounded.state.layout, LargeScreenLayout.adaptive);
    expect(bounded.state.queue, LargeScreenQueue.strip);
    expect(bounded.state.queueCount, 8);
    expect(bounded.state.textScale, .8);
    expect(bounded.state.showProgress, isTrue);
    expect(bounded.state.keepScreenOn, isFalse);
    expect(bounded.state.musicEffect, LargeScreenMusicEffect.aurora);
    expect(bounded.state.musicEffectIntensity, 1);
    expect(bounded.state.musicEffectLowPower, isFalse);
    expect(bounded.state.fluidMotion, LargeScreenFluidMotion.automatic);
    expect(LargeScreenSettings.fromJson(const {}).musicEffectIntensity, .6);
    bounded.dispose();
  });

  test('older settings use the default effect and a saved off choice survives',
      () async {
    SharedPreferences.setMockInitialValues({
      'largeScreen': jsonEncode({'layout': 'coverRight'}),
    });
    final legacy = LargeScreenSettingsController();
    await legacy.ready;
    expect(legacy.state.layout, LargeScreenLayout.coverRight);
    expect(legacy.state.musicEffect, LargeScreenMusicEffect.aurora);
    expect(legacy.state.fluidMotion, LargeScreenFluidMotion.automatic);
    await legacy
        .update(legacy.state.copyWith(musicEffect: LargeScreenMusicEffect.off));
    final restored = LargeScreenSettingsController();
    await restored.ready;
    expect(restored.state.musicEffect, LargeScreenMusicEffect.off);
    legacy.dispose();
    restored.dispose();
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
        Finder card(LargeScreenMusicEffect effect) =>
            find.byKey(ValueKey('music-effect-${effect.name}'));
        for (final effect in LargeScreenMusicEffect.values) {
          expect(
              find.descendant(
                  of: card(effect), matching: find.byType(SvgPicture)),
              findsOneWidget);
        }
        final selected = find.descendant(
            of: card(LargeScreenMusicEffect.aurora),
            matching: find.byWidgetPredicate(
                (w) => w is Semantics && w.properties.label == '极光流场'));
        expect(tester.widget<Semantics>(selected).properties.selected, isTrue);
        final fluid = card(LargeScreenMusicEffect.fluid);
        await tester.ensureVisible(fluid);
        await tester.tap(fluid);
        await tester.pumpAndSettle();
        expect(container.read(largeScreenSettingsProvider).musicEffect,
            LargeScreenMusicEffect.fluid);
        final tide = find.widgetWithText(ChoiceChip, '潮汐');
        await tester.ensureVisible(tide);
        await tester.tap(tide);
        await tester.pumpAndSettle();
        expect(container.read(largeScreenSettingsProvider).fluidMotion,
            LargeScreenFluidMotion.tide);
        expect(tester.widget<ChoiceChip>(tide).selected, isTrue);
        final off = card(LargeScreenMusicEffect.off);
        await tester.ensureVisible(off);
        await tester.tap(off);
        await tester.pumpAndSettle();
        expect(find.text('动效强度'), findsNothing);
        expect(find.text('流体运动'), findsNothing);
        final prism = card(LargeScreenMusicEffect.prism);
        await tester.ensureVisible(prism);
        await tester.tap(prism);
        await tester.pumpAndSettle();
        final intensity = find.byWidgetPredicate((widget) =>
            widget is ThmrSlider && widget.semanticsLabel == '动效强度');
        await tester.ensureVisible(intensity);
        final slider = tester.getRect(intensity);
        await tester.tapAt(Offset(slider.right - 8, slider.center.dy));
        await tester.pumpAndSettle();
        final powerSaving = find.descendant(
            of: find.byWidgetPredicate((widget) =>
                widget is Semantics && widget.properties.label == '动效省电模式'),
            matching: find.byType(Switch));
        await tester.ensureVisible(powerSaving);
        await tester.tap(powerSaving);
        await tester.pumpAndSettle();
        final effect = container.read(largeScreenSettingsProvider);
        expect(effect.musicEffect, LargeScreenMusicEffect.prism);
        expect(effect.musicEffectIntensity, 1);
        expect(effect.musicEffectLowPower, isTrue);
        final keepAwake = find.descendant(
            of: find.byWidgetPredicate((widget) =>
                widget is Semantics && widget.properties.label == '保持屏幕常亮'),
            matching: find.byType(Switch));
        await tester.ensureVisible(keepAwake);
        await tester.tap(keepAwake);
        await tester.pumpAndSettle();
        expect(
            container.read(largeScreenSettingsProvider).keepScreenOn, isTrue);
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
    await tester.tap(find.text('大屏幕模式Beta 配置'));
    await tester.pumpAndSettle();
    expect(find.byType(LargeScreenSettingsPanel), findsOneWidget);
    expect(find.text('布局'), findsOneWidget);
    expect(find.text('大屏主题'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
