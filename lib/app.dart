import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/state/settings_provider.dart';
import 'core/theme/thmr_theme.dart';
import 'features/mini/mini_player.dart';
import 'features/shell/home_shell.dart';
import 'features/account/update_panel.dart';
import 'shared/widgets/desktop_title_bar.dart';
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
        final mini = ref.watch(miniPlayerProvider);
        final miniVisible = ref.watch(miniContentVisibleProvider);
        final saved = ref.watch(miniSavedBoundsProvider);
        final transition =
            MediaQuery.maybeOf(context)?.disableAnimations ?? false
                ? Duration.zero
                : const Duration(milliseconds: 180);
        return Stack(
          fit: StackFit.expand,
          children: [
            // 静态背景层:迷你模式下由迷你窗自带底色,插画不再绘制
            if (!mini) const ThmrBackground(child: SizedBox.expand()),
            // 主界面:两种模式下槽位结构一致,仅参数变化 → 状态不丢
            Padding(
              padding: mini ? EdgeInsets.zero : const EdgeInsets.only(top: 38),
              child: TickerMode(
                enabled: !mini,
                child: LayoutBuilder(builder: (context, constraints) {
                  final size = mini
                      ? (saved?.size ?? kMainMinWindowSize)
                      : constraints.biggest;
                  return Offstage(
                    offstage: mini,
                    child: OverflowBox(
                      alignment: Alignment.topLeft,
                      maxWidth: double.infinity,
                      maxHeight: double.infinity,
                      child: SizedBox.fromSize(
                        size: size,
                        child: child ?? const SizedBox.expand(),
                      ),
                    ),
                  );
                }),
              ),
            ),
            if (mini)
              IgnorePointer(
                ignoring: !miniVisible,
                child: AnimatedOpacity(
                  opacity: miniVisible ? 1 : 0,
                  duration: transition,
                  curve: Curves.easeOutCubic,
                  child: AnimatedScale(
                    scale: miniVisible ? 1 : 0.96,
                    duration: transition,
                    curve: Curves.easeOutCubic,
                    child: const MiniPlayerWindow(),
                  ),
                ),
              )
            else
              Align(
                alignment: Alignment.topCenter,
                child: DesktopTitleBar(
                  onMini: () =>
                      enterMiniMode(ref, MediaQuery.textScalerOf(context)),
                ),
              ),
          ],
        );
      },
      home: const AppUpdateMonitor(child: HomeShell()),
    );
  }
}
