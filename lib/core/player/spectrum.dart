// 频谱数据源接口及各平台的实现选择。
// - Windows：通过 dart:ffi 调用 thmr_capture.dll，使用 WASAPI loopback 采集并执行 FFT。
// - Android：通过 MethodChannel 获取应用直播流解码后的频谱。
// - Linux：在 worker isolate 中用内置 minimp3 解码并执行 FFT。
// - iOS / macOS：同样使用 minimp3 和 worker isolate，原生解码器打包为 framework。
// - 其他平台：返回 null，界面保持静止。
// 各平台在 Dart 端共用自适应带宽估计和对数频带映射，随后由 UI 对振幅上升和衰减做平滑。

import 'dart:io' show Platform;
import 'dart:typed_data';

import 'spectrum_ffi.dart' show SpectrumCapture;
import 'spectrum_android.dart' show AndroidSpectrum;
import 'spectrum_linux.dart' show LinuxSpectrum;

abstract class SpectrumSource {
  void start();
  void stop();

  /// 同步读取最近一帧已归一化到 0–1 的频带值。未接收到可用数据或最近一帧已过期时返回 null。
  Float32List? poll(int bands);
}

abstract class RetryableSpectrumSource implements SpectrumSource {
  bool get isUnavailable;
  String? get unavailableReason;
  Future<bool> retry();
}

SpectrumSource? getPlatformSpectrum() {
  if (Platform.isWindows) {
    return SpectrumCapture.tryCreate();
  }
  if (Platform.isAndroid) {
    return AndroidSpectrum.tryCreate();
  }
  if (Platform.isLinux) return LinuxSpectrum.instance;
  if (Platform.isIOS || Platform.isMacOS) return LinuxSpectrum.appleInstance;
  return null;
}
