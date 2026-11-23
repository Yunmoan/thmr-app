import 'dart:math' as math;
import 'dart:typed_data';

import 'spectrum_fft.dart';

/// 根据新到达、按 PCM 幅值归一化的 FFT 振幅估计有效带宽。读取 [bands] 不更新估计值，
/// 输入时间戳必须单调递增。
class AdaptiveSpectrum {
  AdaptiveSpectrum({this.autoGain = false});

  final bool autoGain;
  Float32List? _frame;
  Float64List? _peakDb;
  int _sampleRate = 0;
  Duration? _lastTime;
  double _upperHz = 0, _targetHz = 0;
  double _lowSeconds = 0, _lowCeilingHz = 0;

  double get upperHz => _upperHz;

  void reset() {
    _frame = null;
    _peakDb = null;
    _sampleRate = 0;
    _lastTime = null;
    _upperHz = _targetHz = 0;
    _lowSeconds = _lowCeilingHz = 0;
  }

  void add(Float32List magnitudes, int sampleRate, Duration time) {
    if (magnitudes.length < 3 || sampleRate < 1000) return;
    if (_sampleRate != sampleRate || _frame?.length != magnitudes.length) {
      reset();
      _sampleRate = sampleRate;
      _upperHz = _targetHz = sampleRate / 2;
      if (autoGain) {
        _peakDb = Float64List(magnitudes.length)
          ..fillRange(0, magnitudes.length, -120);
      }
    }
    final gap =
        _lastTime == null ? 0.0 : (time - _lastTime!).inMicroseconds / 1e6;
    // 采样间隔超过 250 毫秒时重新累计低带宽证据，本帧不平滑带宽。
    final dt = gap > 0 && gap <= 0.25 ? gap : 0.0;
    if (dt == 0) _clearLowEvidence();
    _lastTime = time;
    _frame = Float32List.fromList(magnitudes);

    var peak = 0.0;
    for (var bin = 1; bin < magnitudes.length; bin++) {
      final value = magnitudes[bin];
      if (value.isFinite) peak = math.max(peak, value);
    }
    // 静音或接近静音时暂停带宽估计和过渡。
    if (peak < 0.0005) {
      _clearLowEvidence();
      return;
    }
    final threshold = math.max(0.00025, peak * 0.00316228); // -72 / -50 dB
    var highest = 0, run = 0;
    for (var bin = 1; bin < magnitudes.length; bin++) {
      final value = magnitudes[bin];
      run = value.isFinite && value >= threshold ? run + 1 : 0;
      // 加 Hann 窗后的单频信号会覆盖相邻频点，因此忽略孤立的 FFT 峰值。
      if (run >= 2) highest = bin;
      final peaks = _peakDb;
      if (peaks != null) {
        final db = 20 *
            math.log(value.isFinite ? math.max(value, 1e-7) : 1e-7) /
            math.ln10;
        peaks[bin] = math.max(db, peaks[bin] - 22 * dt);
      }
    }
    if (highest == 0) {
      _clearLowEvidence();
      return;
    }
    final nyquist = sampleRate / 2;
    final binHz = nyquist / (magnitudes.length - 1);
    final desired = ((highest + 1) * binHz * 1.15)
        .clamp(math.min(4000.0, nyquist), nyquist)
        .toDouble();
    if (desired > _targetHz * 1.05) {
      _targetHz = desired;
      _clearLowEvidence();
    } else if (desired < _targetHz * 0.9) {
      _lowSeconds += dt;
      _lowCeilingHz = math.max(_lowCeilingHz, desired);
      if (_lowSeconds >= 3) {
        _targetHz = _lowCeilingHz;
        _clearLowEvidence();
      }
    } else {
      _clearLowEvidence();
    }
    // 在对数频率域平滑带宽，与显示的频率刻度一致。
    final tau = _targetHz > _upperHz ? 0.25 : 1.2;
    final blend = 1 - math.exp(-dt / tau);
    _upperHz *= math.exp(math.log(_targetHz / _upperHz) * blend);
  }

  void _clearLowEvidence() {
    _lowSeconds = _lowCeilingHz = 0;
  }

  Float32List? bands(int count) {
    final frame = _frame;
    if (frame == null || count <= 0) return null;
    return logarithmicSpectrumBands(frame, count, _sampleRate,
        maxHz: _upperHz, peakDb: _peakDb);
  }
}
