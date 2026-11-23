import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'desktop_window.dart';

bool get hasIosPresentation =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

bool get hasMobilePresentation =>
    hasIosPresentation ||
    (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

bool get supportsLargeScreenMode =>
    hasDesktopWindowControls || hasMobilePresentation;

class MobilePresentation {
  static const _channel = MethodChannel('thmr/mobile_presentation');

  Future<void> setKeepScreenOn(bool enabled) =>
      _channel.invokeMethod<void>('setKeepScreenOn', enabled);
}

final iosIsPadProvider = FutureProvider<bool?>((ref) async {
  if (!hasIosPresentation) return null;
  try {
    return await MobilePresentation._channel.invokeMethod<bool>('isIPad');
  } on MissingPluginException {
    return null;
  } on PlatformException catch (error) {
    debugPrint('iOS device type unavailable: $error');
    return null;
  }
});

bool usesPhoneLayout(BuildContext context, WidgetRef ref,
    {bool listen = true}) {
  if (!hasMobilePresentation) return false;
  if (hasIosPresentation) {
    final isPad =
        (listen ? ref.watch(iosIsPadProvider) : ref.read(iosIsPadProvider))
            .valueOrNull;
    if (isPad != null) return !isPad;
  }
  // 分屏只缩小应用视图，平板判断仍以整块屏幕的尺寸为准。
  final display = View.maybeOf(context)?.display;
  if (display != null && !display.size.isEmpty) {
    return display.size.shortestSide / display.devicePixelRatio < 600;
  }
  return MediaQuery.sizeOf(context).shortestSide < 600;
}
