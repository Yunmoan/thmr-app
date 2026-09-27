package cn.yunmoan.thmr.thmr_app;

import android.Manifest;
import android.content.pm.PackageManager;
import android.media.audiofx.Visualizer;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;
import com.ryanheise.audioservice.AudioServiceActivity;

// Keep this launcher in the Java source set so Gradle compiles the
// activity referenced by AndroidManifest.xml.
public class MainActivity extends AudioServiceActivity {
    private static final int SPECTRUM_PERMISSION_REQUEST = 1097;
    private Visualizer visualizer = null;
    private MethodChannel.Result permissionResult = null;

    @Override
    public void configureFlutterEngine(FlutterEngine engine) {
        super.configureFlutterEngine(engine);
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), "thmr/spectrum")
            .setMethodCallHandler((call, result) -> {
                switch (call.method) {
                    case "start" -> {
                        result.success(startVisualizer());
                    }
                    case "requestPermission" -> {
                        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO)
                                == PackageManager.PERMISSION_GRANTED) {
                            result.success(true);
                        } else if (permissionResult != null) {
                            result.error("permission_pending", "Permission request already open", null);
                        } else {
                            permissionResult = result;
                            requestPermissions(
                                new String[]{Manifest.permission.RECORD_AUDIO},
                                SPECTRUM_PERMISSION_REQUEST);
                        }
                    }
                    case "fft" -> {
                        Visualizer v = visualizer;
                        if (v == null) {
                            result.success(null);
                        } else {
                            try {
                                byte[] bytes = new byte[v.getCaptureSize()];
                                int ok = v.getFft(bytes);
                                result.success(ok < 0 ? null : bytes);
                            } catch (Exception e) {
                                result.success(null);
                            }
                        }
                    }
                    case "stop" -> {
                        releaseVisualizer();
                        result.success(true);
                    }
                    default -> result.notImplemented();
                }
            });
    }

    private String startVisualizer() {
        if (checkSelfPermission(Manifest.permission.RECORD_AUDIO)
                != PackageManager.PERMISSION_GRANTED) {
            return "permissionRequired";
        }
        if (visualizer != null) return "ready";
        Visualizer candidate = null;
        try {
            // Session 0 captures the output mix used by media_kit/mpv.
            candidate = new Visualizer(0);
            candidate.setCaptureSize(Visualizer.getCaptureSizeRange()[1]);
            candidate.setScalingMode(Visualizer.SCALING_MODE_NORMALIZED);
            candidate.setEnabled(true);
            visualizer = candidate;
            return "ready";
        } catch (Exception e) {
            if (candidate != null) {
                try { candidate.release(); } catch (Exception ignored) {}
            }
            return "unavailable";
        }
    }

    private void releaseVisualizer() {
        Visualizer current = visualizer;
        visualizer = null;
        if (current == null) return;
        try { current.setEnabled(false); } catch (Exception ignored) {}
        try { current.release(); } catch (Exception ignored) {}
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions,
                                           int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == SPECTRUM_PERMISSION_REQUEST && permissionResult != null) {
            MethodChannel.Result pending = permissionResult;
            permissionResult = null;
            pending.success(grantResults.length > 0
                && grantResults[0] == PackageManager.PERMISSION_GRANTED);
        }
    }

    @Override
    public void onDestroy() {
        releaseVisualizer();
        if (permissionResult != null) {
            permissionResult.success(false);
            permissionResult = null;
        }
        super.onDestroy();
    }
}
