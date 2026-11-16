import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/platform/desktop_window.dart';
import '../../core/platform/window_presentation.dart';
import '../../core/state/large_screen_settings.dart';
import '../mini/mini_player.dart';

class LargeScreenState {
  const LargeScreenState(
      {this.active = false,
      this.fullScreen = false,
      this.busy = false,
      this.error});
  final bool active;
  final bool fullScreen;
  final bool busy;
  final String? error;
}

final largeScreenProvider =
    StateNotifierProvider<LargeScreenController, LargeScreenState>(
        (ref) => LargeScreenController(ref));

final largeScreenRevealRequests = ValueNotifier<int>(0);
typedef _PresentationTarget = ({bool active, bool? fullScreen});

/// Serialize native changes and keep the latest requested presentation.
/// Controls stay busy until the incoming surface has finished its entrance.
class LargeScreenController extends StateNotifier<LargeScreenState> {
  LargeScreenController(this._ref) : super(const LargeScreenState());

  final Ref _ref;
  final _presentation = WindowPresentation();
  Future<void>? _inFlight;
  _PresentationTarget? _pending;
  _PresentationTarget? _target;
  Future<void> Function(bool)? animatePresentation;
  Future<void> Function(bool)? animateStandard;
  bool _restoreFullScreen = false;
  bool get _windows => defaultTargetPlatform == TargetPlatform.windows;

  Future<void> change(bool active) => _request(active: active);

  Future<void> toggleFullScreen() {
    final desired = _pending ?? _target;
    if (!(desired?.active ?? state.active)) return change(true);
    final fullScreen = desired?.fullScreen ??
        (state.active
            ? state.fullScreen
            : _ref.read(largeScreenSettingsProvider).startFullScreen ||
                state.fullScreen);
    return _request(fullScreen: !fullScreen);
  }

  Future<void> _request({bool? active, bool? fullScreen}) {
    if (!hasDesktopWindowControls ||
        _ref.read(miniPlayerProvider) ||
        _ref.read(miniTransitionBusyProvider)) {
      return Future.value();
    }
    final base = _pending ??
        _target ??
        (active: state.active, fullScreen: state.fullScreen);
    final next = (
      active: active ?? base.active,
      fullScreen: fullScreen ??
          (active != null && active != base.active ? null : base.fullScreen),
    );
    if (_inFlight == null &&
        next.active == state.active &&
        (next.fullScreen == null || next.fullScreen == state.fullScreen)) {
      return Future.value();
    }
    _pending = next;
    if (_inFlight != null) return _inFlight!;
    final completion = Completer<void>();
    _inFlight = completion.future;
    unawaited(_drain(completion));
    return completion.future;
  }

  Future<void> _drain(Completer<void> completion) async {
    try {
      while (mounted && _pending != null) {
        final next = _pending!;
        _pending = null;
        _target = next;
        if (next.active != state.active ||
            (next.fullScreen != null && next.fullScreen != state.fullScreen)) {
          await _change(next);
        }
      }
    } finally {
      _target = null;
      _inFlight = null;
      completion.complete();
    }
  }

  Future<void> _paint({required bool concealed}) async {
    if (_windows) {
      if (concealed) {
        await _presentation.waitForFrame();
      } else {
        await _presentation.flushFrame();
      }
    } else {
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  Future<void> _animate(bool visible) async {
    await (state.active ? animatePresentation : animateStandard)?.call(visible);
  }

  Future<void> _change(_PresentationTarget target) async {
    final previous = state;
    var previousFullScreen = previous.fullScreen;
    var concealed = false;
    String? errorMessage;
    state = LargeScreenState(
        active: previous.active, fullScreen: previous.fullScreen, busy: true);
    try {
      previousFullScreen = await windowManager.isFullScreen();
      if (!mounted) return;
      if (!previous.active && target.active) {
        _restoreFullScreen = previousFullScreen;
      }
      final targetFullScreen = target.fullScreen ??
          (target.active
              ? _ref.read(largeScreenSettingsProvider).startFullScreen ||
                  previousFullScreen
              : _restoreFullScreen);
      _target = (active: target.active, fullScreen: targetFullScreen);
      await _animate(false);
      if (!mounted) return;
      if (_windows) {
        await _presentation.conceal();
        concealed = true;
      }
      if (target.active && !previous.active) {
        // Freeze the normal shell before any native metrics arrive.
        state = LargeScreenState(
            active: true, fullScreen: targetFullScreen, busy: true);
        await WidgetsBinding.instance.endOfFrame;
      }
      if (previousFullScreen != targetFullScreen) {
        await windowManager.setFullScreen(targetFullScreen);
        // Consume restored native metrics while the normal shell is still
        // retained at its old extent. Reflow it only after this raster fence.
        await _paint(concealed: concealed);
      }
      if (!mounted) return;
      state = LargeScreenState(
          active: target.active, fullScreen: targetFullScreen, busy: true);
      await _paint(concealed: concealed);
    } catch (error, stack) {
      debugPrint('Large screen transition failed: $error\n$stack');
      errorMessage = !target.active ? '无法收起大屏模式，请重试。' : '无法切换显示模式，请重试。';
      try {
        if (await windowManager.isFullScreen() != previousFullScreen) {
          await windowManager.setFullScreen(previousFullScreen);
          await _paint(concealed: concealed);
        }
      } catch (rollbackError) {
        debugPrint('Fullscreen rollback failed: $rollbackError');
      }
      if (mounted) {
        state = LargeScreenState(
            active: previous.active,
            fullScreen: previousFullScreen,
            busy: true);
        try {
          await _paint(concealed: concealed);
        } catch (paintError) {
          debugPrint('Presentation recovery failed: $paintError');
        }
      }
    } finally {
      if (concealed) {
        try {
          await _presentation.reveal();
        } catch (error) {
          // A transient reveal failure must not leave a permanently hidden HWND.
          debugPrint('Presentation reveal failed: $error');
          try {
            await _presentation.reveal();
          } catch (retryError) {
            debugPrint('Presentation reveal retry failed: $retryError');
          }
          errorMessage ??= '无法恢复窗口显示，请重试。';
        }
      }
      if (mounted) {
        try {
          await windowManager.focus();
        } catch (error) {
          debugPrint('Window focus failed: $error');
        }
        try {
          await _animate(true);
        } catch (error) {
          debugPrint('Presentation entrance failed: $error');
          errorMessage ??= '无法完成显示切换，请重试。';
        }
        if (mounted) {
          state = LargeScreenState(
              active: state.active,
              fullScreen: state.fullScreen,
              error: errorMessage);
          try {
            await _paint(concealed: false);
          } catch (error) {
            debugPrint('Final presentation frame failed: $error');
          }
        }
      }
    }
  }

  void nativeFullScreenChanged(bool fullScreen) {
    if (_inFlight == null && state.active) {
      state = LargeScreenState(active: true, fullScreen: fullScreen);
    }
  }
}
