// Spectrum source abstraction and per-platform picker.
//  - Windows: thmr_capture.dll (WASAPI loopback + FFT, dart:ffi)
//  - Android: Visualizer(output mix) via method channel
//  - others  : null -> UI falls back to the energy model

import 'dart:io' show Platform;
import 'dart:typed_data';

import 'spectrum_ffi.dart' show SpectrumCapture;
import 'spectrum_android.dart' show AndroidSpectrum;

abstract class SpectrumSource {
  void start();
  void stop();

  /// Synchronous poll returning normalized 0..1 band values,
  /// or null when no fresh data this frame.
  Float32List? poll(int bands);
}

SpectrumSource? getPlatformSpectrum() {
  if (Platform.isWindows) {
    return SpectrumCapture.tryCreate();
  }
  if (Platform.isAndroid) {
    return AndroidSpectrum.tryCreate();
  }
  return null;
}
