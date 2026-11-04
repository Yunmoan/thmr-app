package cn.yunmoan.thmr.thmr_app;

/** Real FFT of decoded PCM, mapped to logarithmic frequency bands. */
final class SpectrumMath {
    static final int FFT_SIZE = 2048;

    static byte[] bands(float[] pcm, int sampleRate, int count) {
        if (pcm.length != FFT_SIZE || sampleRate < 1000 || count < 1) {
            throw new IllegalArgumentException("Invalid spectrum input");
        }
        double[] real = new double[FFT_SIZE];
        double[] imaginary = new double[FFT_SIZE];
        for (int i = 0; i < FFT_SIZE; i++) {
            double window = 0.5 - 0.5 * Math.cos(2 * Math.PI * i / (FFT_SIZE - 1));
            real[i] = pcm[i] * window;
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
        byte[] result = new byte[count];
        double minHz = 50;
        double maxHz = Math.min(16000, sampleRate / 2.0);
        double ratio = maxHz / minHz;
        for (int band = 0; band < count; band++) {
            double lowHz = minHz * Math.pow(ratio, (double) band / count);
            double highHz = minHz * Math.pow(ratio, (double) (band + 1) / count);
            int lowBin = Math.max(1, (int) Math.floor(lowHz * FFT_SIZE / sampleRate));
            int highBin = Math.min(FFT_SIZE / 2,
                    Math.max(lowBin + 1, (int) Math.ceil(highHz * FFT_SIZE / sampleRate)));
            double peak = 0;
            for (int bin = lowBin; bin < highBin; bin++) {
                peak = Math.max(peak, Math.hypot(real[bin], imaginary[bin]));
            }
            double db = 20 * Math.log10(Math.max(1e-9, peak / (FFT_SIZE / 4.0)));
            double level = Math.max(0, Math.min(1, (db + 55) / 55));
            result[band] = (byte) Math.round(level * 255);
        }
        return result;
    }

    private SpectrumMath() { }
}
