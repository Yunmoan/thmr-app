import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:thmr_app/core/platform/desktop_tray.dart';
import 'package:thmr_app/core/platform/desktop_window.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('tray_manager');
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];
  late DesktopTrayController tray;
  var shows = 0, exits = 0;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    calls.clear();
    shows = exits = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    tray = DesktopTrayController(
      showWindow: () async => shows++,
      exitApplication: () => exits++,
    );
  });
  tearDown(() async {
    await tray.dispose();
    debugDefaultTargetPlatformOverride = null;
    messenger.setMockMethodCallHandler(channel, null);
  });

  Future<void> event(String name, [Object? args]) async {
    final handled = Completer<void>();
    await messenger.handlePlatformMessage(
      channel.name,
      codec.encodeMethodCall(MethodCall(name, args)),
      (_) => handled.complete(),
    );
    await handled.future;
  }

  List<Map> menuItems() => List<Map>.from(calls
      .singleWhere((call) => call.method == 'setContextMenu')
      .arguments['menu']['items'] as List);

  test('macOS installs the bundled icon and working native menu actions',
      () async {
    expect(hasDesktopWindowControls, isTrue);
    expect(await tray.start(), isTrue);
    expect(tray.ready, isTrue);
    final icon = calls.singleWhere((call) => call.method == 'setIcon');
    final expected = await rootBundle.load('assets/icons/icon-512.png');
    expect(base64Decode(icon.arguments['base64Icon'] as String),
        expected.buffer.asUint8List());
    expect(icon.arguments['iconSize'], 18);
    expect(icon.arguments['iconPath'], contains('assets/icons/icon-512.png'));
    expect(calls.map((call) => call.method),
        ['setIcon', 'setToolTip', 'setContextMenu']);
    expect(menuItems().map((item) => item['label']), ['显示主窗口', '', '退出']);
    await event('onTrayIconMouseDown');
    await event('onTrayIconRightMouseDown');
    expect(
        calls.where((call) => call.method == 'popUpContextMenu'), hasLength(2));
    expect(shows, 0);
    await event('onTrayMenuItemClick', {
      'id':
          menuItems().singleWhere((item) => item['key'] == 'show-window')['id'],
    });
    await event('onTrayMenuItemClick', {
      'id': menuItems().singleWhere((item) => item['key'] == 'exit')['id'],
    });
    expect(shows, 1);
    expect(exits, 1);
    expect(desktopTrayActionLabel(available: true), '隐藏到菜单栏');
    expect(desktopTrayActionLabel(available: false), '最小化到 Dock');
  });

  test('failed native icon setup leaves the tray unavailable and removes it',
      () async {
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'setIcon') {
        throw PlatformException(code: 'no_status_bar');
      }
      return null;
    });
    expect(await tray.start(), isFalse);
    expect(tray.ready, isFalse);
    expect(calls.map((call) => call.method), ['setIcon', 'destroy']);
    expect(trayManager.hasListeners, isFalse);
  });

  test('quitting during startup waits for the late icon then removes it once',
      () async {
    final requested = Completer<void>();
    final iconReady = Completer<void>();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'setIcon') {
        requested.complete();
        await iconReady.future;
      }
      return null;
    });
    final starting = tray.start();
    await requested.future;
    final disposing = DesktopTrayController.disposeActive();
    expect(tray.isDisposed, isTrue);
    expect(trayManager.hasListeners, isFalse);
    expect(calls.map((call) => call.method), ['setIcon']);
    iconReady.complete();
    expect(await starting, isFalse);
    await disposing;
    await tray.dispose();
    expect(calls.map((call) => call.method), ['setIcon', 'destroy']);
    expect(tray.ready, isFalse);
    expect(await tray.start(), isFalse);
    tray.onTrayIconMouseDown();
    tray.onTrayIconRightMouseDown();
    expect(calls, hasLength(2));
  });

  test('Windows keeps file-based icons, click-to-restore and temp file cleanup',
      () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tray = DesktopTrayController(
      showWindow: () async => shows++,
      exitApplication: () => exits++,
    );
    expect(await tray.start(), isTrue);
    final args =
        calls.singleWhere((call) => call.method == 'setIcon').arguments;
    expect(args.containsKey('base64Icon'), isFalse);
    final file = File(args['iconPath'] as String);
    expect(await file.exists(), isTrue);
    await event('onTrayIconMouseDown');
    expect(shows, 1);
    expect(calls.where((call) => call.method == 'popUpContextMenu'), isEmpty);
    await tray.dispose();
    expect(await file.exists(), isFalse);
  });
}
