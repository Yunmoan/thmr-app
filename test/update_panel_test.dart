import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thmr_app/core/theme/thmr_theme.dart';
import 'package:thmr_app/core/update/app_update.dart';
import 'package:thmr_app/features/account/login_screen.dart';
import 'package:thmr_app/features/account/update_panel.dart';

import 'app_update_test.dart' show ReleaseAdapter, serviceFor;

class _UiUpdateService extends AppUpdateService {
  _UiUpdateService(this.release, this.adapter);
  final AppRelease release;
  final ReleaseAdapter adapter;
  @override
  Future<AppRelease?> latestRelease() async {
    adapter.requests++;
    return release;
  }
}

class _PreviewController extends AppUpdateController {
  _PreviewController(this.preview)
      : super(
            service: AppUpdateService(),
            installedVersion: () async => const ClientVersion('0.1.3', '1'));
  final AppUpdateState preview;
  @override
  Future<void> check({bool manual = false}) async {
    await ready;
    state = preview;
  }
}

void main() {
  late AppRelease uiRelease;
  setUpAll(() async {
    uiRelease = (await serviceFor(ReleaseAdapter()).latestRelease())!;
  });
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  for (final dark in [false, true]) {
    testWidgets('manual check and release dialog fit 320px (dark=$dark)',
        (tester) async {
      tester.view.physicalSize = const Size(320, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final adapter = ReleaseAdapter();
      final container = ProviderContainer(overrides: [
        appUpdateProvider.overrideWith((ref) => AppUpdateController(
              service: _UiUpdateService(uiRelease, adapter),
              installedVersion: () async => const ClientVersion('0.1.3', '1'),
            )),
      ]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: dark ? ThmrTheme.dark() : ThmrTheme.light(),
          home: const Scaffold(
              body: Padding(padding: EdgeInsets.all(12), child: UpdatePanel())),
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('检查更新'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('下载更新'), findsOneWidget);
      expect(find.text('更新说明'), findsOneWidget);
      expect(adapter.requests, 1);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('稍后'));
      await tester.pumpAndSettle();
      expect(find.text('发现新版本 v0.1.10+2'), findsOneWidget);
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }

  testWidgets('startup notice can be ignored without removing the child',
      (tester) async {
    final container = ProviderContainer(overrides: [
      appUpdateProvider.overrideWith((ref) => AppUpdateController(
            service: _UiUpdateService(uiRelease, ReleaseAdapter()),
            installedVersion: () async => const ClientVersion('0.1.3', '1'),
          )),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
          home: Scaffold(
        body: AppUpdateMonitor(child: Center(child: Text('电台页面'))),
      )),
    ));
    await tester.pumpAndSettle();
    expect(find.text('发现新版本 · v0.1.10'), findsOneWidget);
    await tester.tap(find.byTooltip('忽略此版本'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-update-notice')), findsNothing);
    expect(find.text('电台页面'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  for (final width in [320.0, 1280.0]) {
    testWidgets(
        'ready notice stays compact and error dialog fits at ${width}px',
        (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = _PreviewController(AppUpdateState(
          status: UpdateStatus.ready,
          release: uiRelease,
          error: '已取消管理员授权，应用保持原版本。'));
      final container = ProviderContainer(
          overrides: [appUpdateProvider.overrideWith((ref) => controller)]);
      addTearDown(container.dispose);
      await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
              theme: ThmrTheme.dark(),
              builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                      textScaler: TextScaler.linear(width < 480 ? 1.4 : 1)),
                  child: child!),
              home: const Scaffold(
                  body:
                      AppUpdateMonitor(child: Center(child: Text('电台页面')))))));
      await tester.pumpAndSettle();
      final notice = find.byKey(const ValueKey('app-update-notice'));
      expect(tester.getSize(notice).height,
          lessThanOrEqualTo(width < 480 ? 120 : 60));
      await tester.tap(find.text('查看更新'));
      await tester.pumpAndSettle();
      expect(find.text('更新未完成'), findsOneWidget);
      expect(find.text('构建 2'), findsOneWidget);
      expect(find.text('更新内容'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }

  testWidgets('Linux login explains unsupported WebView without invoking it',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Linux 暂不支持内置登录'), findsOneWidget);
    expect(find.text('打开网页版'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
