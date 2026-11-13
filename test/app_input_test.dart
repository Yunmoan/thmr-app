import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:gamepads/gamepads.dart';
import 'package:thmr_app/core/input/app_commands.dart';
import 'package:thmr_app/core/input/app_input.dart';
import 'package:thmr_app/core/player/playback_controller.dart';
import 'package:thmr_app/core/state/station_provider.dart';
import 'package:thmr_app/shared/widgets/volume_slider.dart';
import 'gamepad_navigation_test.dart' show event;

class _Playback extends StateNotifier<PlaybackState>
    implements PlaybackController {
  _Playback() : super(const PlaybackState(volume: 70, lastAudibleVolume: 70));
  int toggles = 0;

  @override
  Future<void> toggle(String? url) async {
    toggles++;
  }

  @override
  Future<void> setVolume(double value) async {
    state = state.copyWith(volume: value);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Harness {
  final navigator = GlobalKey<NavigatorState>();
  final events = StreamController<NormalizedGamepadEvent>.broadcast(sync: true);
  final connections =
      StreamController<GamepadConnectionEvent>.broadcast(sync: true);
  final first = FocusNode();
  final second = FocusNode();
  final playback = _Playback();
  late final container = ProviderContainer(overrides: [
    gamepadEventsProvider.overrideWithValue(events.stream),
    gamepadConnectionsProvider.overrideWithValue(connections.stream),
    playbackProvider.overrideWith((ref) => playback),
    streamUrlProvider.overrideWithValue('https://radio.test/live'),
  ]);
  int activations = 0;
  double volume = 50;

  Future<void> mount(WidgetTester tester) async {
    await tester.pumpWidget(UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
            navigatorKey: navigator,
            builder: (_, child) =>
                AppInput(navigatorKey: navigator, child: child!),
            home: Scaffold(
                body: StatefulBuilder(
                    builder: (_, setState) => Column(children: [
                          TextButton(
                              focusNode: first,
                              onPressed: () => activations++,
                              child: const Text('first')),
                          TextButton(
                              focusNode: second,
                              onPressed: () => activations++,
                              child: const Text('second')),
                          SizedBox(
                              width: 200,
                              child: VolumeSlider(
                                  value: volume,
                                  onChanged: (v) =>
                                      setState(() => volume = v))),
                          TextField(
                              focusNode:
                                  container.read(librarySearchFocusProvider)),
                        ]))))));
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await events.close();
    await connections.close();
    first.dispose();
    second.dispose();
    container.dispose();
  }

  void press(GamepadButton button) {
    events.add(event(button: button));
    events.add(event(button: button, value: 0));
  }

  Future<void> shortcut(WidgetTester tester, LogicalKeyboardKey key,
      {bool meta = false, bool shift = false}) async {
    final modifier =
        meta ? LogicalKeyboardKey.metaLeft : LogicalKeyboardKey.controlLeft;
    await tester.sendKeyDownEvent(modifier);
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(key);
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(modifier);
    await tester.pumpAndSettle();
  }
}

