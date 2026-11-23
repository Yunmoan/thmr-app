import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thmr_app/core/state/settings_provider.dart';
import 'package:thmr_app/features/account/about_panel.dart';
import 'package:thmr_app/features/account/login_screen.dart';
import 'package:thmr_app/shared/widgets/developer_mode_strip.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('正式构建需连续点七次版本号并确认，关闭后再次隐藏开关', (tester) async {
    final container = ProviderContainer(overrides: [
      settingsProvider
          .overrideWith((ref) => SettingsController(debugBuild: false)),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(width: double.infinity, child: DeveloperModeStrip()),
              Expanded(
                child:
                    SingleChildScrollView(child: AboutPanel(version: '0.2.0')),
              ),
            ],
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final version = find.text('客户端 · v0.2.0');
    final confirmation = find.text('启用开发者模式？');
    final developerSwitch = find.widgetWithText(SwitchListTile, '开发者模式');
    final stripe = find.byWidgetPredicate(
      (widget) => widget is Semantics && widget.properties.label == '开发者模式已启用',
    );
    final prefs = await SharedPreferences.getInstance();
    expect(developerSwitch, findsNothing);
    expect(stripe, findsNothing);

    Future<void> tapVersion(int times) async {
      for (var i = 0; i < times; i++) {
        await tester.tap(version);
      }
      await tester.pumpAndSettle();
    }

    await tapVersion(6);
    expect(confirmation, findsNothing);
    await tester.pump(const Duration(seconds: 3));
    await tapVersion(1);
    expect(confirmation, findsNothing);
    await tapVersion(6);
    expect(confirmation, findsOneWidget);
    expect(container.read(settingsProvider).developerMode, isFalse);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(developerSwitch, findsNothing);
    expect(prefs.getBool('developerMode'), isNull);

    await tapVersion(7);
    await tester.tap(find.text('启用'));
    await tester.pumpAndSettle();
    expect(tester.widget<SwitchListTile>(developerSwitch).value, isTrue);
    expect(stripe, findsOneWidget);
    expect(prefs.getBool('developerMode'), isTrue);

    final restarted = ProviderContainer(overrides: [
      settingsProvider
          .overrideWith((ref) => SettingsController(debugBuild: false)),
    ]);
    addTearDown(restarted.dispose);
    await restarted.read(settingsProvider.notifier).ready;
    expect(restarted.read(settingsProvider).developerMode, isTrue);

    await tester.ensureVisible(developerSwitch);
    await tester.pumpAndSettle();
    await tester.tap(developerSwitch);
    await tester.pumpAndSettle();
    expect(developerSwitch, findsNothing);
    expect(stripe, findsNothing);
    expect(prefs.getBool('developerMode'), isFalse);
  });

  test('调试构建默认启用，调试偏好与正式版分别保存', () async {
    final debug = ProviderContainer();
    addTearDown(debug.dispose);
    final controller = debug.read(settingsProvider.notifier);
    await controller.ready;
    expect(debug.read(settingsProvider).developerMode, isTrue);
    await controller.setDeveloperMode(false);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('developerMode.debug'), isFalse);
    expect(prefs.getBool('developerMode'), isNull);
  });

  testWidgets('Android 登录页无验证状态条，网页尺寸不随键盘改变', (tester) async {
    InAppWebViewPlatform.instance = _TestWebViewPlatform();
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pump();
    expect(find.textContaining('登录验证状态'), findsNothing);
    Rect bodyRect() => tester.getRect(find.byWidget(
          tester.widget<Scaffold>(find.byType(Scaffold)).body!,
        ));
    final before = bodyRect();
    addTearDown(tester.view.resetViewInsets);
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    await tester.pump();
    expect(bodyRect(), before);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));
}

class _TestWebViewPlatform extends InAppWebViewPlatform {
  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) =>
      _TestWebViewWidget(params);
}

class _TestWebViewWidget extends PlatformInAppWebViewWidget {
  _TestWebViewWidget(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      throw UnimplementedError();

  @override
  void dispose() {}
}
