import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
        child: SvgPicture.asset(
          'assets/large_screen_effects/${effect.name}.svg',
          colorMapper: _ThumbnailColors(
            paper: tokens.pageBg,
            palette: musicPaletteFor(stageTheme, effect),
          ),
          excludeFromSemantics: true,
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _ThumbnailColors extends ColorMapper {
  const _ThumbnailColors({required this.paper, required this.palette});

  final Color paper;
  final LargeScreenMusicPalette palette;

  @override
  Color substitute(String? id, String element, String attribute, Color color) {
    // The assets also have a complete fallback palette when opened directly.
    final mapped = switch (color.toARGB32() & 0xffffff) {
      0x21171c => paper,
      0x643b4d => palette.shade,
      0xd17790 => palette.accent,
      0xffe0e7 => palette.highlight,
      _ => color,
    };
    return mapped.withValues(alpha: color.a);
  }

  @override
  bool operator ==(Object other) =>
      other is _ThumbnailColors &&
      paper == other.paper &&
      palette == other.palette;

  @override
  int get hashCode => Object.hash(paper, palette);
}
