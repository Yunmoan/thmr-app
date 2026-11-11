package cn.yunmoan.thmr.thmr_app;

import android.media.AudioFormat;
import android.media.MediaCodec;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import android.util.Log;

import java.nio.ByteBuffer;
import java.nio.ByteOrder;
import java.util.HashMap;
import java.util.Map;

/** Decodes THMR's loopback MP3 stream to PCM, without any audio capture API. */
final class StreamSpectrumDecoder {
    private static final String TAG = "ThmrSpectrum";
    private final Object samplesLock = new Object();
    // Live MP3 extractors can deliver several seconds of PCM in one burst.
    // Keep a bounded queue so each UI frame advances through real audio.
    private final float[] samples = new float[48000 * 8];
    private volatile long generation;
    private volatile boolean decodeFailed;
    private Thread worker;
    private int writeIndex;
    private int readIndex;
    private int available;
    private int sampleRate = 44100;
    private long lastPollNanos;
    private boolean startedReading;

    synchronized void start(String url) {
        stop();
        decodeFailed = false;
        Log.i(TAG, "Starting spectrum decoder");
        final long token = generation;
        worker = new Thread(() -> decode(url, token), "thmr-spectrum-decoder");
        worker.setDaemon(true);
        worker.start();
    }

    synchronized void stop() {
        generation++;
        if (worker != null) {
            worker.interrupt();
            worker = null;
        }
        synchronized (samplesLock) {
            writeIndex = 0;
            readIndex = 0;
            available = 0;
            lastPollNanos = 0;
            startedReading = false;
        }
    }

    boolean failed() {
        return decodeFailed;
    }

    Map<String, Object> magnitudes() {
        float[] snapshot = new float[SpectrumMath.FFT_SIZE];
        int rate;
        synchronized (samplesLock) {
            if (available == 0 || (!startedReading && available < snapshot.length)) {
                return null;
            }
            long now = System.nanoTime();
            if (!startedReading || available > sampleRate * 7) {
                // Retain enough PCM to bridge the extractor's multi-second gaps.
                int skip = Math.max(0, available - Math.max(sampleRate * 5,
                        snapshot.length));
                readIndex = (readIndex + skip) % samples.length;
                available -= skip;
                startedReading = true;
            }
            int step = lastPollNanos == 0 ? snapshot.length
                    : (int) Math.max(1, Math.min(sampleRate / 5,
                            (now - lastPollNanos) * sampleRate / 1_000_000_000L));
            step = Math.min(step, available);
            if (step == 0) return null;
            readIndex = (readIndex + step) % samples.length;
            available -= step;
            lastPollNanos = now;
            for (int i = 0; i < snapshot.length; i++) {
                snapshot[i] = samples[(readIndex - snapshot.length + i
                        + samples.length) % samples.length];
            }
            rate = sampleRate;
        }
        Map<String, Object> frame = new HashMap<>();
        frame.put("sampleRate", rate);
        frame.put("magnitudes", SpectrumMath.magnitudes(snapshot));
        return frame;
    }

