import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/player/macos_media_controls.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = StandardMethodCodec();
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(MacosMediaControls.channel,
        (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() =>
      messenger.setMockMethodCallHandler(MacosMediaControls.channel, null));

  Future<void> command(String name) async {
    final done = Completer<void>();
    await messenger.handlePlatformMessage(
      MacosMediaControls.channel.name,
      codec.encodeMethodCall(MethodCall('command', {
        'command': name,
      })),
      (_) => done.complete(),
    );
    await done.future;
  }

  test(
      'pre-start metadata reaches the service and commands use player callbacks',
      () async {
    final actions = <String>[];
    final controls = MacosMediaControls(
      play: () async => actions.add('play'),
      pause: () async => actions.add('pause'),
      stop: () async => actions.add('stop'),
    );
    addTearDown(controls.dispose);
    await controls.update({'track': '42-123', 'title': 'Song'});
    expect(calls, isEmpty);
    await controls.start();
    expect(calls.last.arguments['track'], '42-123');
    for (final name in ['play', 'pause', 'stop']) {
      await command(name);
    }
    expect(actions, ['play', 'pause', 'stop']);
  });

  test('native initialization failure leaves metadata updates harmless',
      () async {
    messenger.setMockMethodCallHandler(MacosMediaControls.channel,
        (_) async => throw PlatformException(code: 'no_bus'));
    final controls = MacosMediaControls(
      play: () async {},
      pause: () async {},
      stop: () async {},
    );
    addTearDown(controls.dispose);
    await controls.start();
    await controls.update({'status': 'Playing'});
  });

  test('late startup cannot reactivate media controls during shutdown',
      () async {
    final started = Completer<void>();
    messenger.setMockMethodCallHandler(MacosMediaControls.channel,
        (call) async {
      calls.add(call);
      if (call.method == 'start') await started.future;
      return null;
    });
    final controls = MacosMediaControls(
      play: () async {},
      pause: () async {},
      stop: () async {},
    );
    final starting = controls.start();
    await Future<void>.delayed(Duration.zero);
    await controls.dispose();
    started.complete();
    await starting;
    await controls.update({'status': 'Playing'});
    await controls.start();
    expect(calls.map((call) => call.method), ['start', 'stop']);
  });
}
