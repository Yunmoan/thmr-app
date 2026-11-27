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

/// 直接打开更新弹窗，避免依赖面板的检查流程。
Future<void> _pumpUpdateDialog(
  WidgetTester tester,
  AppUpdateState state, {
  double width = 620,
  double textScale = 1,
}) async {
  tester.view.physicalSize = Size(width, 940);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final controller = _PreviewController(state);
  final container = ProviderContainer(overrides: [
    appUpdateProvider.overrideWith((ref) => controller),
  ]);
  addTearDown(container.dispose);
  await controller.check();
  // 先移除上一个弹窗，避免同一个 MaterialApp 里残留的路由挡住按钮。
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: ThmrTheme.light(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: TextButton(
              onPressed: () => showAppUpdate(context, state.release!),
              child: const Text('打开更新'),
            ),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('打开更新'));
  await tester.pump();
  // 不定态进度条持续动画，不能用 pumpAndSettle。
  await tester.pump(const Duration(milliseconds: 400));
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
      // 更新说明按简单 Markdown 渲染，标题、列表和行内格式不显示原始标记。
      expect(find.text('更新说明'), findsOneWidget);
      expect(find.text('修复 下载进度 显示'), findsOneWidget);
      expect(find.text('优化 重试 逻辑'), findsOneWidget);
      expect(find.textContaining('**'), findsNothing);
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
    final contentRect = tester.getRect(find.text('电台页面'));
    await tester.tap(find.byTooltip('忽略此版本'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-update-notice')), findsNothing);
    expect(find.text('电台页面'), findsOneWidget);
    expect(tester.getRect(find.text('电台页面')), contentRect);
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
      expect(find.text('更新说明'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
  }

  testWidgets('downloading shows a full-bleed band with a tail label',
      (tester) async {
    await _pumpUpdateDialog(
        tester,
        AppUpdateState(
            status: UpdateStatus.downloading,
            release: uiRelease,
            progress: .7));
    expect(find.text('70%'), findsOneWidget);
    final bandFinder = find.byKey(const ValueKey('update-progress'));
    final band = tester.getRect(bandFinder);
    // 进度带铺满弹窗表面，直到两侧圆角处的 Material 边缘。
    final surface = tester.getRect(
        find.ancestor(of: bandFinder, matching: find.byType(Material)).first);
    expect(band.left, closeTo(surface.left, .5));
    expect(band.right, closeTo(surface.right, .5));
    final fill =
        tester.getRect(find.byKey(const ValueKey('update-progress-fill')));
    final labelFinder = find.byKey(const ValueKey('update-progress-label'));
    final label = tester.getRect(labelFinder);
    final backdrop =
        tester.getRect(find.byKey(const ValueKey('update-progress-backdrop')));
    expect(fill.width, closeTo(band.width * .7, 1));
    // 横带只有细线高度；百分比文字没有胶囊，用同色背景挡住重叠内容。
    expect(band.height, 3);
    expect(fill.height, 3);
    expect(tester.widget(labelFinder), isA<Text>());
    expect(backdrop.left, lessThan(label.left));
    expect(backdrop.right, greaterThan(label.right));
    expect(backdrop.top, lessThan(label.top));
    expect(backdrop.bottom, greaterThan(label.bottom));
    expect(label.height, greaterThan(fill.height));
    expect(label.top, lessThan(band.top));
    expect(label.bottom, greaterThan(band.bottom));
    // 文字尾部保留 8px 填充和 4px 挖空间隔。
    expect(label.right, closeTo(fill.right - 12, 1));
    expect(label.right, lessThan(band.right));
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('missing package offers a re-download action', (tester) async {
    await _pumpUpdateDialog(
        tester,
        AppUpdateState(
            status: UpdateStatus.available,
            release: uiRelease,
            error: '安装包已被删除，请重新下载'));
    expect(find.text('更新未完成'), findsOneWidget);
    expect(find.text('安装包已被删除，请重新下载'), findsOneWidget);
    expect(find.text('重新下载'), findsOneWidget);
    expect(find.text('下载更新'), findsNothing);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('zero progress still shows the label at the band start',
      (tester) async {
    await _pumpUpdateDialog(
        tester,
        AppUpdateState(
            status: UpdateStatus.downloading, release: uiRelease, progress: 0));
    final band = tester.getRect(find.byKey(const ValueKey('update-progress')));
    final label =
        tester.getRect(find.byKey(const ValueKey('update-progress-label')));
    expect(find.text('0%'), findsOneWidget);
    expect(label.left, closeTo(band.left + 8, 1));
    expect(label.right, greaterThan(band.left + 8));
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('verifying and installing use an indeterminate band',
      (tester) async {
    await _pumpUpdateDialog(
        tester,
        AppUpdateState(
            status: UpdateStatus.downloading, release: uiRelease, progress: 1));
    expect(find.text('正在校验更新包…'), findsOneWidget);
    expect(find.byKey(const ValueKey('update-progress')), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);

    await _pumpUpdateDialog(tester,
        AppUpdateState(status: UpdateStatus.installing, release: uiRelease));
    expect(find.text('正在准备安装…'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('progress band fits 320px with large text', (tester) async {
    await _pumpUpdateDialog(
        tester,
        AppUpdateState(
            status: UpdateStatus.downloading, release: uiRelease, progress: .7),
        width: 320,
        textScale: 1.4);
    final bandFinder = find.byKey(const ValueKey('update-progress'));
    final band = tester.getRect(bandFinder);
    final surface = tester.getRect(
        find.ancestor(of: bandFinder, matching: find.byType(Material)).first);
    expect(band.width, closeTo(surface.width, .5));
    expect(find.text('70%'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // 不确定态的长状态文字也要能放进窄屏。
    await _pumpUpdateDialog(
        tester,
        AppUpdateState(
            status: UpdateStatus.downloading, release: uiRelease, progress: 1),
        width: 320,
        textScale: 1.4);
    expect(find.text('正在校验更新包…'), findsOneWidget);
    expect(tester.takeException(), isNull);
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
