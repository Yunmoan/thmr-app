import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/state/settings_provider.dart';
import 'core/theme/thmr_theme.dart';
import 'features/mini/desktop_player_surface.dart';
import 'features/shell/home_shell.dart';
import 'features/account/update_panel.dart';
import 'shared/widgets/thmr_background.dart';

class ThmrApp extends ConsumerWidget {
  const ThmrApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    return MaterialApp(
      title: '东方音乐电台 THMR',
      debugShowCheckedModeBanner: false,
      themeMode: settings.themeMode,
      theme: ThmrTheme.light(settings.accentTheme),
      darkTheme: ThmrTheme.dark(settings.accentTheme),
      // Single shared background under every route: pages stay transparent
      // and the illustration never jumps between tabs.
      //
      // Windows mini mode keeps the shell mounted at its previous size so
      // tab and scroll state survive the swap.
      builder: (context, child) {
        if (kIsWeb || !Platform.isWindows) {
          return Stack(
            fit: StackFit.expand,
            children: [
              const ThmrBackground(child: SizedBox.expand()),
              child ?? const SizedBox.expand(),
            ],
          );
        }
        return DesktopPlayerSurface(child: child ?? const SizedBox.expand());
      },
      home: const AppUpdateMonitor(child: HomeShell()),
    );
  }
}
