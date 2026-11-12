import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:thmr_app/core/api/radio_api.dart';
import 'package:thmr_app/core/platform/desktop_tray.dart';
import 'package:thmr_app/core/platform/linux_tray.dart';
import 'package:thmr_app/core/player/playback_controller.dart';
import 'package:thmr_app/core/state/channel_provider.dart';
import 'package:thmr_app/core/state/radio_source_provider.dart';
import 'package:thmr_app/core/state/settings_provider.dart';
import 'package:thmr_app/core/state/station_provider.dart';
import 'package:thmr_app/core/theme/thmr_colors.dart';
import 'package:thmr_app/features/shell/home_shell.dart';

class _Station extends StateNotifier<StationUiState> implements StationPoller {
  _Station() : super(const StationUiState(initialLoading: false));

  @override
  Future<void> refresh() async {}
}

class _Playback extends StateNotifier<PlaybackState>
    implements PlaybackController {
  _Playback() : super(const PlaybackState(phase: PlaybackPhase.online));
  int stops = 0;

  @override
  Future<void> stop() async => stops++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _RadioApi extends RadioApi {
  @override
  Future<int> siteListeners() async => 12;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const window = MethodChannel('window_manager');
  const tray = MethodChannel('tray_manager');
  const codec = StandardMethodCodec();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final windowCalls = <MethodCall>[];
  final trayCalls = <MethodCall>[];

  Future<void> nativeEvent(MethodChannel channel, String method,
      [Object? arguments]) async {
    final done = Completer<void>();
    await messenger.handlePlatformMessage(
        channel.name,
        codec.encodeMethodCall(MethodCall(method, arguments)),
        (_) => done.complete());
    await done.future;
  }

  Future<_Playback> mount(WidgetTester tester,
      {bool trayWorks = true,
      CloseAction closeAction = CloseAction.tray}) async {
    final initialized = Completer<void>();
    SharedPreferences.setMockInitialValues({'closeAction': closeAction.name});
    windowCalls.clear();
    trayCalls.clear();
    messenger.setMockMethodCallHandler(window, (call) async {
      windowCalls.add(call);
      if (call.method == 'isMinimized') return true;
      return null;
    });
    messenger.setMockMethodCallHandler(tray, (call) async {
      trayCalls.add(call);
      if (call.method == 'setIcon' && !trayWorks) {
        throw PlatformException(code: 'unavailable');
      }
      if (call.method == (trayWorks ? 'setContextMenu' : 'destroy')) {
        if (!initialized.isCompleted) initialized.complete();
      }
      return null;
    });
    final playback = _Playback();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        stationProvider.overrideWith((ref) => _Station()),
        playbackProvider.overrideWith((ref) => playback),
        radioSourceProvider.overrideWith((ref) =>
            RadioSourceController(preference: RadioSourcePreference.source1)),
        radioApiProvider.overrideWithValue(_RadioApi()),
        channelCatalogProvider.overrideWith((ref) async => []),
        desktopTrayAvailableProvider.overrideWith((ref) => false),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: [ThmrTokens.reimuLight]),
        home: const HomeShell(),
      ),
    ));
    await tester.runAsync(() => initialized.future);
    await tester.pumpAndSettle();
    return playback;
  }

  tearDown(() async {
    await DesktopTrayController.disposeActive();
    messenger.setMockMethodCallHandler(window, null);
    messenger.setMockMethodCallHandler(tray, null);
  });

  testWidgets('close hides the window, keeps playback and menu restores it',
      (tester) async {
    final playback = await mount(tester);
    await nativeEvent(window, 'onEvent', {'eventName': 'close'});
    await tester.pumpAndSettle();
    expect(windowCalls.where((call) => call.method == 'hide'), hasLength(1));
    expect(windowCalls.where((call) => call.method == 'minimize'), isEmpty);
    expect(playback.state.phase, PlaybackPhase.online);
    expect(playback.stops, 0);
    final items = trayCalls
        .singleWhere((call) => call.method == 'setContextMenu')
        .arguments['menu']['items'] as List;
    await nativeEvent(tray, 'onTrayMenuItemClick', {
      'id': items.singleWhere((item) => item['key'] == 'show-window')['id'],
    });
    await tester.pumpAndSettle();
    expect(
        windowCalls.map((call) => call.method),
        containsAllInOrder(
            ['hide', 'isMinimized', 'restore', 'show', 'focus']));
    expect(playback.stops, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('failed tray setup minimizes to Dock and remains recoverable',
      (tester) async {
    final playback = await mount(tester, trayWorks: false);
    await nativeEvent(window, 'onEvent', {'eventName': 'close'});
    await tester.pumpAndSettle();
    expect(windowCalls.where((call) => call.method == 'hide'), isEmpty);
    expect(windowCalls.map((call) => call.method),
        containsAllInOrder(['restore', 'show', 'focus', 'minimize']));
    expect(playback.stops, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('close preference asks and cancel keeps the window visible',
      (tester) async {
    await mount(tester, closeAction: CloseAction.ask);
    await nativeEvent(window, 'onEvent', {'eventName': 'close'});
    await tester.pumpAndSettle();
    expect(find.text('隐藏到菜单栏'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(windowCalls.where((call) => call.method == 'hide'), isEmpty);
    expect(windowCalls.where((call) => call.method == 'minimize'), isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
