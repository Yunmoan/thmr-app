package cn.yunmoan.thmr.thmr_app;

import com.ryanheise.audioservice.AudioServiceActivity;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

/** Flutter bridge for a spectrum of the app's own radio stream. */
public class MainActivity extends AudioServiceActivity {
    private final StreamSpectrumDecoder spectrum = new StreamSpectrumDecoder();

    @Override
    public void configureFlutterEngine(FlutterEngine engine) {
        super.configureFlutterEngine(engine);
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), "thmr/updater")
            .setMethodCallHandler((call, result) -> {
                if (!call.method.equals("installApk")) { result.notImplemented(); return; }
                try {
                    String path = call.argument("path");
                    String version = call.argument("version");
                    Number build = call.argument("buildNumber");
                    if (path == null || version == null || build == null) {
                        result.error("invalid_update", "Missing update metadata", null);
                        return;
                    }
                    result.success(UpdateInstaller.install(this, path, version, build.longValue()));
                } catch (Exception error) {
                    result.error("install_rejected", error.getMessage(), null);
                }
            });
        new MethodChannel(engine.getDartExecutor().getBinaryMessenger(), "thmr/spectrum")
            .setMethodCallHandler((call, result) -> {
                switch (call.method) {
                    case "start" -> {
                        String url = call.argument("url");
                        if (url == null || !(url.startsWith("https://")
                                || url.startsWith("http://"))) {
                            result.success("unavailable");
                        } else {
                            spectrum.start(url);
                            result.success("ready");
                        }
                    }
                    case "bands" -> {
                        Integer count = call.argument("bands");
                        if (count == null || count < 1 || count > 128) {
                            result.error("invalid_bands", "Band count must be 1..128", null);
                        } else if (spectrum.failed()) {
                            result.error("decoder_unavailable",
                                    "Could not decode the radio stream", null);
                        } else {
                            result.success(spectrum.bands(count));
                        }
                    }
                    case "stop" -> {
                        spectrum.stop();
                        result.success(true);
                    }
                    default -> result.notImplemented();
                }
            });
    }

    @Override
    public void onDestroy() {
        spectrum.stop();
        super.onDestroy();
    }
}
