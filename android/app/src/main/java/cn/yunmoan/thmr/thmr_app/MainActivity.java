package cn.yunmoan.thmr.thmr_app;

import android.hardware.input.InputManager;
import android.os.Handler;
import android.view.InputDevice;
import android.view.KeyEvent;
import android.view.MotionEvent;
import com.ryanheise.audioservice.AudioServiceActivity;
import kotlin.jvm.functions.Function1;
import org.flame_engine.gamepads_android.GamepadsCompatibleActivity;

import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

/** Flutter bridge for a spectrum of the app's own radio stream. */
public class MainActivity extends AudioServiceActivity implements GamepadsCompatibleActivity {
    private final StreamSpectrumDecoder spectrum = new StreamSpectrumDecoder();
    private Function1<? super KeyEvent, Boolean> gamepadKeyHandler;
    private Function1<? super MotionEvent, Boolean> gamepadMotionHandler;

    @Override
    public boolean dispatchKeyEvent(KeyEvent event) {
        if (gamepadKeyHandler != null && Boolean.TRUE.equals(gamepadKeyHandler.invoke(event))) {
            return true;
        }
        return super.dispatchKeyEvent(event);
    }

    @Override
    public boolean dispatchGenericMotionEvent(MotionEvent event) {
        if (gamepadMotionHandler != null && Boolean.TRUE.equals(gamepadMotionHandler.invoke(event))) {
            return true;
        }
        return super.dispatchGenericMotionEvent(event);
    }

    @Override
    public void registerKeyEventHandler(Function1<? super KeyEvent, Boolean> handler) {
        gamepadKeyHandler = handler;
    }

    @Override
    public void registerMotionEventHandler(Function1<? super MotionEvent, Boolean> handler) {
        gamepadMotionHandler = handler;
    }

    @Override
    public void registerInputDeviceListener(InputManager.InputDeviceListener listener, Handler handler) {
        ((InputManager) getSystemService(INPUT_SERVICE)).registerInputDeviceListener(listener, handler);
    }

    @Override
    public boolean isGamepadsInputDevice(InputDevice device) {
        int sources = device.getSources();
        if ((sources & InputDevice.SOURCE_GAMEPAD) != InputDevice.SOURCE_GAMEPAD
                && (sources & InputDevice.SOURCE_JOYSTICK) != InputDevice.SOURCE_JOYSTICK) {
            return false;
        }
        if (device.getKeyboardType() != InputDevice.KEYBOARD_TYPE_ALPHABETIC) return true;
        // Composite typing keyboards can advertise joystick sources. Only
        // claim devices with a supported stick/trigger axis or gamepad button.
        int[] axes = {MotionEvent.AXIS_X, MotionEvent.AXIS_Y, MotionEvent.AXIS_Z,
            MotionEvent.AXIS_RX, MotionEvent.AXIS_RY, MotionEvent.AXIS_RZ,
            MotionEvent.AXIS_HAT_X, MotionEvent.AXIS_HAT_Y,
            MotionEvent.AXIS_LTRIGGER, MotionEvent.AXIS_RTRIGGER,
            MotionEvent.AXIS_BRAKE, MotionEvent.AXIS_GAS};
        for (int axis : axes) {
            if (device.getMotionRange(axis, InputDevice.SOURCE_JOYSTICK) != null) return true;
        }
        for (int key = KeyEvent.KEYCODE_BUTTON_A; key <= KeyEvent.KEYCODE_BUTTON_MODE; key++) {
            if (device.hasKeys(key)[0]) return true;
        }
        for (int key = KeyEvent.KEYCODE_BUTTON_1; key <= KeyEvent.KEYCODE_BUTTON_16; key++) {
            if (device.hasKeys(key)[0]) return true;
        }
        return false;
    }

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
                    case "magnitudes" -> {
                        if (spectrum.failed()) {
                            result.error("decoder_unavailable",
                                    "Could not decode the radio stream", null);
                        } else {
                            result.success(spectrum.magnitudes());
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
