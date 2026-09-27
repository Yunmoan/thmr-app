package cn.yunmoan.thmr.thmr_app;

import android.media.audiofx.Visualizer;
import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import io.ryanheise.audioservice.AudioServiceActivity;

// Java 而非 Kotlin:AGP 9.1 + KGP 2.4 下 :app 的 Kotlin 编译解析不到插件工程类
// (releaseApiElements 变体歧义),javac 类路径不受影响。
public class MainActivity extends AudioServiceActivity {
    private Visualizer visualizer = null;

    @Override
    public void configureFlutterEngine(FlutterEngine engine) {
        super.configureFlutterEngine(engine);
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), "thmr/spectrum")
            .setMethodCallHandler((call, result) -> {
                switch (call.method) {
                    case "start" -> {
                        try {
                            if (visualizer == null) {
                                // session 0 = output mix
                                Visualizer v = new Visualizer(0);
                                v.setCaptureSize(Visualizer.getCaptureSizeRange()[1]);
                                v.setScalingMode(Visualizer.SCALING_MODE_NORMALIZED);
                                v.setEnabled(true);
                                visualizer = v;
                            }
                            result.success(true);
                        } catch (Exception e) {
                            visualizer = null;
                            result.success(false);
                        }
                    }
                    case "fft" -> {
                        Visualizer v = visualizer;
                        if (v == null) {
                            result.success(null);
                        } else {
                            byte[] bytes = new byte[v.getCaptureSize()];
                            int ok = v.getFft(bytes);
                            result.success(ok < 0 ? null : bytes);
                        }
                    }
                    case "stop" -> {
                        try {
                            if (visualizer != null) {
                                visualizer.setEnabled(false);
                                visualizer.release();
                            }
                        } catch (Exception ignored) {
                        }
                        visualizer = null;
                        result.success(true);
                    }
                    default -> result.notImplemented();
                }
            });
    }

    @Override
    public void onDestroy() {
        try {
            if (visualizer != null) {
                visualizer.setEnabled(false);
                visualizer.release();
            }
        } catch (Exception ignored) {
        }
        visualizer = null;
        super.onDestroy();
    }
}
