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

  Future<void> setMaximized(bool maximized) =>
      _channel.invokeMethod<void>('setMaximized', maximized);

  Future<void> waitForFrame() async {
    // endOfFrame submits the target layer tree; it does not wait for raster.
    // The native fence is queued on the raster thread after that submission,
    // and requests a redraw even when the target UI has no active animations.
    final binding = WidgetsBinding.instance;
    await binding.endOfFrame;
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
    final rasterized = _channel.invokeMethod<void>('waitForFrame');
    requestFrame(Duration.zero);
    try {
      await rasterized;
    } finally {
      waiting = false;
    }
  }

  Future<void> reveal() => _channel.invokeMethod<void>('reveal');
}
