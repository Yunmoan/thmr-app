import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Windows keeps composing a cloaked HWND, including its Flutter surface, but
/// does not expose either its client content or its DWM decorations.
class WindowPresentation {
  static const _channel = MethodChannel('thmr/window_presentation');

  static final activationRequests = ValueNotifier<int>(0);

  Future<void> startupReady() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'activate') activationRequests.value++;
    });
    return _channel.invokeMethod<void>('startupReady');
  }

  Future<void> conceal() => _channel.invokeMethod<void>('conceal');

  Future<void> fullscreenHint(bool fullscreen) =>
      _channel.invokeMethod<void>('fullscreenHint', fullscreen);

  /// Windows does not report taskbar/work-area insets through MediaQuery.
  Future<EdgeInsets> workAreaInsets() async {
    final values =
        await _channel.invokeMapMethod<String, num>('workAreaInsets');
    double inset(String name) {
      final value = values?[name]?.toDouble() ?? 0;
      return value.isFinite ? value.clamp(0, 240) : 0;
    }

    return EdgeInsets.fromLTRB(
        inset('left'), inset('top'), inset('right'), inset('bottom'));
  }

  Future<void> setMaximized(bool maximized) =>
      _channel.invokeMethod<void>('setMaximized', maximized);

  Future<void> waitForFrame() => _waitForFrame('waitForFrame');

  /// Also fence the final enabled surface after its visible entrance.
  Future<void> flushFrame() => _waitForFrame('flushFrame');

  /// Native visibility changes can temporarily pause regular frame scheduling.
  /// Submit the retained or incoming surface even while that pause is active.
  Future<void> submitFrame() {
    final binding = WidgetsBinding.instance;
    final completed = binding.endOfFrame;
    binding.scheduleForcedFrame();
    return completed.timeout(const Duration(seconds: 3));
  }

  Future<void> _waitForFrame(String method) async {
    // endOfFrame submits the target layer tree; it does not wait for raster.
    // The native fence is queued on the raster thread after that submission,
    // and requests a redraw even when the target UI has no active animations.
    final binding = WidgetsBinding.instance;
    await submitFrame();
    var waiting = true;
    void requestFrame(Duration _) {
      if (!waiting) return;
      binding.addPostFrameCallback(requestFrame);
      binding.scheduleForcedFrame();
    }

    // The Windows view's ForceRedraw can skip scheduling while a native resize
    // is pending. A static/transparent target has no animation to wake it later.
    // Keep submitting frames from Dart until the raster fence acknowledges one;
    // no elapsed-time guess or persistent animation is involved.
    final rasterized = _channel.invokeMethod<void>(method);
    requestFrame(Duration.zero);
    try {
      await rasterized;
    } finally {
      waiting = false;
    }
  }

  Future<void> reveal() => _channel.invokeMethod<void>('reveal');
}
