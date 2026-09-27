// Android output-mix FFT from the platform Visualizer. No simulated data.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'spectrum.dart';

enum AndroidSpectrumStatus { starting, ready, permissionRequired, unavailable }

class AndroidSpectrum implements SpectrumSource {
  AndroidSpectrum._();

  static final AndroidSpectrum _instance = AndroidSpectrum._();
  static AndroidSpectrum? tryCreate() => _instance;
  static const channel = MethodChannel('thmr/spectrum');

  int _refs = 0;
  int _generation = 0;
  bool _fetching = false;
  Float32List? _last;
  AndroidSpectrumStatus status = AndroidSpectrumStatus.starting;

  @override
  void start() {
    _refs++;
    if (_refs == 1) {
      _generation++;
      _startCapture(_generation);
    }
  }

  Future<void> _startCapture(int generation) async {
    status = AndroidSpectrumStatus.starting;
    try {
      final result = await channel.invokeMethod<String>('start');
      if (generation != _generation || _refs == 0) return;
      status = switch (result) {
        'ready' => AndroidSpectrumStatus.ready,
        'permissionRequired' => AndroidSpectrumStatus.permissionRequired,
        _ => AndroidSpectrumStatus.unavailable,
      };
    } catch (_) {
      if (generation == _generation) {
        status = AndroidSpectrumStatus.unavailable;
      }
    }
  }

  /// Called after the user opens the in-app permission explanation.
  Future<bool> requestAccess() async {
    if (_refs == 0) return false;
    final generation = _generation;
    try {
      if (status == AndroidSpectrumStatus.permissionRequired) {
        final granted =
            await channel.invokeMethod<bool>('requestPermission') ?? false;
        if (!granted) return false;
      }
      if (_refs == 0 || generation != _generation) return false;
      await _startCapture(generation);
      return status == AndroidSpectrumStatus.ready;
    } catch (_) {
      status = AndroidSpectrumStatus.unavailable;
      return false;
    }
  }

  @override
  void stop() {
    if (_refs <= 0) return;
    _refs--;
    if (_refs == 0) {
      _generation++;
      _last = null;
      channel.invokeMethod<void>('stop').catchError((_) {});
    }
  }

  @override
  Float32List? poll(int bands) {
    if (_refs == 0 || status != AndroidSpectrumStatus.ready || bands <= 0) {
      return null;
    }
    if (!_fetching) _fetch(bands, _generation);
    return _last?.length == bands ? _last : null;
  }

  Future<void> _fetch(int bands, int generation) async {
    _fetching = true;
    try {
      final fft = await channel.invokeMethod<Uint8List>('fft');
      if (generation != _generation || _refs == 0) return;
      _last = fft == null ? null : spectrumBandsFromFft(fft, bands);
    } catch (_) {
      if (generation == _generation) {
        _last = null;
        status = AndroidSpectrumStatus.unavailable;
      }
    } finally {
      _fetching = false;
    }
  }
}

/// Android Visualizer format: DC at byte 0, Nyquist at byte 1, then
/// interleaved signed real/imaginary bytes for bins 1..N/2-1.
Float32List spectrumBandsFromFft(Uint8List fft, int bands) {
  final out = Float32List(bands);
  final maxBin = fft.length ~/ 2 - 1;
  if (bands <= 0 || maxBin < 1) return out;
  for (var band = 0; band < bands; band++) {
    final lo = math.max(1, math.exp(math.log(maxBin) * band / bands).floor());
    final next = math.exp(math.log(maxBin) * (band + 1) / bands).ceil();
    final hi = math.min(maxBin + 1, math.max(lo + 1, next));
    var peak = 0.0;
    for (var bin = lo; bin < hi; bin++) {
      final re = _signed(fft[bin * 2]);
      final im = _signed(fft[bin * 2 + 1]);
      peak = math.max(peak, math.sqrt(re * re + im * im));
    }
    if (peak < 2) continue;
    final db = 20 * math.log(peak / 128) / math.ln10;
    out[band] = ((db + 45) / 42).clamp(0.0, 1.0).toDouble();
  }
  return out;
}

int _signed(int byte) => byte >= 128 ? byte - 256 : byte;
