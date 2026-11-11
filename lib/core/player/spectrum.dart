// Spectrum source abstraction and per-platform picker.
//  - Windows: thmr_capture.dll (WASAPI loopback + FFT, dart:ffi)
//  - Android: decoded PCM from this app's radio stream via method channel
//  - Linux: bundled minimp3 + FFT in a worker isolate
//  - others  : null -> UI stays still rather than simulating audio
// All supported platforms share adaptive bandwidth detection and logarithmic
// band mapping in Dart, before the UI's attack/release envelope.

import 'dart:io' show Platform;
import 'dart:typed_data';

import 'spectrum_ffi.dart' show SpectrumCapture;
import 'spectrum_android.dart' show AndroidSpectrum;
import 'spectrum_linux.dart' show LinuxSpectrum;

abstract class SpectrumSource {
  void start();
  void stop();

  /// Synchronous poll returning normalized 0..1 band values,
  /// or null when no fresh data this frame.
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
  return null;
}
