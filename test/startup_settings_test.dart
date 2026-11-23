import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thmr_app/app.dart';
import 'package:thmr_app/core/state/settings_provider.dart';
import 'package:thmr_app/core/theme/thmr_colors.dart';
import 'package:thmr_app/core/theme/thmr_theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    // 测试检查主题身份。使用内置字体字节，确保延迟加载无需网络或磁盘缓存。
    final font = await rootBundle.load('fonts/MaterialIcons-Regular.otf');
    final assets = <String, Object>{
      for (final weight in [
        'Thin',
        'ExtraLight',
        'Light',
        'Regular',
        'Medium',
        'SemiBold',
        'Bold',
        'ExtraBold',
        'Black'
      ])
        'test-fonts/NotoSerifSC-$weight.ttf': [
          <String, Object>{'asset': 'test-fonts/NotoSerifSC-$weight.ttf'}
        ],
    };
    final manifest = const StandardMessageCodec().encodeMessage(assets);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async {
      final path = utf8.decode(message!.buffer
          .asUint8List(message.offsetInBytes, message.lengthInBytes));
      if (path == 'AssetManifest.bin') return manifest;
      if (path.startsWith('test-fonts/NotoSerifSC-')) return font;
      return null;
    });
  });
  tearDownAll(() async {
    await GoogleFonts.pendingFonts();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  for (final brightness in Brightness.values) {
    test('Reimu preserves its original palette in $brightness', () {
      final theme =
          brightness == Brightness.dark ? ThmrTheme.dark() : ThmrTheme.light();
      const accent = Color(0xFFC65A69);
      const onAccent = Color(0xFFFFF8FA);
      expect(theme.colorScheme.primary, accent);
      expect(theme.colorScheme.onPrimary, onAccent);
      expect(
          theme.filledButtonTheme.style?.backgroundColor?.resolve({}), accent);
      expect(theme.filledButtonTheme.style?.foregroundColor?.resolve({}),
          onAccent);
      expect(theme.textButtonTheme.style?.foregroundColor?.resolve({}), accent);
    });
  }

  for (final (name, preferences, mode, accent) in [
    ('fresh install', <String, Object>{}, ThemeMode.system, AccentTheme.reimu),
    (
      'existing preferences',
      {'themeMode': 2, 'accentTheme': 2},
      ThemeMode.dark,
      AccentTheme.cirno,
    ),
  ]) {
    test('startup loads the appearance for $name', () async {
      SharedPreferences.setMockInitialValues(preferences);
      final controller = SettingsController();
      addTearDown(controller.dispose);
      await controller.ready;
      expect(controller.state.themeMode, mode);
      expect(controller.state.accentTheme, accent);
    });
  }

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
    expect(
        changed.$1.colorScheme.primary,
        ThmrTokens.resolve(AccentTheme.cirno, Brightness.light)
            .accessible()
            .accent);
  });
}