void main() {
  for (final meta in [false, true]) {
    testWidgets('page and search shortcuts work with meta=$meta',
        (tester) async {
      final h = _Harness();
      await h.mount(tester);
      await h.shortcut(tester, LogicalKeyboardKey.digit3, meta: meta);
      expect(h.container.read(appTabProvider), 2);
      await h.shortcut(tester, LogicalKeyboardKey.keyF, meta: meta);
      expect(h.container.read(appTabProvider), 1);
      expect(h.container.read(librarySearchFocusProvider).hasFocus, isTrue);
      await tester.enterText(find.byType(TextField), 'Touhou music');
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(h.activations, 0);
      expect(h.playback.toggles, 0);
      await h.close(tester);
    },
        variant: TargetPlatformVariant.only(
            meta ? TargetPlatform.macOS : TargetPlatform.windows));
  }

  for (final mac in [false, true]) {
    testWidgets('media shortcuts preserve system minimize on mac=$mac',
        (tester) async {
      final h = _Harness();
      await h.mount(tester);
      await h.shortcut(tester, LogicalKeyboardKey.keyP, meta: mac);
      expect(h.playback.toggles, 1);
      if (mac) {
        await h.shortcut(tester, LogicalKeyboardKey.keyM, meta: true);
        expect(h.playback.state.volume, 70);
      }
      await h.shortcut(tester, LogicalKeyboardKey.keyM, meta: mac, shift: mac);
      expect(h.playback.state.volume, 0);
      await h.shortcut(tester, LogicalKeyboardKey.keyM, meta: mac, shift: mac);
      expect(h.playback.state.volume, 70);
      h.press(GamepadButton.x);
      h.press(GamepadButton.rightStick);
      await tester.pump();
      expect(h.playback.toggles, 2);
      expect(h.playback.state.volume, 0);
      await h.close(tester);
    },
        variant: TargetPlatformVariant.only(
            mac ? TargetPlatform.macOS : TargetPlatform.windows));
  }

  testWidgets('gamepad moves focus, activates and adjusts focused volume',
      (tester) async {
    final h = _Harness();
    await h.mount(tester);
    h.first.requestFocus();
    await tester.pump();
    h.press(GamepadButton.dpadDown);
    await tester.pumpAndSettle();
    expect(h.second.hasFocus, isTrue);
    h.press(GamepadButton.a);
    await tester.pump();
    expect(h.activations, 1);
    h.press(GamepadButton.dpadDown);
    await tester.pump();
    h.press(GamepadButton.dpadRight);
    await tester.pump();
    expect(h.volume, 55);
    h.press(GamepadButton.dpadDown);
    await tester.pump();
    expect(h.container.read(librarySearchFocusProvider).hasFocus, isTrue);
    await h.close(tester);
  });

  testWidgets('gamepad B dismisses a popup and tabs do not switch behind it',
      (tester) async {
    final h = _Harness();
    await h.mount(tester);
    unawaited(showDialog<void>(
        context: tester.element(find.text('first')),
        builder: (_) => const AlertDialog(
            title: Text('modal'), content: TextField(autofocus: true))));
    await tester.pumpAndSettle();
    h.press(GamepadButton.rightBumper);
    await h.shortcut(tester, LogicalKeyboardKey.digit3);
    expect(h.container.read(appTabProvider), 0);
    h.press(GamepadButton.b);
    await tester.pumpAndSettle();
    expect(find.text('modal'), findsNothing);
    expect(h.navigator.currentState!.canPop(), isFalse);
    await h.close(tester);
  });

  testWidgets('back respects a non-dismissible required dialog',
      (tester) async {
    final h = _Harness();
    await h.mount(tester);
    unawaited(showDialog<void>(
        context: tester.element(find.text('first')),
        barrierDismissible: false,
        builder: (context) => AlertDialog(
                title: const Text('required'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('done'))
                ])));
    await tester.pumpAndSettle();
    h.press(GamepadButton.b);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('required'), findsOneWidget);
    FocusManager.instance.rootScope.requestFocus();
    await tester.pump();
    h.press(GamepadButton.b);
    await tester.pumpAndSettle();
    expect(find.text('required'), findsOneWidget);
    await tester.tap(find.text('done'));
    await tester.pumpAndSettle();
    await h.close(tester);
  });

  testWidgets('background window ignores input and clears held navigation',
      (tester) async {
    final h = _Harness();
    await h.mount(tester);
    h.first.requestFocus();
    await tester.pump();
    h.events.add(event(button: GamepadButton.dpadDown));
    await tester.pump();
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    h.press(GamepadButton.a);
    h.press(GamepadButton.rightBumper);
    await tester.pump(const Duration(seconds: 1));
    expect(h.activations, 0);
    expect(h.container.read(appTabProvider), 0);
    expect(h.second.hasFocus, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    h.press(GamepadButton.a);
    await tester.pump();
    expect(h.activations, 1);
    await h.close(tester);
  });

  testWidgets('F1 opens accessible input help and Escape closes it',
      (tester) async {
    final h = _Harness();
    await h.mount(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.f1);
    await tester.pumpAndSettle();
    expect(find.text('键盘与手柄操作'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('键盘与手柄操作'), findsNothing);
    await h.close(tester);
  });

  testWidgets(
      'disposing gamepad input restores the previous focus highlight mode',
      (tester) async {
    FocusManager.instance.highlightStrategy = FocusHighlightStrategy.automatic;
    final h = _Harness();
    await h.mount(tester);
    h.press(GamepadButton.dpadDown);
    await tester.pump();
    expect(FocusManager.instance.highlightStrategy,
        FocusHighlightStrategy.alwaysTraditional);
    await h.close(tester);
    expect(FocusManager.instance.highlightStrategy,
        FocusHighlightStrategy.automatic);
  });
}
