import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

typedef WindowDisplay = ({Rect bounds, Rect workArea});
typedef MiniWindowGeometry = ({
  Rect bounds,
  double scale,
  List<WindowDisplay> displays,
});

/// Windows 会继续合成被 DWM 隐藏的 HWND 及其 Flutter 表面，同时隐藏窗口内容和边框装饰。
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

  /// 显示器和窗口的矩形都使用桌面物理像素坐标。
  Future<MiniWindowGeometry> miniWindowGeometry() async {
    final data = (await _channel
        .invokeMapMethod<String, Object?>('miniWindowGeometry'))!;
    return (
      bounds: _pixelRect(data['bounds']),
      scale: (data['dpi'] as int) / 96,
      displays: (data['displays'] as List<Object?>).map((entry) {
        final display = entry as Map<Object?, Object?>;
        return (
          bounds: _pixelRect(display['bounds']),
          workArea: _pixelRect(display['workArea']),
        );
      }).toList(),
    );
  }

  Future<Rect> windowBoundsInPixels() async =>
      _pixelRect(await _channel.invokeMethod<Object?>('windowBoundsInPixels'));

  Future<void> setWindowPositionInPixels(Offset position) =>
      _channel.invokeMethod<void>('setWindowPositionInPixels', {
        'x': position.dx.round(),
        'y': position.dy.round(),
      });

  Rect _pixelRect(Object? value) {
    final rect = value as Map<Object?, Object?>;
    return Rect.fromLTRB(
      (rect['left'] as num).toDouble(),
      (rect['top'] as num).toDouble(),
      (rect['right'] as num).toDouble(),
      (rect['bottom'] as num).toDouble(),
    );
  }

  /// Windows 的 MediaQuery 不提供任务栏占用的工作区边距，由原生侧计算。
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

  /// 入场动画可见地结束后，等待最终可交互帧完成光栅化。
  Future<void> flushFrame() => _waitForFrame('flushFrame');

  /// 原生窗口的可见性变化可能暂时暂停普通帧调度，主动提交帧可使保留的界面或即将显示的界面继续
  /// 绘制。
  Future<void> submitFrame() {
    final binding = WidgetsBinding.instance;
    final completed = binding.endOfFrame;
    binding.scheduleForcedFrame();
    return completed.timeout(const Duration(seconds: 3));
  }

  Future<void> _waitForFrame(String method) async {
    // endOfFrame 等待 Dart 帧提交图层树。随后由原生侧在光栅线程排队等待绘制，
    // 并为静止界面主动请求重绘。
    final binding = WidgetsBinding.instance;
    await submitFrame();
    var waiting = true;
    void requestFrame(Duration _) {
      if (!waiting) return;
      binding.addPostFrameCallback(requestFrame);
      binding.scheduleForcedFrame();
    }

    // 原生窗口尺寸调整期间，Windows 视图的 ForceRedraw 可能跳过调度。
    // 静止或透明的界面缺少后续动画帧，因此由 Dart 持续提交帧，直到原生侧确认完成光栅化。
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
