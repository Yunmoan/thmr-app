import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Tooltip;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/platform/mobile_presentation.dart';
import '../../core/platform/window_presentation.dart';
import '../../core/state/large_screen_settings.dart';
import '../mini/mini_player.dart';

class LargeScreenState {
  const LargeScreenState(
      {this.active = false,
      this.fullScreen = false,
      this.busy = false,
      this.contentVisible = true,
      this.switchingInPlace = false,
      this.error});
  final bool active;
  final bool fullScreen;
  final bool busy;

  /// 原生切换或入场动画进行时，组件重挂载也会保留该状态。
  final bool contentVisible;
  final bool switchingInPlace;
  final String? error;
}

final largeScreenProvider =
    StateNotifierProvider<LargeScreenController, LargeScreenState>(
        (ref) => LargeScreenController(ref));

final largeScreenRevealRequests = ValueNotifier<int>(0);
typedef _PresentationTarget = ({bool active, bool? fullScreen});

/// 串行处理原生窗口切换，并保留最新请求。新界面完成入场前，控件保持忙碌状态。
class LargeScreenController extends StateNotifier<LargeScreenState> {
  LargeScreenController(this._ref) : super(const LargeScreenState());

  final Ref _ref;
  final _presentation = WindowPresentation();
  Future<void>? _inFlight;
  _PresentationTarget? _pending;
  _PresentationTarget? _target;
  Future<void> Function(bool)? animatePresentation;
  Future<void> Function(bool)? animateStandard;
  Future<void> Function(bool)? animateInPlace;
  Future<void> Function()? refreshMetrics;
  bool _restoreFullScreen = false;
  Completer<void>? _nativeFullScreenWaiter;
  bool? _nativeFullScreenTarget;
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
    if (!supportsLargeScreenMode ||
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
      await _presentation.submitFrame();
    }
  }

  Future<void> _animate(bool visible) async {
    state = LargeScreenState(
        active: state.active,
        fullScreen: state.fullScreen,
        busy: state.busy,
        contentVisible: visible,
        error: state.error);
    await (state.active ? animatePresentation : animateStandard)?.call(visible);
  }

  Future<void> _setFullScreen(bool fullScreen) async {
    // AppKit 发起 Space 切换时就会回复，GTK 也异步切换。等待完成事件后再恢复普通页面的布局尺寸。
    final completed = _windows ? null : Completer<void>();
    _nativeFullScreenWaiter = completed;
    _nativeFullScreenTarget = fullScreen;
    try {
      await windowManager.setFullScreen(fullScreen);
      if (completed != null) {
        await completed.future.timeout(const Duration(seconds: 5));
      }
    } finally {
      _nativeFullScreenWaiter = null;
      _nativeFullScreenTarget = null;
    }
  }

  Future<void> _change(_PresentationTarget target) async {
    if (hasMobilePresentation) return _changeMobile(target.active);
    final previous = state;
    final changesPage = previous.active != target.active;
    var switchingInPlace = false;
    var animateSwitch = false;
    var previousFullScreen = previous.fullScreen;
    var concealed = false;
    String? errorMessage;
    state = LargeScreenState(
        active: previous.active, fullScreen: previous.fullScreen, busy: true);
    try {
      await _ref.read(largeScreenSettingsProvider.notifier).ready;
      if (!mounted) return;
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
      Tooltip.dismissAllToolTips();
      switchingInPlace =
          _windows && changesPage && previousFullScreen == targetFullScreen;
      if (switchingInPlace) {
        await refreshMetrics?.call();
        if (!mounted) return;
        state = LargeScreenState(
            active: previous.active,
            fullScreen: previousFullScreen,
            busy: true,
            switchingInPlace: true);
        await animateInPlace?.call(target.active);
        if (mounted) {
          state = LargeScreenState(
              active: target.active, fullScreen: targetFullScreen, busy: true);
        }
        return;
      }
      // Windows 调整窗口尺寸时保留完整的大屏界面，直到原生窗口隐藏。
      animateSwitch = changesPage && (!_windows || target.active);
      if (animateSwitch) await _animate(false);
      if (!mounted) return;
      if (_windows) {
        await _presentation.conceal();
        concealed = true;
      }
      if (target.active && !previous.active) {
        // 在收到新的原生窗口尺寸前，先固定普通界面的布局。
        state = LargeScreenState(
            active: true,
            fullScreen: targetFullScreen,
            busy: true,
            contentVisible: false);
        await _presentation.submitFrame();
      }
      if (previousFullScreen != targetFullScreen) {
        await _setFullScreen(targetFullScreen);
        // 先接收恢复后的原生窗口尺寸，普通界面暂留原尺寸。等待光栅化确认后再重新布局。
        await _paint(concealed: concealed);
      }
      if (!mounted) return;
      await refreshMetrics?.call();
      state = LargeScreenState(
          active: target.active,
          fullScreen: targetFullScreen,
          busy: true,
          contentVisible: !animateSwitch);
      await _paint(concealed: concealed);
    } catch (error, stack) {
      debugPrint('Large screen transition failed: $error\n$stack');
      errorMessage = !target.active ? '无法收起大屏幕模式，请重试。' : '无法切换显示模式，请重试。';
      try {
        if (await windowManager.isFullScreen() != previousFullScreen) {
          await _setFullScreen(previousFullScreen);
          await _paint(concealed: concealed);
        }
      } catch (rollbackError) {
        debugPrint('Fullscreen rollback failed: $rollbackError');
      }
      if (mounted) {
        await refreshMetrics?.call();
        state = LargeScreenState(
            active: previous.active,
            fullScreen: previousFullScreen,
            contentVisible: !animateSwitch,
            busy: true);
        try {
          await _paint(concealed: concealed);
        } catch (paintError) {
          debugPrint('Presentation recovery failed: $paintError');
        }
      }
    } finally {
      // 入场动画第一帧以零透明度记录起始时间。再等待下一帧光栅化后显示窗口，
      // 确保尺寸变化后的首次入场也能直接看到新界面。
      final entrance = mounted && animateSwitch ? _animate(true) : null;
      if (concealed) {
        try {
          await _paint(concealed: true);
          if (entrance != null) await _paint(concealed: true);
        } catch (error) {
          debugPrint('Entrance frame fence failed: $error');
        }
        try {
          await _presentation.reveal();
        } catch (error) {
          // 原生显示短暂失败时继续尝试，避免 HWND 一直隐藏。
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
        if (!switchingInPlace) {
          try {
            await windowManager.focus();
            if (_windows) await _presentation.fullscreenHint(state.fullScreen);
          } catch (error) {
            debugPrint('Window focus failed: $error');
          }
        }
        if (entrance != null) {
          try {
            await entrance;
          } catch (error) {
            debugPrint('Presentation entrance failed: $error');
            errorMessage ??= '无法完成显示切换，请重试。';
          }
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

  Future<void> _changeMobile(bool active) async {
    final previous = state;
    String? errorMessage;
    state = LargeScreenState(active: previous.active, busy: true);
    try {
      await _ref.read(largeScreenSettingsProvider.notifier).ready;
      if (!mounted) return;
      Tooltip.dismissAllToolTips();
      await _animate(false);
      if (!mounted) return;
      state =
          LargeScreenState(active: active, busy: true, contentVisible: false);
      await _presentation.submitFrame();
    } catch (error, stack) {
      debugPrint('Mobile presentation failed: $error\n$stack');
      errorMessage = '无法切换大屏幕模式，请重试。';
      if (mounted) {
        state = LargeScreenState(
            active: previous.active, busy: true, contentVisible: false);
      }
    } finally {
      if (mounted) {
        try {
          await _animate(true);
        } catch (error) {
          debugPrint('Mobile presentation entrance failed: $error');
          errorMessage ??= '无法完成显示切换，请重试。';
        }
        if (mounted) {
          state = LargeScreenState(active: state.active, error: errorMessage);
        }
      }
    }
  }

  void nativeFullScreenChanged(bool fullScreen) {
    final waiter = _nativeFullScreenWaiter;
    if (waiter != null &&
        !waiter.isCompleted &&
        _nativeFullScreenTarget == fullScreen) {
      waiter.complete();
    }
    if (mounted && state.fullScreen != fullScreen) {
      state = LargeScreenState(
          active: state.active,
          fullScreen: fullScreen,
          contentVisible: state.contentVisible,
          busy: state.busy,
          switchingInPlace: state.switchingInPlace,
          error: state.error);
    }
  }

  @override
  void dispose() {
    final waiter = _nativeFullScreenWaiter;
    if (waiter != null && !waiter.isCompleted) waiter.complete();
    super.dispose();
  }
}
