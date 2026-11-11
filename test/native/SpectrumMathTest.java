package cn.yunmoan.thmr.thmr_app;

/** Standalone javac/java check of Android's production FFT, without a device. */
public final class SpectrumMathTest {
    public static void main(String[] args) {
        float[] pcm = new float[SpectrumMath.FFT_SIZE];
        for (int i = 0; i < pcm.length; i++) {
            pcm[i] = (float) (0.5 * Math.sin(2 * Math.PI * 320 * i / pcm.length));
        }
        double[] fft = SpectrumMath.magnitudes(pcm);
        require(fft.length == 1025, "Missing Nyquist bin");
        require(Math.abs(fft[320] - 0.5) < 0.002, "Wrong PCM normalization");
        require(fft[319] > 0.24, "Windowed tone lost its adjacent bin");
        require(fft[900] < 0.0001, "Unexpected high-frequency energy");
        for (double value : SpectrumMath.magnitudes(new float[2048])) {
            require(value == 0, "Silence produced motion");
        }
        pcm[0] = Float.NaN;
        pcm[1] = Float.POSITIVE_INFINITY;
        for (double value : SpectrumMath.magnitudes(pcm)) {
            require(Double.isFinite(value), "Non-finite PCM escaped into FFT");
        }
        System.out.println("Android FFT, normalization, silence and invalid PCM passed");
    }

    private static void require(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }
}
