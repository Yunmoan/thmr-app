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

  test('Linux releases resources before terminating without GTK teardown',
      () async {
    final events = <String>[];
    await quitDesktopApplication(
        () async {
          await Future<void>.delayed(Duration.zero);
          events.add('cleanup');
        },
        platform: TargetPlatform.linux,
        exitProcess: (code) {
          events.add('exit $code');
        });

    expect(events, ['cleanup', 'exit 0']);
    expect(calls, isEmpty);
  });

  test('Linux still terminates when resource cleanup fails', () async {
    final exits = <int>[];
    await quitDesktopApplication(() async {
      throw StateError('media cleanup failed');
    }, platform: TargetPlatform.linux, exitProcess: exits.add);

    expect(exits, [0]);
    expect(calls, isEmpty);
  });
}
