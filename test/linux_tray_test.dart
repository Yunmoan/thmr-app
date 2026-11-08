import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/platform/linux_tray.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(
      () => messenger.setMockMethodCallHandler(LinuxTrayMonitor.channel, null));

  test('host appearance, loss and recovery update tray availability', () async {
    var host = false;
    messenger.setMockMethodCallHandler(
        LinuxTrayMonitor.channel, (_) async => host);
    final monitor = LinuxTrayMonitor();
    addTearDown(monitor.dispose);
    final changes = <bool>[];
    monitor.addListener(() => changes.add(monitor.value));
    await monitor.refresh();
    expect(monitor.value, isFalse);
    host = true;
    await monitor.refresh();
    host = false;
    await monitor.refresh();
    host = true;
    await monitor.refresh();
    expect(changes, [true, false, true]);
  });

  test('a failed D-Bus probe cannot leave a usable-tray state', () async {
    messenger.setMockMethodCallHandler(
        LinuxTrayMonitor.channel, (_) async => true);
    final monitor = LinuxTrayMonitor();
    addTearDown(monitor.dispose);
    await monitor.refresh();
    messenger.setMockMethodCallHandler(LinuxTrayMonitor.channel,
        (_) async => throw PlatformException(code: 'bus_disconnected'));
    await monitor.refresh();
    expect(monitor.value, isFalse);
  });

  test('disposing during an in-flight probe ignores its late reply', () async {
    final reply = Completer<bool>();
    messenger.setMockMethodCallHandler(
        LinuxTrayMonitor.channel, (_) => reply.future);
    final monitor = LinuxTrayMonitor();
    final probe = monitor.refresh();
    await Future<void>.delayed(Duration.zero);
    monitor.dispose();
    reply.complete(true);
    await probe;
    expect(monitor.value, isFalse);
  });
}
