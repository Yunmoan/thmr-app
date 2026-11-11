package cn.yunmoan.thmr.thmr_app;

/** PCM-normalized real FFT; adaptive band mapping is shared in Dart. */
final class SpectrumMath {
    static final int FFT_SIZE = 2048;

    static double[] magnitudes(float[] pcm) {
        if (pcm.length != FFT_SIZE) {
            throw new IllegalArgumentException("Invalid spectrum input");
        }
        double[] real = new double[FFT_SIZE];
        double[] imaginary = new double[FFT_SIZE];
        for (int i = 0; i < FFT_SIZE; i++) {
            double window = 0.5 - 0.5 * Math.cos(2 * Math.PI * i / (FFT_SIZE - 1));
            real[i] = Float.isFinite(pcm[i]) ? pcm[i] * window : 0;
        }
        for (int i = 1, j = 0; i < FFT_SIZE; i++) {
            int bit = FFT_SIZE >> 1;
            for (; (j & bit) != 0; bit >>= 1) j ^= bit;
            j ^= bit;
            if (i < j) {
                double swap = real[i]; real[i] = real[j]; real[j] = swap;
            }
        }
        for (int size = 2; size <= FFT_SIZE; size <<= 1) {
            double angle = -2 * Math.PI / size;
            double stepReal = Math.cos(angle);
            double stepImaginary = Math.sin(angle);
            for (int start = 0; start < FFT_SIZE; start += size) {
                double twiddleReal = 1;
                double twiddleImaginary = 0;
                for (int j = 0; j < size / 2; j++) {
                    int even = start + j;
                    int odd = even + size / 2;
                    double productReal = twiddleReal * real[odd]
                            - twiddleImaginary * imaginary[odd];
                    double productImaginary = twiddleReal * imaginary[odd]
                            + twiddleImaginary * real[odd];
                    real[odd] = real[even] - productReal;
                    imaginary[odd] = imaginary[even] - productImaginary;
                    real[even] += productReal;
                    imaginary[even] += productImaginary;
                    double nextReal = twiddleReal * stepReal
                            - twiddleImaginary * stepImaginary;
                    twiddleImaginary = twiddleReal * stepImaginary
                            + twiddleImaginary * stepReal;
                    twiddleReal = nextReal;
                }
            }
        }
        double[] result = new double[FFT_SIZE / 2 + 1];
        for (int bin = 0; bin < result.length; bin++) {
            result[bin] = Math.hypot(real[bin], imaginary[bin]) * 4.0 / FFT_SIZE;
        }
        return result;
    }

    private SpectrumMath() { }
}
