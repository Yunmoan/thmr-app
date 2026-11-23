import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/state/settings_provider.dart';
import 'core/input/app_input.dart';
import 'core/theme/thmr_theme.dart';
import 'core/theme/thmr_motion.dart';
import 'core/theme/thmr_focus_ring.dart';
import 'features/mini/desktop_player_surface.dart';
import 'features/mini/mini_player.dart' show miniPlayerProvider;
import 'features/large_screen/large_screen_controller.dart';
import 'features/shell/home_shell.dart';
import 'features/account/update_panel.dart';
import 'shared/widgets/thmr_background.dart';

// 构建 Material 主题时也会解析字体。仅订阅影响主题的偏好，避免播放状态或码率变化触发重建。
final appThemesProvider = Provider((ref) {
  final accent = ref.watch(settingsProvider.select((s) => s.accentTheme));
  return (ThmrTheme.light(accent), ThmrTheme.dark(accent));
});

final appNavigatorKeyProvider = Provider((ref) => GlobalKey<NavigatorState>());

class ThmrApp extends ConsumerWidget {
  const ThmrApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(settingsProvider.select((s) => s.themeMode));
    final (light, dark) = ref.watch(appThemesProvider);
    final navigatorKey = ref.watch(appNavigatorKeyProvider);
    return MaterialApp(
      navigatorKey: navigatorKey,
      title: '东方音乐电台 THMR',
      debugShowCheckedModeBanner: false,
      themeMode: mode,
      theme: light,
      darkTheme: dark,
      themeAnimationDuration: ThmrMotion.duration,
      themeAnimationCurve: ThmrMotion.enterCurve,
      // 所有路由共用一个背景。页面保持透明，切换标签页时背景插画的位置不变。
      //
      // Windows 迷你模式保留主界面的挂载状态和原尺寸，切回时可恢复标签页与滚动位置。
      builder: (context, child) {
        if (kIsWeb || !Platform.isWindows) {
          return AppInput(
              navigatorKey: navigatorKey,
              child: ThmrFocusLayer(
                  reserveEdgeSpace:
                      !ref.watch(largeScreenProvider.select((s) => s.active)),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      const ThmrBackground(child: SizedBox.expand()),
                      child ?? const SizedBox.expand(),
                    ],
                  )));
        }
        return AppInput(
            navigatorKey: navigatorKey,
            child: ThmrFocusLayer(
                reserveEdgeSpace: !ref.watch(miniPlayerProvider) &&
                    !ref.watch(largeScreenProvider.select((s) => s.active)),
                child: DesktopPlayerSurface(
                    child: child ?? const SizedBox.expand())));
      },
      home: const AppUpdateMonitor(child: HomeShell()),
    );
  }
}
