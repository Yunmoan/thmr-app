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
      expect(find.text('下载并自动更新'), findsOneWidget);
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
    expect(find.text('发现客户端新版本 v0.1.10+2'), findsOneWidget);
    await tester.tap(find.text('忽略此版本'));
    await tester.pumpAndSettle();
    expect(find.byType(MaterialBanner), findsNothing);
    expect(find.text('电台页面'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('Linux login explains unsupported WebView without invoking it',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Linux 暂不支持内置登录'), findsOneWidget);
    expect(find.text('打开网页版'), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.linux));
}
