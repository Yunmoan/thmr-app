import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/player/linux_media_controls.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const codec = StandardMethodCodec();
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    messenger.setMockMethodCallHandler(LinuxMediaControls.channel,
        (call) async {
      calls.add(call);
      return null;
    });
  });
  tearDown(() =>
      messenger.setMockMethodCallHandler(LinuxMediaControls.channel, null));

  Future<void> command(String name, [double value = 0]) async {
    final done = Completer<void>();
    await messenger.handlePlatformMessage(
      LinuxMediaControls.channel.name,
      codec.encodeMethodCall(MethodCall('command', {
        'command': name,
        'value': value,
      })),
      (_) => done.complete(),
    );
    await done.future;
  }

  test(
      'pre-start metadata reaches the service and commands use player callbacks',
      () async {
    final actions = <String>[];
    final controls = LinuxMediaControls(
      play: () async => actions.add('play'),
      pause: () async => actions.add('pause'),
      stop: () async => actions.add('stop'),
      raise: () async => actions.add('raise'),
      setVolume: (value) async => actions.add('volume:$value'),
    );
    addTearDown(controls.dispose);
    await controls.update({'track': '42-123', 'title': 'Song'});
    expect(calls, isEmpty);
    await controls.start();
    expect(calls.last.arguments['track'], '42-123');
    for (final name in ['play', 'pause', 'stop', 'raise']) {
      await command(name);
    }
    await command('volume', 0.42);
    expect(actions, ['play', 'pause', 'stop', 'raise', 'volume:42.0']);
  });

  test('native initialization failure leaves metadata updates harmless',
      () async {
    messenger.setMockMethodCallHandler(LinuxMediaControls.channel,
        (_) async => throw PlatformException(code: 'no_bus'));
    final controls = LinuxMediaControls(
      play: () async {},
      pause: () async {},
      stop: () async {},
      raise: () async {},
      setVolume: (_) async {},
    );
    addTearDown(controls.dispose);
    await controls.start();
    await controls.update({'status': 'Playing'});
  });
}
