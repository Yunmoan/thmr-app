import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/platform/desktop_window.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('window_manager');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'isMinimized') return true;
      return null;
    });
  });
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('Linux initialization preserves GTK decorations and geometry', () async {
    await initializeDesktopWindow(platform: TargetPlatform.linux);
    expect(calls.map((call) => call.method), ['ensureInitialized']);
  });

  test('restoring a minimized window makes it visible before focusing',
      () async {
    await restoreDesktopWindow();
    expect(calls.map((call) => call.method),
        ['isMinimized', 'restore', 'show', 'focus']);
  });

  test('Linux releases resources before requesting GTK application exit',
      () async {
    final events = <String>[];
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      events.add(call.method);
      return null;
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await quitDesktopApplication(() async {
      await Future<void>.delayed(Duration.zero);
      events.add('cleanup');
    }, platform: TargetPlatform.linux);

    expect(events, ['cleanup', 'SystemNavigator.pop']);
    expect(calls, isEmpty);
  });

  test('Linux still requests exit when resource cleanup fails', () async {
    final exits = <String>[];
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      exits.add(call.method);
      return null;
    });
    addTearDown(() =>
        messenger.setMockMethodCallHandler(SystemChannels.platform, null));

    await quitDesktopApplication(() async {
      throw StateError('media cleanup failed');
    }, platform: TargetPlatform.linux);

    expect(exits, ['SystemNavigator.pop']);
    expect(calls, isEmpty);
  });
}
