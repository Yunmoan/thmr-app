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

/// Native fullscreen and the player presentation can change independently.
/// On Windows, reveal only after the final surface has actually rasterized.
class LargeScreenController extends StateNotifier<LargeScreenState> {
  LargeScreenController(this._ref) : super(const LargeScreenState());

  final Ref _ref;
  final _presentation = WindowPresentation();
  Future<void>? _inFlight;
  Future<void> Function(bool)? animatePresentation;
  bool _restoreFullScreen = false;
  bool get _windows => defaultTargetPlatform == TargetPlatform.windows;

  Future<void> change(bool active) => _request(active: active);

  Future<void> toggleFullScreen() =>
      state.active ? _request(fullScreen: !state.fullScreen) : change(true);

  Future<void> _request({bool? active, bool? fullScreen}) {
    if (!hasDesktopWindowControls) return Future.value();
    if (_inFlight != null) return _inFlight!;
    if ((active != null && state.active == active) ||
        _ref.read(miniPlayerProvider) ||
        _ref.read(miniTransitionBusyProvider)) {
      return Future.value();
    }
    return _inFlight = _change(active: active, fullScreen: fullScreen)
        .whenComplete(() => _inFlight = null);
  }

  Future<void> _paint() async {
    if (_windows) {
      await _presentation.waitForFrame();
    } else {
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  Future<void> _change({bool? active, bool? fullScreen}) async {
    final previous = state;
    var previousFullScreen = previous.fullScreen;
    var concealed = false;
    state = LargeScreenState(
        active: previous.active, fullScreen: previous.fullScreen, busy: true);
    try {
      if (active == false) await animatePresentation?.call(false);
      previousFullScreen = await windowManager.isFullScreen();
      if (!mounted) return;
      if (active == true) _restoreFullScreen = previousFullScreen;
      final targetFullScreen = fullScreen ??
          (active == true
              ? _ref.read(largeScreenSettingsProvider).startFullScreen ||
                  previousFullScreen
              : _restoreFullScreen);
      if (_windows) {
        await _presentation.conceal();
        concealed = true;
      }
      if (active == true) {
        // Retain the shell's old extent before native metrics change.
        state = LargeScreenState(
            active: true, fullScreen: targetFullScreen, busy: true);
        await WidgetsBinding.instance.endOfFrame;
      }
      if (previousFullScreen != targetFullScreen) {
        await windowManager.setFullScreen(targetFullScreen);
      }
      if (!mounted) return;
      // Paint enabled controls and the final page before revealing the HWND.
      state = LargeScreenState(
          active: active ?? previous.active, fullScreen: targetFullScreen);
      await _paint();
    } catch (error, stack) {
      debugPrint('Large screen transition failed: $error\n$stack');
      try {
        if (await windowManager.isFullScreen() != previousFullScreen) {
          await windowManager.setFullScreen(previousFullScreen);
        }
      } catch (rollbackError) {
        debugPrint('Fullscreen rollback failed: $rollbackError');
      }
      if (mounted) {
        state = LargeScreenState(
            active: previous.active,
            fullScreen: previousFullScreen,
            error: active == false ? '无法收起大屏模式，请重试。' : '无法切换显示模式，请重试。');
        try {
          await _paint();
        } catch (paintError) {
          debugPrint('Presentation recovery failed: $paintError');
        }
      }
    } finally {
      if (concealed) await _presentation.reveal();
      if (mounted) {
        await windowManager.focus();
        if (state.active) await animatePresentation?.call(true);
      }
    }
  }

  void nativeFullScreenChanged(bool fullScreen) {
    if (_inFlight == null && state.active) {
      state = LargeScreenState(active: true, fullScreen: fullScreen);
    }
  }
}
