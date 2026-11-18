import 'dart:async';
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

/// Resolve the current cover once for both the flowing background and portrait.
class LargeScreenFluidArtwork extends StatefulWidget {
  const LargeScreenFluidArtwork({
    super.key,
    required this.artwork,
    required this.builder,
  });

  final ImageProvider<Object>? artwork;
  final Widget Function(BuildContext, FluidColors?) builder;

  @override
  State<LargeScreenFluidArtwork> createState() =>
      _LargeScreenFluidArtworkState();
}

class _LargeScreenFluidArtworkState extends State<LargeScreenFluidArtwork> {
  ImageProvider<Object>? _watchedArtwork;
  ({ImageStream stream, ImageStreamListener listener})? _load;
  FluidColors? _colors;
  int _revision = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _watchArtwork();
  }

  @override
  void didUpdateWidget(covariant LargeScreenFluidArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    _watchArtwork();
  }

  void _watchArtwork() {
    final artwork = widget.artwork;
    if (artwork == _watchedArtwork) return;
    _watchedArtwork = artwork;
    final revision = ++_revision;
    _detach();
    if (artwork == null) {
      _colors = null;
      return;
    }

    // Keep the previous colors while the new cover is loading.
    final stream = artwork.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener((info, _) {
      if (revision == _revision) _detach();
      unawaited(_sample(info, revision));
    }, onError: (Object _, StackTrace? __) {
      if (revision != _revision) return;
      _detach();
      // A provider may report a cached error during this build.
      scheduleMicrotask(() => _useColors(null, revision));
    });
    _load = (stream: stream, listener: listener);
    stream.addListener(listener);
  }

  Future<void> _sample(ImageInfo info, int revision) async {
    FluidColors? colors;
    try {
      colors = await fluidColorsFromArtwork(info.image);
    } catch (_) {
      // An unreadable thumbnail uses the same theme fallback as a missing one.
    } finally {
      info.dispose();
    }
    _useColors(colors, revision);
  }

  void _useColors(FluidColors? colors, int revision) {
    if (!mounted || revision != _revision || colors == _colors) return;
    setState(() => _colors = colors);
  }

  void _detach() {
    final load = _load;
    _load = null;
    load?.stream.removeListener(load.listener);
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(context, _colors);
}

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
      final chroma = (math.max(red, math.max(green, blue)) -
              math.min(red, math.min(green, blue))) /
          255;
      // A small area of pigment can define a cover with a large neutral field.
      final weight = alpha / 255 * (.10 + 4.8 * chroma * chroma);
      final region =
          (y * 2 < image.height ? 0 : 2) + (x * 2 < image.width ? 0 : 1);
      regions[region].add(red, green, blue, weight);
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
  Color tone(Color color, double lightnessOffset) {
    final hsl = HSLColor.fromColor(color);
    final lightness =
        dark ? .16 + .26 * hsl.lightness : .70 + .20 * hsl.lightness;
    final pigment = hsl
        .withSaturation((hsl.saturation * 1.27).clamp(0.0, 1.0))
        .withLightness((lightness + lightnessOffset).clamp(0.0, 1.0))
        .toColor();
    if (ThmrColors.contrast(pigment, theme.mutedInk) >= 4.5) return pigment;
    var high = 1.0;
    var low = 0.0;
    for (var i = 0; i < 10; i++) {
      final mid = (low + high) * .5;
      final candidate = Color.lerp(theme.pageBg, pigment, mid)!;
      if (ThmrColors.contrast(candidate, theme.mutedInk) >= 4.5) {
        low = mid;
      } else {
        high = mid;
      }
    }
    return Color.lerp(theme.pageBg, pigment, low)!;
  }

  return (
    topLeft: tone(palette.topLeft, .04),
    topRight: tone(palette.topRight, -.035),
    bottomLeft: tone(palette.bottomLeft, -.055),
    bottomRight: tone(palette.bottomRight, .018),
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
