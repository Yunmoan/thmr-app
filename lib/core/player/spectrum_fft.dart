import 'dart:math' as math;
import 'dart:typed_data';

/// A bounded PCM window. Decode and FFT run in the spectrum worker isolate.
class PcmSpectrumDecoder {
  static const windowSize = 2048;
  final _samples = Float32List(windowSize);
  int _write = 0, _count = 0, _sinceFrame = 0, _sampleRate = 0;

  Float32List? add(Float32List pcm, int channels, int sampleRate) {
    if (sampleRate != _sampleRate) {
      _write = _count = _sinceFrame = 0;
      _sampleRate = sampleRate;
    }
    Float32List? latest;
    for (var offset = 0; offset + channels <= pcm.length; offset += channels) {
      var sample = 0.0;
      for (var channel = 0; channel < channels; channel++) {
        sample += pcm[offset + channel];
      }
      sample /= channels;
      _samples[_write] = sample.isFinite ? sample : 0;
      _write = (_write + 1) % windowSize;
      _count = math.min(windowSize, _count + 1);
      _sinceFrame++;
      if (_count == windowSize && _sinceFrame >= sampleRate ~/ 20) {
        _sinceFrame = 0;
        final window = Float32List(windowSize);
        for (var i = 0; i < windowSize; i++) {
          window[i] = _samples[(_write + i) % windowSize];
        }
        latest = pcmMagnitudes(window);
      }
    }
    return latest;
  }
}

/// Radix-2 FFT with a Hann window; amplitudes are normalized to input PCM.
Float32List pcmMagnitudes(Float32List samples) {
  final n = samples.length;
  if (n < 2 || (n & (n - 1)) != 0) {
    throw ArgumentError('FFT length must be a power of two');
  }
  final real = Float64List(n);
  final imaginary = Float64List(n);
  for (var i = 0; i < n; i++) {
    real[i] = samples[i] * (0.5 - 0.5 * math.cos(2 * math.pi * i / (n - 1)));
  }
  for (var i = 1, j = 0; i < n; i++) {
    var bit = n >> 1;
    for (; j & bit != 0; bit >>= 1) {
      j ^= bit;
    }
    j ^= bit;
    if (i < j) {
      final value = real[i];
      real[i] = real[j];
      real[j] = value;
    }
  }
  for (var size = 2; size <= n; size <<= 1) {
    final angle = -2 * math.pi / size;
    final stepReal = math.cos(angle), stepImaginary = math.sin(angle);
    for (var start = 0; start < n; start += size) {
      var wr = 1.0, wi = 0.0;
      for (var j = 0; j < size ~/ 2; j++) {
        final a = start + j, b = a + size ~/ 2;
        final tr = wr * real[b] - wi * imaginary[b];
        final ti = wr * imaginary[b] + wi * real[b];
        real[b] = real[a] - tr;
        imaginary[b] = imaginary[a] - ti;
        real[a] += tr;
        imaginary[a] += ti;
        final next = wr * stepReal - wi * stepImaginary;
        wi = wr * stepImaginary + wi * stepReal;
        wr = next;
      }
    }
  }
  return Float32List.fromList(List.generate(
      n ~/ 2 + 1,
      (i) =>
          math.sqrt(real[i] * real[i] + imaginary[i] * imaginary[i]) * 4 / n));
}

Float32List logarithmicSpectrumBands(
    Float32List magnitudes, int bands, int sampleRate,
    {double? maxHz, Float64List? peakDb}) {
  final result = Float32List(bands);
  final bins = magnitudes.length - 1;
  final nyquist = sampleRate / 2;
  final upper = (maxHz ?? nyquist).clamp(40.0, nyquist);
  for (var band = 0; band < bands; band++) {
    final low = (40 * math.pow(upper / 40, band / bands) * bins / nyquist)
        .floor()
        .clamp(1, bins);
    final high =
        (40 * math.pow(upper / 40, (band + 1) / bands) * bins / nyquist)
            .ceil()
            .clamp(low + 1, bins + 1);
    var amplitude = 0.0;
    var referenceDb = -120.0;
    for (var bin = low; bin < high; bin++) {
      final value = magnitudes[bin];
      if (value.isFinite) amplitude = math.max(amplitude, value);
      if (peakDb != null) referenceDb = math.max(referenceDb, peakDb[bin]);
    }
    final db = 20 * math.log(math.max(amplitude, 0.0000001)) / math.ln10;
    result[band] = peakDb == null
        ? ((db + 72) / 72).clamp(0, 1)
        : db <= -72
            ? 0
            : ((db - referenceDb + 30) / 30).clamp(0, 1);
  }
  return result;
}
