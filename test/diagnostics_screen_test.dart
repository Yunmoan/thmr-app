import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thmr_app/core/network/network_probe.dart';
import 'package:thmr_app/core/state/diagnostics_provider.dart';
import 'package:thmr_app/core/state/radio_source_provider.dart';
import 'package:thmr_app/core/theme/thmr_theme.dart';
import 'package:thmr_app/features/account/radio_source_panel.dart';
import 'package:thmr_app/features/diagnostics/diagnostics_screen.dart';

class _FixtureDiagnostics extends DiagnosticsService {
  @override
  Future<Map<String, String>> environment(String clientVersion) async => {
        '客户端版本': clientVersion,
        '操作系统': 'Windows',
        '系统版本': 'Windows 11 · 24H2',
        '处理器逻辑核心': '16',
        '应用当前内存（RSS）': '186.5 MiB',
        '应用峰值内存（RSS）': '215.2 MiB',
        '系统总内存': '32.00 GiB',
        '系统可用内存': '18.40 GiB',
        '本机 IP / 网络接口': 'WLAN · 192.168.1.20\nEthernet · 2001:db8::20',
      };
  @override
  Future<IpLocation> publicIp() async =>
      const IpLocation('192.0.2.42', ['中国', '测试省', '测试市', '', '测试运营商']);
  @override
  Future<NetworkProbeResult> check(DiagnosticTarget target) async =>
      NetworkProbeResult(
        uri: Uri.parse(target.url),
        statusCode: target.id == 'account' ? 403 : 200,
        elapsed: const Duration(milliseconds: 76),
        remoteAddress: '203.0.113.86',
        remotePort: 443,
        dnsAddresses: const ['203.0.113.86', '2001:db8:1234:5678::aabb:ccdd'],
        headers: const {
          'server': 'nginx',
          'eo-cache-status': 'HIT',
          'eo-log-uuid': '10887446112223334445'
        },
      );
}

void main() {
  var previewFont = false;
  setUpAll(() async {
    final font = File('C:/Windows/Fonts/msyh.ttc');
    if (await font.exists()) {
      await (FontLoader('DiagnosticPreview')
            ..addFont(
                Future.value(ByteData.sublistView(await font.readAsBytes()))))
          .load();
      previewFont = true;
    }
    final icons = File(
        'D:/flutter-sdk/flutter/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
    if (await icons.exists()) {
      await (FontLoader('MaterialIcons')
            ..addFont(
                Future.value(ByteData.sublistView(await icons.readAsBytes()))))
          .load();
    }
  });
  ThemeData themeFor(bool dark) {
    final theme = dark ? ThmrTheme.dark() : ThmrTheme.light();
    return !previewFont
        ? theme
        : theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: 'DiagnosticPreview'),
            appBarTheme: theme.appBarTheme.copyWith(
                titleTextStyle: theme.appBarTheme.titleTextStyle
                    ?.copyWith(fontFamily: 'DiagnosticPreview')),
          );
  }

  setUp(() => SharedPreferences.setMockInitialValues({}));
  for (final dark in [false, true]) {
    for (final width in [320.0, 1280.0]) {
      testWidgets(
          'diagnostics displays and exports at ${width.toInt()}px, dark=$dark',
          (tester) async {
        tester.view.physicalSize = Size(width, 1000);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        String? exported;
        final container = ProviderContainer(overrides: [
          diagnosticsProvider.overrideWith((ref) => DiagnosticsController(
                version: () async => '0.1.5+3302',
                serviceFactory: _FixtureDiagnostics.new,
              )),
          diagnosticReportSaverProvider
              .overrideWithValue((text, filename) async {
            expect(filename, endsWith('.txt'));
            exported = text;
            return 'fixture.txt';
          }),
        ]);
        addTearDown(container.dispose);
        final boundary = GlobalKey();
        await tester.pumpWidget(UncontrolledProviderScope(
          container: container,
          child: RepaintBoundary(
              key: boundary,
              child: MaterialApp(
                theme: themeFor(dark),
                home: const DiagnosticsScreen(),
              )),
        ));
        await tester.pumpAndSettle();
        expect(find.text('网络诊断'), findsOneWidget);
        expect(find.text('7 / 7 个服务已连通'), findsOneWidget);
        expect(find.text('192.0.2.42'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('导出 TXT'));
        await tester.pumpAndSettle();
        expect(exported, contains('192.0.2.42'));
        expect(exported, contains('186.5 MiB'));
        expect(exported, contains('eo-log-uuid'));
        expect(exported, contains('访问受限'));
        expect(find.text('诊断报告已保存'), findsOneWidget);
        await tester.pump(const Duration(seconds: 5));
        await tester.pumpAndSettle();
        await tester.drag(find.byType(ListView), const Offset(0, -900));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        // Save reviewable layout previews without making network calls.
        if (width == 1280 && dark) {
          await tester.runAsync(() async {
            final render = boundary.currentContext!.findRenderObject()
                as RenderRepaintBoundary;
            final image = await render.toImage(pixelRatio: 1);
            final bytes =
                await image.toByteData(format: ui.ImageByteFormat.png);
            await Directory('build/diagnostics-preview')
                .create(recursive: true);
            await File('build/diagnostics-preview/services-dark.png')
                .writeAsBytes(bytes!.buffer.asUint8List());
            image.dispose();
          });
        }
        await tester.drag(find.byType(ListView), const Offset(0, 3000));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('重新诊断'));
        await tester.pumpAndSettle();
        expect(container.read(diagnosticsProvider).services, hasLength(7));
      });
    }
  }

  testWidgets('manual source choice is usable on a narrow settings panel',
      (tester) async {
    tester.view.physicalSize = const Size(320, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThmrTheme.dark(),
          home: const Scaffold(
              body: SingleChildScrollView(
            child:
                Padding(padding: EdgeInsets.all(12), child: RadioSourcePanel()),
          )),
        )));
    await tester.pumpAndSettle();
    await tester.tap(find.text('源 2'));
    await tester.pumpAndSettle();
    expect(container.read(radioSourceProvider).selected.id,
        RadioSourcePreference.source2);
    expect(find.text('当前使用：源 2 · radio.zyghit.cn'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('TXT bytes retain Chinese text and a Windows-friendly UTF-8 BOM', () {
    final bytes = diagnosticReportBytes('网络诊断 · 源 2');
    expect(bytes.take(3), [0xef, 0xbb, 0xbf]);
    expect(utf8.decode(bytes), '网络诊断 · 源 2');
  });
}
