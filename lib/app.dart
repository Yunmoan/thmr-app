import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/state/settings_provider.dart';
import 'core/input/app_input.dart';
import 'core/theme/thmr_theme.dart';
import 'core/theme/thmr_focus_ring.dart';
import 'features/mini/desktop_player_surface.dart';
import 'features/mini/mini_player.dart' show miniPlayerProvider;
import 'features/shell/home_shell.dart';
import 'features/account/update_panel.dart';
import 'shared/widgets/thmr_background.dart';

// Theme construction includes font resolution and the full Material theme.
// Keep it independent of playback, bitrate and other unrelated preferences.
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
      // Single shared background under every route: pages stay transparent
      // and the illustration never jumps between tabs.
      //
      // Windows mini mode keeps the shell mounted at its previous size so
      // tab and scroll state survive the swap.
      builder: (context, child) {
        if (kIsWeb || !Platform.isWindows) {
          return AppInput(
              navigatorKey: navigatorKey,
              child: ThmrFocusLayer(
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
                reserveEdgeSpace: !ref.watch(miniPlayerProvider),
                child: DesktopPlayerSurface(
                    child: child ?? const SizedBox.expand())));
      },
      home: const AppUpdateMonitor(child: HomeShell()),
    );
  }
}
