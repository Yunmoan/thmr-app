import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/theme/thmr_colors.dart';

typedef FluidColors = ({
  Color topLeft,
  Color topRight,
  Color bottomLeft,
  Color bottomRight,
});

/// Read a small decoded cover once. Keeping four spatial averages preserves
/// the cover's distribution of color when the shader moves each region.
Future<FluidColors?> fluidColorsFromArtwork(ui.Image image) async {
  final bytes =
      await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
  if (bytes == null) return null;
  final regions = List.generate(4, (_) => _ColorAverage());
  final total = _ColorAverage();
  for (var y = 0; y < image.height; y++) {
    for (var x = 0; x < image.width; x++) {
      final offset = (y * image.width + x) * 4;
      final alpha = bytes.getUint8(offset + 3);
      if (alpha == 0) continue;
      final red = bytes.getUint8(offset);
      final green = bytes.getUint8(offset + 1);
      final blue = bytes.getUint8(offset + 2);
      final chroma = math.max(red, math.max(green, blue)) -
          math.min(red, math.min(green, blue));
      // Favor the cover's pigments over neutral paper and text.
      final weight = alpha / 255 * (.5 + chroma / 255);
      final r = (y * 2 < image.height ? 0 : 2) + (x * 2 < image.width ? 0 : 1);
      regions[r].add(red, green, blue, weight);
      total.add(red, green, blue, weight);
    }
  }
  final average = total.color;
  if (average == null) return null;
  return (
    topLeft: regions[0].color ?? average,
    topRight: regions[1].color ?? average,
    bottomLeft: regions[2].color ?? average,
    bottomRight: regions[3].color ?? average,
  );
}

/// Tint cover pigments toward the reading surface. Limit strong swatches by
/// the same secondary text color used for the track details and widgets.
FluidColors toneFluidColors(FluidColors palette, ThmrTokens theme, bool dark) {
  Color tone(Color color) {
    var high = dark ? .64 : .42;
    final mixed = Color.lerp(theme.pageBg, color, high)!;
    if (ThmrColors.contrast(mixed, theme.mutedInk) >= 4.5) return mixed;
    var low = 0.0;
    for (var i = 0; i < 10; i++) {
      final mid = (low + high) * .5;
      final candidate = Color.lerp(theme.pageBg, color, mid)!;
      if (ThmrColors.contrast(candidate, theme.mutedInk) >= 4.5) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return Color.lerp(theme.pageBg, color, low)!;
  }

  return (
    topLeft: tone(palette.topLeft),
    topRight: tone(palette.topRight),
    bottomLeft: tone(palette.bottomLeft),
    bottomRight: tone(palette.bottomRight),
  );
}

class _ColorAverage {
  double _red = 0, _green = 0, _blue = 0, _weight = 0;

  void add(int red, int green, int blue, double weight) {
    _red += red * weight;
    _green += green * weight;
    _blue += blue * weight;
    _weight += weight;
  }

  Color? get color => _weight == 0
      ? null
      : Color.fromARGB(255, (_red / _weight).round(),
          (_green / _weight).round(), (_blue / _weight).round());
}
