import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'desktop_window.dart';

bool get hasMobilePresentation =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS);

bool get supportsLargeScreenMode =>
    hasDesktopWindowControls || hasMobilePresentation;

class MobilePresentation {
  static const _channel = MethodChannel('thmr/mobile_presentation');

  Future<void> setLandscape(bool enabled) =>
      SystemChrome.setPreferredOrientations(enabled
          ? const [
              DeviceOrientation.landscapeLeft,
              DeviceOrientation.landscapeRight,
            ]
          : const []);

  Future<void> setKeepScreenOn(bool enabled) =>
      _channel.invokeMethod<void>('setKeepScreenOn', enabled);
}
