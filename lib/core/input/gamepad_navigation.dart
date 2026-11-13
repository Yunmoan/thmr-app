import 'dart:async';

import 'package:gamepads/gamepads.dart';

import 'app_commands.dart';

/// Converts normalized hardware state into discrete UI commands. Only
/// navigation/scrolling repeat; reconnects and window deactivation clear holds.
class GamepadNavigation {
  GamepadNavigation(this.onCommand);
  final void Function(AppCommand) onCommand;
  final _held = <(String, String), AppCommand>{};
  Timer? _repeat;

  void handle(NormalizedGamepadEvent event) {
    final button = event.button;
    final axis = event.axis;
    final key = (event.gamepadId, button?.name ?? axis!.name);
    final previous = _held[key];
    final threshold = previous == null ? 0.55 : 0.35;
    final AppCommand? command;
    if (button != null) {
      command = event.value < 0.5
          ? null
          : switch (button) {
              GamepadButton.dpadUp => AppCommand.up,
              GamepadButton.dpadDown => AppCommand.down,
              GamepadButton.dpadLeft => AppCommand.left,
              GamepadButton.dpadRight => AppCommand.right,
              GamepadButton.a => AppCommand.activate,
              GamepadButton.b || GamepadButton.back => AppCommand.back,
              GamepadButton.x => AppCommand.playPause,
              GamepadButton.y => AppCommand.search,
              GamepadButton.leftBumper => AppCommand.previousTab,
              GamepadButton.rightBumper => AppCommand.nextTab,
              GamepadButton.start => AppCommand.help,
              GamepadButton.rightStick => AppCommand.mute,
              _ => null,
            };
    } else if (event.value.abs() < threshold) {
      command = null;
    } else {
      command = switch (axis!) {
        GamepadAxis.leftStickX =>
          event.value < 0 ? AppCommand.left : AppCommand.right,
        GamepadAxis.leftStickY =>
          event.value < 0 ? AppCommand.down : AppCommand.up,
        GamepadAxis.rightStickY =>
          event.value < 0 ? AppCommand.scrollDown : AppCommand.scrollUp,
        _ => null,
      };
    }
    if (previous == command) return;
    _held.remove(key);
    if (command != null) {
      _held[key] = command;
      onCommand(command);
    }
    _scheduleRepeat();
  }

  bool _repeats(AppCommand command) => switch (command) {
        AppCommand.up ||
        AppCommand.down ||
        AppCommand.left ||
        AppCommand.right ||
        AppCommand.scrollUp ||
        AppCommand.scrollDown =>
          true,
        _ => false,
      };

  void _scheduleRepeat() {
    _repeat?.cancel();
    final commands = _held.values.where(_repeats);
    if (commands.isEmpty) return;
    final command = commands.last;
    _repeat = Timer(const Duration(milliseconds: 400), () {
      onCommand(command);
      _repeat = Timer.periodic(const Duration(milliseconds: 110), (_) {
        onCommand(command);
      });
    });
  }

  void disconnect(String id) {
    _held.removeWhere((key, _) => key.$1 == id);
    _scheduleRepeat();
  }

  void reset() {
    _repeat?.cancel();
    _repeat = null;
    _held.clear();
  }

  void dispose() => reset();
}
