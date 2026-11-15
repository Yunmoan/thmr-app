import 'package:flutter_test/flutter_test.dart';
import 'package:gamepads/gamepads.dart';
import 'package:thmr_app/core/input/app_commands.dart';
import 'package:thmr_app/core/input/gamepad_navigation.dart';

NormalizedGamepadEvent event(
        {GamepadButton? button,
        GamepadAxis? axis,
        double value = 1,
        String id = 'one'}) =>
    NormalizedGamepadEvent(
      gamepadId: id,
      timestamp: 0,
      button: button,
      axis: axis,
      value: value,
      rawEvent: GamepadEvent(
          gamepadId: id,
          timestamp: 0,
          type: KeyType.button,
          key: 'test',
          value: value),
    );

void main() {
  testWidgets('button actions fire on edges and never repeat', (tester) async {
    final commands = <AppCommand>[];
    final input = GamepadNavigation(commands.add);
    input.handle(event(button: GamepadButton.a));
    input.handle(event(button: GamepadButton.a));
    await tester.pump(const Duration(seconds: 2));
    expect(commands, [AppCommand.activate]);
    input.handle(event(button: GamepadButton.a, value: 0));
    input.handle(event(button: GamepadButton.a));
    expect(commands, [AppCommand.activate, AppCommand.activate]);
    input.dispose();
  });

  testWidgets('stick deadzone and hysteresis avoid jitter navigation',
      (tester) async {
    final commands = <AppCommand>[];
    final input = GamepadNavigation(commands.add);
    input.handle(event(axis: GamepadAxis.leftStickY, value: 0.4));
    expect(commands, isEmpty);
    input.handle(event(axis: GamepadAxis.leftStickY, value: 0.8));
    input.handle(event(axis: GamepadAxis.leftStickY, value: 0.4));
    expect(commands, [AppCommand.up]);
    input.handle(event(axis: GamepadAxis.leftStickY, value: 0.2));
    input.handle(event(axis: GamepadAxis.leftStickY, value: -0.8));
    expect(commands, [AppCommand.up, AppCommand.down]);
    input.dispose();
  });

  testWidgets('held navigation repeats and stops on release', (tester) async {
    final commands = <AppCommand>[];
    final input = GamepadNavigation(commands.add);
    input.handle(event(button: GamepadButton.dpadDown));
    await tester.pump(const Duration(milliseconds: 399));
    expect(commands.length, 1);
    await tester.pump(const Duration(milliseconds: 111));
    expect(commands.length, 3);
    input.handle(event(button: GamepadButton.dpadDown, value: 0));
    await tester.pump(const Duration(seconds: 1));
    expect(commands.length, 3);
    input.dispose();
  });

  testWidgets('disconnect clears only that controller; reset stops all holds',
      (tester) async {
    final commands = <AppCommand>[];
    final input = GamepadNavigation(commands.add);
    input.handle(event(button: GamepadButton.dpadDown));
    input.handle(event(button: GamepadButton.dpadUp, id: 'two'));
    input.disconnect('two');
    await tester.pump(const Duration(milliseconds: 400));
    expect(commands, [AppCommand.down, AppCommand.up, AppCommand.down]);
    input.reset();
    await tester.pump(const Duration(seconds: 1));
    expect(commands.length, 3);
    input.dispose();
  });

  testWidgets('right stick scrolls; bumpers, media and help share commands',
      (tester) async {
    final commands = <AppCommand>[];
    final input = GamepadNavigation(commands.add);
    input.handle(event(axis: GamepadAxis.rightStickY, value: -1));
    input.handle(event(axis: GamepadAxis.rightStickY, value: 0));
    for (final button in [
      GamepadButton.leftBumper,
      GamepadButton.rightBumper,
      GamepadButton.x,
      GamepadButton.y,
      GamepadButton.start,
      GamepadButton.rightStick,
      GamepadButton.b
    ]) {
      input.handle(event(button: button));
    }
    expect(commands, [
      AppCommand.scrollDown,
      AppCommand.previousTab,
      AppCommand.nextTab,
      AppCommand.playPause,
      AppCommand.search,
      AppCommand.help,
      AppCommand.mute,
      AppCommand.back
    ]);
    input.dispose();
  });
}
