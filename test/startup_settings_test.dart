import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thmr_app/app.dart';
import 'package:thmr_app/core/state/settings_provider.dart';
import 'package:thmr_app/core/theme/thmr_colors.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the first app build uses the saved theme and accent',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'themeMode': ThemeMode.dark.index,
      'accentTheme': AccentTheme.cirno.index,
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester
        .runAsync(() => container.read(settingsProvider.notifier).ready);

    final rendered = <AppSettings>[];
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: Consumer(builder: (context, ref, child) {
        rendered.add(ref.watch(settingsProvider));
        return const SizedBox.shrink();
      }),
    ));
    await tester.pump();

    expect(rendered, isNotEmpty);
    expect(rendered.map((s) => s.themeMode), everyElement(ThemeMode.dark));
    expect(rendered.map((s) => s.accentTheme), everyElement(AccentTheme.cirno));
  });

  test('startup readiness preserves defaults on a fresh install', () async {
    SharedPreferences.setMockInitialValues({});
    final controller = SettingsController();
    addTearDown(controller.dispose);
    await controller.ready;
    expect(controller.state.themeMode, ThemeMode.system);
    expect(controller.state.accentTheme, AccentTheme.reimu);
  });

  test('appearance is applied atomically after its illustration is prepared',
      () async {
    SharedPreferences.setMockInitialValues({});
    final controller = SettingsController();
    await controller.ready;
    addTearDown(controller.dispose);
    final updates = <AppSettings>[];
    final remove = controller.addListener(updates.add, fireImmediately: false);
    addTearDown(remove);
    await controller.setAppearance(ThemeMode.dark, AccentTheme.marisa);
    expect(updates, hasLength(1));
    expect(updates.single.themeMode, ThemeMode.dark);
    expect(updates.single.accentTheme, AccentTheme.marisa);
    final restored = SettingsController();
    addTearDown(restored.dispose);
    await restored.ready;
    expect(restored.state.themeMode, ThemeMode.dark);
    expect(restored.state.accentTheme, AccentTheme.marisa);
  });

  test('a user change wins over an in-flight settings load', () async {
    SharedPreferences.setMockInitialValues({
      'themeMode': ThemeMode.dark.index,
    });
    final controller = SettingsController();
    addTearDown(controller.dispose);
    final change = controller.setThemeMode(ThemeMode.light);
    await controller.ready;
    await change;
    expect(controller.state.themeMode, ThemeMode.light);
  });

  test('unrelated preferences and theme mode reuse the resolved themes',
      () async {
    SharedPreferences.setMockInitialValues({});
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final settings = container.read(settingsProvider.notifier);
    await settings.ready;
    final original = container.read(appThemesProvider);
    await settings.setBitrate('touhou', '320k');
    await settings.setAutoPlay(true);
    await settings.setThemeMode(ThemeMode.dark);
    final unchanged = container.read(appThemesProvider);
    expect(unchanged.$1, same(original.$1));
    expect(unchanged.$2, same(original.$2));
    await settings.setAccentTheme(AccentTheme.cirno);
    final changed = container.read(appThemesProvider);
    expect(changed.$1, isNot(same(original.$1)));
    expect(
        changed.$1.colorScheme.primary,
        ThmrTokens.resolve(AccentTheme.cirno, Brightness.light)
            .accessible()
            .accent);
  });
}
