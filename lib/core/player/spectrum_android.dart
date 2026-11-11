// Android spectrum from a second decoder of the app's shared radio bytes.
// This never captures the microphone or other apps' output.

import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'shared_radio_stream.dart';
import 'spectrum.dart';
import 'adaptive_spectrum.dart';

enum AndroidSpectrumStatus { starting, ready, unavailable }

class AndroidSpectrum implements RetryableSpectrumSource {
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
  final _spectrum = AdaptiveSpectrum();
  final _clock = Stopwatch()..start();
  Duration? _lastFrame;
  String? _url;
  AndroidSpectrumStatus status = AndroidSpectrumStatus.starting;

  @override
  bool get isUnavailable => status == AndroidSpectrumStatus.unavailable;
  @override
  String? get unavailableReason =>
      isUnavailable ? '实时频谱暂不可用，请检查电台连接后重试。' : null;

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
    _spectrum.reset();
    _lastFrame = null;
    try {
      final url = _streamUrl();
      _url = url;
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

  @override
  Future<bool> retry() async {
    if (_refs == 0) return false;
    final generation = ++_generation;
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
      _lastFrame = null;
      _spectrum.reset();
      channel.invokeMethod<void>('stop').catchError((_) {});
    }
  }

  @override
  Float32List? poll(int bands) {
    if (_refs > 0 && _url != _streamUrl()) {
      _startCapture(++_generation);
      return null;
    }
    if (_refs == 0 || status != AndroidSpectrumStatus.ready || bands <= 0) {
      return null;
    }
    if (!_fetching) _fetch(_generation);
    if (_lastFrame == null ||
        _clock.elapsed - _lastFrame! > const Duration(milliseconds: 250)) {
      return null;
    }
    return _spectrum.bands(bands);
  }

  Future<void> _fetch(int generation) async {
    _fetching = true;
    try {
      final frame = await channel.invokeMapMethod<String, Object>('magnitudes');
      if (generation != _generation || _refs == 0) return;
      if (frame != null) {
        final magnitudes = frame['magnitudes'] as Float64List;
        final rate = frame['sampleRate'] as int;
        final now = _clock.elapsed;
        _spectrum.add(Float32List.fromList(magnitudes), rate, now);
        _lastFrame = now;
      }
    } catch (_) {
      if (generation == _generation) {
        _lastFrame = null;
        status = AndroidSpectrumStatus.unavailable;
      }
    } finally {
      _fetching = false;
    }
  }
}
