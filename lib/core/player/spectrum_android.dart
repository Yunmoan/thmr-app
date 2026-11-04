// Android spectrum from a second decoder of the app's shared radio bytes.
// This never captures the microphone or other apps' output.

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'shared_radio_stream.dart';
import 'spectrum.dart';

enum AndroidSpectrumStatus { starting, ready, unavailable }

class AndroidSpectrum implements SpectrumSource {
  AndroidSpectrum._(this._streamUrl);

  static String? _currentStreamUrl() {
    return sharedRadioStream.spectrumUri?.toString();
  }

  static final AndroidSpectrum _instance = AndroidSpectrum._(_currentStreamUrl);
  static AndroidSpectrum? tryCreate() => _instance;
  AndroidSpectrum.forTesting(String? Function() streamUrl)
      : _streamUrl = streamUrl;

  static const channel = MethodChannel('thmr/spectrum');
  final String? Function() _streamUrl;

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
    _last = null;
    try {
      final url = _streamUrl();
      if (url == null || url.isEmpty) {
        status = AndroidSpectrumStatus.unavailable;
        return;
      }
      final result = await channel
          .invokeMethod<String>('start', <String, Object>{'url': url});
      if (generation != _generation || _refs == 0) return;
      status = switch (result) {
        'ready' => AndroidSpectrumStatus.ready,
        _ => AndroidSpectrumStatus.unavailable,
      };
    } catch (_) {
      if (generation == _generation) {
        status = AndroidSpectrumStatus.unavailable;
      }
    }
  }

  Future<bool> retry() async {
    if (_refs == 0) return false;
    final generation = _generation;
    try {
      await _startCapture(generation);
      return _refs > 0 &&
          generation == _generation &&
          status == AndroidSpectrumStatus.ready;
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
      final levels = await channel
          .invokeMethod<Uint8List>('bands', <String, Object>{'bands': bands});
      if (generation != _generation || _refs == 0) return;
      _last = levels == null ? null : spectrumBandsFromLevels(levels, bands);
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

/// Native decoder returns one unsigned 0..255 level per requested band.
Float32List spectrumBandsFromLevels(Uint8List levels, int bands) {
  final out = Float32List(bands);
  for (var band = 0; band < math.min(bands, levels.length); band++) {
    out[band] = levels[band] / 255;
  }
  return out;
}
