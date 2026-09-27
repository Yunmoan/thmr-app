// Android spectrum source: Visualizer(output mix) over a method channel.
// Requires android.permission.RECORD_AUDIO.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'spectrum.dart';

class AndroidSpectrum implements SpectrumSource {
  AndroidSpectrum._();

  static final AndroidSpectrum _instance = AndroidSpectrum._();

  static AndroidSpectrum? tryCreate() => _instance;

  static const _channel = MethodChannel('thmr/spectrum');
  int _refs = 0;
  bool _failed = false;
  Float32List? _last;

  @override
  void start() {
    if (_failed) return;
    _refs++;
    if (_refs == 1) {
      _channel.invokeMethod<bool>('start').then((ok) {
        if (ok != true) _failed = true;
      }).catchError((_) {
        _failed = true;
      });
      _fetch(48); // warm up
    }
  }

  @override
  void stop() {
    if (_refs <= 0) return;
    _refs--;
    if (_refs == 0) {
      _channel.invokeMethod<void>('stop').catchError((_) {});
    }
  }

  @override
  Float32List? poll(int bands) {
    if (_refs <= 0 || _failed) return null;
    _fetch(bands); // async refresh, sync return of last frame
    return _last;
  }

  Future<void> _fetch(int bands) async {
    try {
      final fft = await _channel.invokeMethod<List<Object?>>('fft');
      if (!identical(this, AndroidSpectrum.tryCreate())) return;
      final n = fft!.length;
      if (n < 5) return;
      // Visualizer FFT bytes: index 0 is DC, then alternating re/im.
      final halfBins = n ~/ 2 - 1;
      final out = Float32List(bands);
      for (var b = 0; b < bands; b++) {
        final lo = (halfBins * b * b) ~/ (bands * bands);
        var hi = (halfBins * (b + 1) * (b + 1)) ~/ (bands * bands);
        if (hi <= lo) hi = lo + 1;
        var peak = 0.0;
        for (var k = lo; k < hi && 2 * k + 2 < n; k++) {
          final re = (fft[2 * k + 1] as int) - 128; // signed magnitude
          final im = (fft[2 * k + 2] as int) - 128;
          final m2 = (re * re + im * im).toDouble();
          if (m2 > peak) peak = m2;
        }
        // dB mapping: floor -40 dB -> 0, top -> 1
        final db = 20 * math.log(peak + 1e-6) / math.ln10;
        out[b] = ((db + 40) / 40).clamp(0.0, 1.0).toDouble();
      }
      _last = out;
    } on PlatformException {
      _failed = true;
      _last = null;
    }
  }
}