    private void decode(String url, long token) {
        MediaExtractor extractor = new MediaExtractor();
        MediaCodec codec = null;
        boolean codecStarted = false;
        try {
            Log.i(TAG, "Opening shared radio stream");
            extractor.setDataSource(url);
            Log.i(TAG, "Shared radio stream opened; tracks=" + extractor.getTrackCount());
            MediaFormat inputFormat = null;
            for (int i = 0; i < extractor.getTrackCount(); i++) {
                MediaFormat candidate = extractor.getTrackFormat(i);
                String mime = candidate.getString(MediaFormat.KEY_MIME);
                if (mime != null && mime.startsWith("audio/")) {
                    extractor.selectTrack(i);
                    inputFormat = candidate;
                    break;
                }
            }
            if (inputFormat == null || token != generation) return;
            codec = MediaCodec.createDecoderByType(inputFormat.getString(MediaFormat.KEY_MIME));
            codec.configure(inputFormat, null, null, 0);
            codec.start();
            codecStarted = true;

            MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
            MediaFormat outputFormat = inputFormat;
            boolean inputEnded = false;
            while (token == generation && !Thread.currentThread().isInterrupted()) {
                if (!inputEnded) {
                    int inputIndex = codec.dequeueInputBuffer(10000);
                    if (inputIndex >= 0) {
                        ByteBuffer input = codec.getInputBuffer(inputIndex);
                        if (input == null) throw new IllegalStateException("No codec input buffer");
                        input.clear();
                        int size = extractor.readSampleData(input, 0);
                        if (size < 0) {
                            codec.queueInputBuffer(inputIndex, 0, 0, 0,
                                    MediaCodec.BUFFER_FLAG_END_OF_STREAM);
                            inputEnded = true;
                        } else {
                            codec.queueInputBuffer(inputIndex, 0, size,
                                    Math.max(0, extractor.getSampleTime()), 0);
                            extractor.advance();
                        }
                    }
                }
                int outputIndex = codec.dequeueOutputBuffer(info, 10000);
                if (outputIndex == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    outputFormat = codec.getOutputFormat();
                } else if (outputIndex >= 0) {
                    ByteBuffer output = codec.getOutputBuffer(outputIndex);
                    if (output != null && info.size > 0 && token == generation) {
                        appendPcm(output, info, outputFormat, token);
                    }
                    codec.releaseOutputBuffer(outputIndex, false);
                    if ((info.flags & MediaCodec.BUFFER_FLAG_END_OF_STREAM) != 0) break;
                }
            }
            if (token == generation) decodeFailed = true;
        } catch (Exception error) {
            if (token == generation) {
                decodeFailed = true;
                Log.w(TAG, "Radio spectrum decoder unavailable: "
                        + error.getClass().getSimpleName());
            }
        } finally {
            if (codec != null) {
                if (codecStarted) {
                    try { codec.stop(); } catch (Exception ignored) { }
                }
                codec.release();
            }
            extractor.release();
        }
    }

    private void appendPcm(ByteBuffer output, MediaCodec.BufferInfo info,
                           MediaFormat format, long token) {
        int channels = format.containsKey(MediaFormat.KEY_CHANNEL_COUNT)
                ? format.getInteger(MediaFormat.KEY_CHANNEL_COUNT) : 2;
        int rate = format.containsKey(MediaFormat.KEY_SAMPLE_RATE)
                ? format.getInteger(MediaFormat.KEY_SAMPLE_RATE) : 44100;
        int encoding = format.containsKey(MediaFormat.KEY_PCM_ENCODING)
                ? format.getInteger(MediaFormat.KEY_PCM_ENCODING)
                : AudioFormat.ENCODING_PCM_16BIT;
        if (channels < 1 || channels > 8) throw new IllegalStateException("Unsupported channels");
        if (encoding != AudioFormat.ENCODING_PCM_16BIT
                && encoding != AudioFormat.ENCODING_PCM_FLOAT) {
            throw new IllegalStateException("Unsupported PCM encoding");
        }
        int bytesPerSample = encoding == AudioFormat.ENCODING_PCM_FLOAT ? 4 : 2;
        ByteBuffer pcm = output.duplicate().order(ByteOrder.LITTLE_ENDIAN);
        pcm.position(info.offset);
        pcm.limit(info.offset + info.size);
        int frames = pcm.remaining() / (channels * bytesPerSample);
        float[] mono = new float[frames];
        for (int i = 0; i < frames; i++) {
            float sum = 0;
            for (int ch = 0; ch < channels; ch++) {
                sum += encoding == AudioFormat.ENCODING_PCM_FLOAT
                        ? pcm.getFloat() : pcm.getShort() / 32768.0f;
            }
            mono[i] = sum / channels;
        }
        synchronized (samplesLock) {
            if (token != generation) return;
            if (sampleRate != rate) {
                readIndex = 0;
                writeIndex = 0;
                available = 0;
                startedReading = false;
                lastPollNanos = 0;
            }
            sampleRate = rate;
            for (float value : mono) {
                samples[writeIndex] = value;
                writeIndex = (writeIndex + 1) % samples.length;
                if (available == samples.length) {
                    readIndex = (readIndex + 1) % samples.length;
                } else {
                    available++;
                }
            }
        }
    }
}
