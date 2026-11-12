import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:thmr_app/core/platform/application_exit.dart';

void main() {
  testWidgets('AppKit exit waits for cleanup and shares concurrent requests',
      (tester) async {
    final released = Completer<void>();
    var cleanups = 0;
    var completed = false;
    final coordinator = ApplicationExitCoordinator(() async {
      cleanups++;
      await released.future;
    }, exitProcess: (_) => fail('Successful cleanup must use the normal exit'));
    final listener =
        AppLifecycleListener(onExitRequested: coordinator.requestExit);
    addTearDown(listener.dispose);

    final request = listener.didRequestAppExit();
    unawaited(request.then((_) => completed = true));
    final second = listener.didRequestAppExit();
    await tester.pump();
    expect(cleanups, 1);
    expect(completed, isFalse);
    released.complete();
    expect(await request, AppExitResponse.exit);
    expect(await second, AppExitResponse.exit);
    expect(await listener.didRequestAppExit(), AppExitResponse.exit);
    expect(cleanups, 1);
  });

  test('failed native cleanup exits without unloading live callbacks',
      () async {
    final exits = <int>[];
    final coordinator = ApplicationExitCoordinator(
      () async => throw StateError('native plugin failed'),
      exitProcess: exits.add,
    );
    expect(await coordinator.requestExit(), AppExitResponse.exit);
    expect(exits, [0]);
    await coordinator.requestExit();
    expect(exits, [0]);
  });

  testWidgets('a stuck plugin cannot hold the process open indefinitely',
      (tester) async {
    final exits = <int>[];
    final released = Completer<void>();
    final coordinator = ApplicationExitCoordinator(
      () => released.future,
      exitProcess: exits.add,
    );
    final request = coordinator.requestExit();
    await tester.pump(const Duration(seconds: 3));
    expect(await request, AppExitResponse.exit);
    expect(exits, [0]);
    released.complete();
  });
}
