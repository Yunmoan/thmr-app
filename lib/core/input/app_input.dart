import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:gamepads/gamepads.dart';

import '../../features/mini/mini_player.dart';
import '../../shared/widgets/input_help.dart';
import '../player/playback_controller.dart';
import '../state/station_provider.dart';
import 'app_commands.dart';
import 'gamepad_navigation.dart';

final gamepadEventsProvider = Provider((ref) => Gamepads.normalizedEvents);
final gamepadConnectionsProvider = Provider((ref) => Gamepads.connectionEvents);

/// Shared command entry point. Hardware input is scoped to this foreground
/// window and uses the focused route's actions, including modal focus traps.
class AppInput extends ConsumerStatefulWidget {
  const AppInput({super.key, required this.navigatorKey, required this.child});
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  ConsumerState<AppInput> createState() => _AppInputState();
}

class _AppInputState extends ConsumerState<AppInput>
    with WidgetsBindingObserver {
  late final _gamepad = GamepadNavigation((command) => _run(command));
  StreamSubscription<NormalizedGamepadEvent>? _events;
  StreamSubscription<GamepadConnectionEvent>? _connections;
  final _focus = FocusNode(debugLabel: '应用操作', skipTraversal: true);
  bool _foreground = true;
  bool _helpOpen = false;
  late final FocusHighlightStrategy _previousHighlightStrategy;

  @override
  void initState() {
    super.initState();
    _previousHighlightStrategy = FocusManager.instance.highlightStrategy;
    WidgetsBinding.instance.addObserver(this);
    _foreground = WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    try {
      _events = ref.read(gamepadEventsProvider).listen((event) {
        if (!_foreground) return;
        FocusManager.instance.highlightStrategy =
            FocusHighlightStrategy.alwaysTraditional;
        _gamepad.handle(event);
      }, onError: _inputError);
      _connections = ref.read(gamepadConnectionsProvider).listen((event) {
        if (event.type == GamepadConnectionEventType.disconnected) {
          _gamepad.disconnect(event.gamepadId);
        }
      }, onError: _inputError);
    } catch (error) {
      _inputError(error);
    }
  }

  void _inputError(Object error) {
    _gamepad.reset();
    debugPrint('Gamepad input unavailable: $error');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) _gamepad.reset();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_events?.cancel());
    unawaited(_connections?.cancel());
    _gamepad.dispose();
    _focus.dispose();
    FocusManager.instance.highlightStrategy = _previousHighlightStrategy;
    super.dispose();
  }

  bool get _mainRoute => widget.navigatorKey.currentState?.canPop() == false;

  Future<void> _navigate(AppCommand command, int? index) async {
    if (!_mainRoute) return;
    if (ref.read(miniPlayerProvider)) await exitMiniMode(ref);
    if (!mounted || !_mainRoute) return;
    final current = ref.read(appTabProvider);
    ref.read(appTabProvider.notifier).state = switch (command) {
      AppCommand.tab => index!.clamp(0, 3),
      AppCommand.search => 1,
      AppCommand.previousTab => (current + 3) % 4,
      _ => (current + 1) % 4,
    };
    if (command == AppCommand.search) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _mainRoute && !ref.read(miniPlayerProvider)) {
          ref.read(librarySearchFocusProvider).requestFocus();
        }
      });
    }
  }

  Future<void> _help() async {
    if (_helpOpen) return;
    _helpOpen = true;
    try {
      if (ref.read(miniPlayerProvider)) await exitMiniMode(ref);
      if (!mounted) return;
      final context = widget.navigatorKey.currentState?.overlay?.context;
      if (context != null && context.mounted) await showInputHelp(context);
    } finally {
      _helpOpen = false;
    }
  }

  void _focusCommand(AppCommand command) {
    final node = FocusManager.instance.primaryFocus;
    final context = node?.context;
    if (context == null) return;
    final direction = switch (command) {
      AppCommand.up => TraversalDirection.up,
      AppCommand.down => TraversalDirection.down,
      AppCommand.left => TraversalDirection.left,
      AppCommand.right => TraversalDirection.right,
      _ => null,
    };
    if (direction != null) {
      if (node is FocusScopeNode || node == _focus) {
        node!.nextFocus();
      } else {
        Actions.maybeInvoke(context, DirectionalFocusIntent(direction));
      }
    } else if (command == AppCommand.activate) {
      // Text fields retain their normal editing/IME path.
      Actions.maybeInvoke(context, const ActivateIntent());
    } else if (command == AppCommand.scrollUp ||
        command == AppCommand.scrollDown) {
      Actions.maybeInvoke(
          context,
          ScrollIntent(
            direction: command == AppCommand.scrollUp
                ? AxisDirection.up
                : AxisDirection.down,
          ));
    }
  }

  void _run(AppCommand command, [int? index]) {
    if (!mounted || !_foreground || ref.read(miniTransitionBusyProvider)) {
      return;
    }
    final mini = ref.read(miniPlayerProvider);
    switch (command) {
      case AppCommand.back:
        final context = FocusManager.instance.primaryFocus?.context;
        final route = context == null ? null : ModalRoute.of(context);
        if (route is PopupRoute && !route.barrierDismissible) return;
        final dismiss =
            context == null ? null : Actions.maybeFind<DismissIntent>(context);
        if (context != null &&
            dismiss?.isEnabled(const DismissIntent()) == true) {
          Actions.invoke(context, const DismissIntent());
        } else if (!_mainRoute && route != null && route is! PopupRoute) {
          unawaited(widget.navigatorKey.currentState?.maybePop());
        } else if (mini) {
          unawaited(exitMiniMode(ref));
        }
      case AppCommand.help:
        unawaited(_help());
      case AppCommand.tab:
      case AppCommand.previousTab:
      case AppCommand.nextTab:
      case AppCommand.search:
        unawaited(_navigate(command, index));
      case AppCommand.playPause:
        ref.read(playbackProvider.notifier).toggle(ref.read(streamUrlProvider));
      case AppCommand.mute:
        ref
            .read(playbackProvider.notifier)
            .setVolume(ref.read(playbackProvider).volumeAfterMuteToggle);
      case AppCommand.volumeUp:
      case AppCommand.volumeDown:
        final volume = ref.read(playbackProvider).volume;
        ref.read(playbackProvider.notifier).setVolume(
            (volume + (command == AppCommand.volumeUp ? 5 : -5)).clamp(0, 100));
      case AppCommand.mini:
        if (!_mainRoute ||
            kIsWeb ||
            defaultTargetPlatform != TargetPlatform.windows) {
          return;
        }
        unawaited(mini
            ? exitMiniMode(ref)
            : enterMiniMode(ref, MediaQuery.textScalerOf(context)));
      default:
        if (mini) {
          miniRevealRequests.value++;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && ref.read(miniPlayerProvider)) _focusCommand(command);
          });
        } else {
          _focusCommand(command);
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final shortcuts = <ShortcutActivator, Intent>{
      const SingleActivator(LogicalKeyboardKey.f1):
          const AppCommandIntent(AppCommand.help),
      const SingleActivator(LogicalKeyboardKey.escape):
          const AppCommandIntent(AppCommand.back),
    };
    final mac = defaultTargetPlatform == TargetPlatform.macOS;
    for (final meta in [false, if (mac) true]) {
      SingleActivator key(LogicalKeyboardKey key, {bool shift = false}) =>
          SingleActivator(key,
              control: !meta, meta: meta, shift: shift, includeRepeats: false);
      shortcuts.addAll({
        key(LogicalKeyboardKey.keyP):
            const AppCommandIntent(AppCommand.playPause),
        if (!meta || !mac)
          key(LogicalKeyboardKey.keyM): const AppCommandIntent(AppCommand.mute),
        key(LogicalKeyboardKey.keyM, shift: true):
            AppCommandIntent(meta && mac ? AppCommand.mute : AppCommand.mini),
        key(LogicalKeyboardKey.keyF): const AppCommandIntent(AppCommand.search),
        key(LogicalKeyboardKey.arrowUp):
            const AppCommandIntent(AppCommand.volumeUp),
        key(LogicalKeyboardKey.arrowDown):
            const AppCommandIntent(AppCommand.volumeDown),
        for (var i = 0; i < 4; i++)
          key([
            LogicalKeyboardKey.digit1,
            LogicalKeyboardKey.digit2,
            LogicalKeyboardKey.digit3,
            LogicalKeyboardKey.digit4
          ][i]): AppCommandIntent(AppCommand.tab, i),
      });
    }
    return Listener(
      onPointerDown: (_) => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic,
      child: Shortcuts(
          shortcuts: shortcuts,
          child: Actions(
            actions: {
              AppCommandIntent: CallbackAction<AppCommandIntent>(
                onInvoke: (intent) {
                  _run(intent.command, intent.index);
                  return null;
                },
              )
            },
            child:
                Focus(focusNode: _focus, autofocus: true, child: widget.child),
          )),
    );
  }
}
