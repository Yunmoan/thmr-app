import 'package:flutter/material.dart';

import '../../core/state/large_screen_settings.dart';
import '../../core/theme/thmr_theme.dart';
import 'large_screen_music_visual.dart';

class LargeScreenMusicThumbnail extends StatelessWidget {
  const LargeScreenMusicThumbnail({
    super.key,
    required this.effect,
    required this.stageTheme,
  });

  final LargeScreenMusicEffect effect;
  final ThemeData stageTheme;

  @override
  Widget build(BuildContext context) {
    final tokens = stageTheme.thmr;
    return AspectRatio(
      aspectRatio: 180 / 80,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: Theme(
          data: stageTheme,
          child: ColoredBox(
            color: tokens.pageBg,
            child: switch (effect) {
              LargeScreenMusicEffect.off => Center(
                  child: Container(
                    width: 92,
                    height: 48,
                    decoration: BoxDecoration(
                      border: Border.all(
                          color: tokens.mutedInk.withValues(alpha: .42)),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Center(
                      child: Container(
                          width: 34,
                          height: 1.5,
                          color: tokens.mutedInk.withValues(alpha: .58)),
                    ),
                  ),
                ),
              _ => LargeScreenMusicVisual(
                  effect: effect,
                  intensity: 1,
                  lowPower: true,
                  playing: false,
                  source: null,
                  demo: true,
                ),
            },
          ),
        ),
      ),
    );
  }
}
