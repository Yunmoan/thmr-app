import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui'
    show FragmentProgram, FragmentShader, PointMode, VertexMode, Vertices;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/player/spectrum.dart';
import '../../core/state/large_screen_settings.dart';
import '../../core/theme/thmr_theme.dart';
import 'large_screen_fluid_colors.dart';

const _spectrumBandCount = 96;

typedef LargeScreenMusicPalette = ({
  Color accent,
  Color shade,
  Color highlight
});

LargeScreenMusicPalette musicPaletteFor(
    ThemeData theme, LargeScreenMusicEffect effect) {
  final tokens = theme.thmr;
  final dark = theme.brightness == Brightness.dark;
  var shade = Color.lerp(tokens.accent, tokens.supportInk, .42)!;
  if (effect == LargeScreenMusicEffect.fluid) {
    final pigment = HSLColor.fromColor(tokens.accent);
    shade = pigment
        .withHue((pigment.hue + 48) % 360)
        .withSaturation((pigment.saturation * .8 + .10).clamp(0, 1))
        .withLightness(dark ? .54 : .61)
        .toColor();
  }
  return (
    accent: tokens.accent,
    shade: shade,
    highlight: Color.lerp(
        tokens.accent, dark ? tokens.ink : tokens.codeInk, dark ? .62 : .25)!,
  );
}

class LargeScreenMusicVisual extends StatefulWidget {
  const LargeScreenMusicVisual({
    super.key,
    required this.effect,
    required this.intensity,
    required this.lowPower,
    required this.playing,
    required this.source,
    this.artwork,
    this.fluidMotion = LargeScreenFluidMotion.automatic,
    this.demo = false,
  });

  final LargeScreenMusicEffect effect;
  final double intensity;
  final bool lowPower;
  final bool playing;
  final SpectrumSource? source;
  final ImageProvider<Object>? artwork;
  final LargeScreenFluidMotion fluidMotion;
  final bool demo;

  @override
  State<LargeScreenMusicVisual> createState() => _LargeScreenMusicVisualState();
}

class _LargeScreenMusicVisualState extends State<LargeScreenMusicVisual>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _bandCount = 48;
  static const _demoDuration = Duration(milliseconds: 4800);

  final _motion = _MusicMotion();
  late final _sampleBands = Float32List(_spectrumBandCount);
  late final Ticker _ticker = createTicker(_tick);
  FragmentShader? _shader;
  SpectrumSource? _capture;
  Duration _lastTick = Duration.zero;
  bool _allowsMotion = false;
  bool _shaderRequested = false;
  bool _demoFinished = false;
  ImageProvider<Object>? _watchedArtwork;
  ({ImageStream stream, ImageStreamListener listener})? _artworkLoad;
  FluidColors? _artworkColors;
  int _artworkRevision = 0;

  bool get _isFluid => widget.effect == LargeScreenMusicEffect.fluid;

  bool get _usesShader => switch (widget.effect) {
        LargeScreenMusicEffect.aurora ||
        LargeScreenMusicEffect.nebula ||
        LargeScreenMusicEffect.fluid =>
          true,
        LargeScreenMusicEffect.off ||
        LargeScreenMusicEffect.prism ||
        LargeScreenMusicEffect.spectrum =>
          false,
      };

  bool get _visible {
    final state = WidgetsBinding.instance.lifecycleState;
    if (state == null || state == AppLifecycleState.resumed) return true;
    // A desktop window can still be visible while another window has focus.
    return state == AppLifecycleState.inactive &&
        switch (defaultTargetPlatform) {
          TargetPlatform.windows ||
          TargetPlatform.linux ||
          TargetPlatform.macOS =>
            true,
          _ => false,
        };
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  void _loadShaderIfNeeded() {
    if (!_usesShader || _shaderRequested) return;
    _shaderRequested = true;
    unawaited(_prepareShader());
  }

  Future<void> _prepareShader() async {
    try {
      final program =
          await FragmentProgram.fromAsset('shaders/large_screen_music.frag');
      if (!mounted) return;
      setState(() => _shader = program.fragmentShader());
      _sync();
    } catch (error) {
      debugPrint('Large screen music shader unavailable: $error');
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final tickersEnabled = TickerMode.valuesOf(context).enabled;
    _allowsMotion = tickersEnabled && !MediaQuery.disableAnimationsOf(context);
    _watchArtwork();
    _refreshFluidColors();
    _sync();
  }

  @override
  void didUpdateWidget(covariant LargeScreenMusicVisual oldWidget) {
    super.didUpdateWidget(oldWidget);
    final effectChanged = widget.effect != oldWidget.effect;
    if (effectChanged) _motion.clear();
    if (effectChanged || widget.artwork != oldWidget.artwork) {
      _watchArtwork();
      _refreshFluidColors();
    }
    if (widget.demo &&
        (!oldWidget.demo ||
            effectChanged ||
            (_isFluid && widget.fluidMotion != oldWidget.fluidMotion))) {
      _demoFinished = false;
      _ticker.stop();
    }
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _sync();

  void _watchArtwork() {
    final artwork = _isFluid ? widget.artwork : null;
    if (artwork == _watchedArtwork) return;
    final revision = ++_artworkRevision;
    _detachArtwork();
    _watchedArtwork = artwork;
    if (artwork == null) {
      _artworkColors = null;
      return;
    }

    // Keep the previous colors while the new cover is loading.
    final stream = artwork.resolve(createLocalImageConfiguration(context));
    final listener = ImageStreamListener((info, _) {
      if (revision == _artworkRevision) _detachArtwork();
      unawaited(_sampleArtwork(info, revision));
    }, onError: (Object _, StackTrace? __) {
      if (revision != _artworkRevision) return;
      _detachArtwork();
      _useArtwork(null, revision);
    });
    _artworkLoad = (stream: stream, listener: listener);
    stream.addListener(listener);
  }

  void _detachArtwork() {
    final load = _artworkLoad;
    _artworkLoad = null;
    load?.stream.removeListener(load.listener);
  }

  Future<void> _sampleArtwork(ImageInfo info, int revision) async {
    FluidColors? colors;
    try {
      colors = await fluidColorsFromArtwork(info.image);
    } catch (_) {
      // An unreadable thumbnail uses the same theme fallback as a missing one.
    } finally {
      info.dispose();
    }
    _useArtwork(colors, revision);
  }

  void _useArtwork(FluidColors? colors, int revision) {
    if (!mounted || revision != _artworkRevision) return;
    _artworkColors = colors;
    _refreshFluidColors();
    _sync();
  }

  void _refreshFluidColors() {
    if (!_isFluid) return;
    final theme = Theme.of(context);
    final palette = musicPaletteFor(theme, widget.effect);
    final colors = _artworkColors ??
        (
          topLeft: palette.highlight,
          topRight: palette.shade,
          bottomLeft: palette.accent,
          bottomRight: theme.thmr.pageBg,
        );
    _motion.setFluidColors(
        toneFluidColors(
            colors, theme.thmr, theme.brightness == Brightness.dark),
        animate: _allowsMotion && _visible);
  }

  bool get _hasPendingFrame {
    if (_isFluid &&
        (_motion.blendingColors || (!widget.demo && widget.playing))) {
      return true;
    }
    return widget.demo ? !_demoFinished : _capture != null || !_motion.isSilent;
  }

  void _sync() {
    final visible = _allowsMotion && _visible;
    final source = !widget.demo && widget.playing ? widget.source : null;
    if (_isFluid || (visible && (widget.demo || source != null))) {
      _loadShaderIfNeeded();
    }
    final canAnimate = visible && (!_usesShader || _shader != null);
    final capture = canAnimate ? source : null;
    if (!identical(capture, _capture)) {
      _capture?.stop();
      _capture = capture;
      _capture?.start();
    }
    if (!canAnimate) {
      _motion.clear();
      _demoFinished = false;
    }
    if (!visible) _motion.finishColorBlend();
    if (!canAnimate || !_hasPendingFrame) {
      _ticker.stop();
    } else if (!_ticker.isActive) {
      _lastTick = Duration.zero;
      _ticker.start();
    }
  }

  void _tick(Duration elapsed) {
    final delta = elapsed - _lastTick;
    final interval = Duration(milliseconds: widget.lowPower ? 64 : 32);
    if (delta < interval) return;
    _lastTick = elapsed;
    final seconds = math.min(delta.inMicroseconds / 1e6, .08);
    final showBands = widget.effect == LargeScreenMusicEffect.spectrum;
    final bands = _capture?.poll(showBands ? _spectrumBandCount : _bandCount);
    if (showBands) {
      _motion.updateSpectrum(
          widget.demo ? _demoSpectrum(elapsed, _demoEnergy(elapsed)) : bands,
          seconds);
    } else {
      _motion.advance(
        widget.demo && !_demoFinished
            ? _demoEnergy(elapsed)
            : _measureEnergy(bands),
        seconds,
        widget.intensity,
        fluid: _isFluid,
        flowing: _isFluid && (widget.demo ? !_demoFinished : widget.playing),
      );
    }
    if (widget.demo && elapsed >= _demoDuration) _demoFinished = true;
    if (!_hasPendingFrame) _ticker.stop();
  }

  _Energy _measureEnergy(Float32List? data) {
    if (data == null) return _silence;
    final lowEnd = data.length * 11 ~/ _bandCount;
    final midEnd = data.length * 32 ~/ _bandCount;
    return (
      bass: _level(data, 0, lowEnd),
      mids: _level(data, lowEnd, midEnd),
      treble: _level(data, midEnd, data.length),
    );
  }

  // A short pattern for settings previews, with no capture or audio playback.
  _Energy _demoEnergy(Duration elapsed) {
    final t = elapsed.inMicroseconds / 1e6;
    return (
      bass: .26 + .57 * math.exp(-6.4 * ((t / .6) % 1)),
      mids: .44 + .15 * math.sin(t * 3.6),
      treble: .13 + .44 * math.exp(-5.2 * ((t / .3 + .4) % 1)),
    );
  }

  Float32List _demoSpectrum(Duration elapsed, _Energy energy) {
    final seconds = elapsed.inMicroseconds / 1e6;
    for (var i = 0; i < _sampleBands.length; i++) {
      final x = i / (_sampleBands.length - 1);
      final bass = energy.bass * math.exp(-5.0 * x);
      final mids = energy.mids * math.exp(-4.0 * (x - .32) * (x - .32));
      final highs = energy.treble * x;
      final peaks = (.5 + .5 * math.cos(x * 49 + seconds * 2.0)) *
          (.60 + .4 * math.cos(x * 93 - seconds * 1.2));
      _sampleBands[i] = (bass * .8 + (mids + highs) * peaks).clamp(0.0, 1.0);
    }
    return _sampleBands;
  }

  // The source returns logarithmic bands. RMS lets a strong kick or cymbal
  // register without giving a single isolated FFT bin the whole visual range.
  double _level(Float32List bands, int first, int end) {
    var squares = 0.0;
    for (var i = first; i < end; i++) {
      final value = bands[i];
      squares += value * value;
    }
    final level = math.sqrt(squares / (end - first));
    return level < .025 ? 0 : level;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _detachArtwork();
    _ticker.dispose();
    _capture?.stop();
    _shader?.dispose();
    _motion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shader = _shader;
    if (_usesShader && shader == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return IgnorePointer(
      child: RepaintBoundary(
        child: CustomPaint(
          willChange: true,
          painter: _MusicVisualPainter(
            shader: _usesShader ? shader : null,
            motion: _motion,
            effect: widget.effect,
            intensity: widget.intensity,
            dark: theme.brightness == Brightness.dark,
            palette: musicPaletteFor(theme, widget.effect),
            paper: theme.thmr.pageBg,
            fluidMotion: widget.fluidMotion,
          ),
        ),
      ),
    );
  }
}

typedef _Energy = ({double bass, double mids, double treble});
const _Energy _silence = (bass: 0, mids: 0, treble: 0);

class _MusicMotion extends ChangeNotifier {
  final spectrum = Float32List(_spectrumBandCount);
  _Energy energy = _silence;
  double time = 0;
  double pulse = 0;
  double _bassFloor = 0;
  bool _hasSpectrum = false;
  FluidColors? _fluidFrom, _fluidTo;
  double _colorBlend = 1;

  bool get isSilent => energy == _silence && !_hasSpectrum;
  bool get blendingColors => _colorBlend < 1;

  FluidColors? get fluidColors {
    final to = _fluidTo;
    if (to == null || !blendingColors) return to;
    final from = _fluidFrom!;
    final t = Curves.easeInOut.transform(_colorBlend);
    return (
      topLeft: Color.lerp(from.topLeft, to.topLeft, t)!,
      topRight: Color.lerp(from.topRight, to.topRight, t)!,
      bottomLeft: Color.lerp(from.bottomLeft, to.bottomLeft, t)!,
      bottomRight: Color.lerp(from.bottomRight, to.bottomRight, t)!,
    );
  }

  void setFluidColors(FluidColors palette, {required bool animate}) {
    if (palette == _fluidTo) return;
    _fluidFrom = animate ? fluidColors : null;
    _fluidTo = palette;
    _colorBlend = _fluidFrom == null ? 1 : 0;
    notifyListeners();
  }

  void finishColorBlend() {
    if (!blendingColors) return;
    _colorBlend = 1;
    _fluidFrom = null;
    notifyListeners();
  }

  void updateSpectrum(Float32List? bands, double seconds) {
    final attack = 1 - math.exp(-seconds / .035);
    final decay = 1 - math.exp(-seconds / .16);
    var hasSpectrum = false;
    var changed = false;
    for (var i = 0; i < spectrum.length; i++) {
      final sample = bands?[i] ?? 0.0;
      final next = sample < .02 ? 0.0 : sample;
      final current = spectrum[i];
      final value =
          current + (next - current) * (next > current ? attack : decay);
      spectrum[i] = value < .005 ? 0 : value;
      hasSpectrum = hasSpectrum || spectrum[i] > 0;
      changed = changed || spectrum[i] != current;
    }
    _hasSpectrum = hasSpectrum;
    if (changed) notifyListeners();
  }

  void advance(_Energy target, double seconds, double intensity,
      {required bool fluid, required bool flowing}) {
    final changeColors = fluid && blendingColors;
    if (isSilent && target == _silence && !flowing && !changeColors) return;
    energy = (
      bass: _ease(energy.bass, target.bass, seconds, .055, .23),
      mids: _ease(energy.mids, target.mids, seconds, .10, .26),
      treble: _ease(energy.treble, target.treble, seconds, .045, .18),
    );
    // Smooth against a slower moving bass floor so accents punch through
    // without making a sustained bass note look like a constant beat.
    final transient = ((target.bass - _bassFloor - .035) * 3.4).clamp(0.0, 1.0);
    _bassFloor = _ease(_bassFloor, target.bass, seconds, .84, .46);
    pulse = _ease(pulse, transient, seconds, .045, .22);
    if (flowing) {
      time += seconds * (.86 + .41 * energy.mids + .13 * pulse);
    } else if (!fluid && target != _silence) {
      time += seconds *
          (.28 + .92 * energy.mids + .27 * energy.treble) *
          (.48 + .52 * intensity);
    }
    if (changeColors) _colorBlend = math.min(1, _colorBlend + seconds / .94);
    if (isSilent) pulse = _bassFloor = 0;
    notifyListeners();
  }

  void clear() {
    if (isSilent) return;
    energy = _silence;
    pulse = _bassFloor = 0;
    if (_hasSpectrum) spectrum.fillRange(0, spectrum.length, 0);
    _hasSpectrum = false;
    notifyListeners();
  }

  double _ease(
      double from, double to, double dt, double attack, double release) {
    final offset = (from - to) * math.exp(-dt / (to > from ? attack : release));
    return offset.abs() < .002 ? to : to + offset;
  }
}

class _MusicVisualPainter extends CustomPainter {
  _MusicVisualPainter({
    required this.shader,
    required this.motion,
    required this.effect,
    required this.intensity,
    required this.dark,
    required this.palette,
    required this.paper,
    required this.fluidMotion,
  }) : super(repaint: motion);

  final FragmentShader? shader;
  final _MusicMotion motion;
  final LargeScreenMusicEffect effect;
  final double intensity;
  final bool dark;
  final LargeScreenMusicPalette palette;
  final Color paper;
  final LargeScreenFluidMotion fluidMotion;
  late final _prism = _PrismMesh(palette);
  late final _spectrum = _MirroredSpectrum(palette, intensity);
  final _shaderPaint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty ||
        (motion.isSilent && effect != LargeScreenMusicEffect.fluid)) {
      return;
    }
    switch (effect) {
      case LargeScreenMusicEffect.off:
        return;
      case LargeScreenMusicEffect.prism:
        _prism.paint(canvas, size, motion, intensity);
      case LargeScreenMusicEffect.spectrum:
        _spectrum.paint(canvas, size, motion.spectrum);
      case LargeScreenMusicEffect.aurora:
        _paintShader(canvas, size, 1);
      case LargeScreenMusicEffect.nebula:
        _paintShader(canvas, size, 2);
      case LargeScreenMusicEffect.fluid:
        _paintShader(canvas, size, 3);
    }
  }

  void _paintShader(Canvas canvas, Size size, double style) {
    final shader = this.shader!;
    // Uniform order matches shaders/large_screen_music.frag.
    shader
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, motion.time)
      ..setFloat(3, intensity)
      ..setFloat(4, motion.energy.bass)
      ..setFloat(5, motion.energy.mids)
      ..setFloat(6, motion.energy.treble)
      ..setFloat(7, motion.pulse)
      ..setFloat(17, dark ? 1 : 0)
      ..setFloat(18, style);
    _setShaderColor(shader, 8, palette.accent);
    _setShaderColor(shader, 11, palette.shade);
    _setShaderColor(shader, 14, palette.highlight);
    if (effect == LargeScreenMusicEffect.fluid) {
      final colors = motion.fluidColors!;
      _setShaderColor(shader, 19, colors.topLeft);
      _setShaderColor(shader, 22, colors.topRight);
      _setShaderColor(shader, 25, colors.bottomLeft);
      _setShaderColor(shader, 28, colors.bottomRight);
      _setShaderColor(shader, 31, paper);
      final (drift, orbit, tide) = _fluidWeights();
      shader
        ..setFloat(34, drift)
        ..setFloat(35, orbit)
        ..setFloat(36, tide);
    }
    canvas.drawRect(Offset.zero & size, _shaderPaint..shader = shader);
  }

  (double, double, double) _fluidWeights() {
    if (fluidMotion == LargeScreenFluidMotion.automatic) {
      final phase = (motion.time / 8) % 3;
      final section = phase.floor();
      final t = Curves.easeInOut.transform(phase - section);
      return switch (section) {
        0 => (1 - t, t, 0),
        1 => (0, 1 - t, t),
        _ => (t, 0, 1 - t),
      };
    }
    return (
      fluidMotion == LargeScreenFluidMotion.drift ? 1 : 0,
      fluidMotion == LargeScreenFluidMotion.orbit ? 1 : 0,
      fluidMotion == LargeScreenFluidMotion.tide ? 1 : 0,
    );
  }

  void _setShaderColor(FragmentShader shader, int offset, Color color) {
    shader
      ..setFloat(offset, color.r)
      ..setFloat(offset + 1, color.g)
      ..setFloat(offset + 2, color.b);
  }

  @override
  bool shouldRepaint(_MusicVisualPainter oldDelegate) =>
      effect != oldDelegate.effect ||
      intensity != oldDelegate.intensity ||
      dark != oldDelegate.dark ||
      palette != oldDelegate.palette ||
      paper != oldDelegate.paper ||
      fluidMotion != oldDelegate.fluidMotion;
}

/// Symmetric bars use the individual FFT bands, in rising frequency order.
/// Interpolating the rows of thin strokes keeps the spacing on large displays.
class _MirroredSpectrum {
  _MirroredSpectrum(this.palette, this.intensity);

  final LargeScreenMusicPalette palette;
  final double intensity;
  final _paint = Paint();
  Size? _size;
  late Float32List _lines;

  void paint(Canvas canvas, Size size, Float32List bands) {
    if (_size != size) {
      _size = size;
      final count = (size.width / 4.6).round().clamp(48, 480);
      _lines = Float32List(count * 4);
      final spacing = size.width / count;
      for (var i = 0; i < count; i++) {
        _lines[i * 4] = _lines[i * 4 + 2] = (i + .5) * spacing;
      }
      _paint
        ..strokeWidth = (spacing * .35).clamp(1, 2.6)
        ..shader = LinearGradient(colors: [
          palette.accent.withValues(alpha: intensity),
          palette.highlight.withValues(alpha: intensity * .82),
          palette.accent.withValues(alpha: intensity * .9),
        ]).createShader(Offset.zero & size);
    }

    final count = _lines.length ~/ 4;
    final center = size.height * .5;
    final extent = size.height * .46 * (.4 + .6 * intensity);
    final lastBand = bands.length - 1;
    for (var i = 0; i < count; i++) {
      final band = i * lastBand / (count - 1);
      final low = band.toInt();
      final high = math.min(low + 1, lastBand);
      final level = bands[low] + (bands[high] - bands[low]) * (band - low);
      final height = level * math.sqrt(level) * extent;
      _lines[i * 4 + 1] = center - height;
      _lines[i * 4 + 3] = center + height;
    }
    canvas.drawRawPoints(PointMode.lines, _lines, _paint);
  }
}

/// Draw the glass rims as one mesh with soft, colored edges. The topology stays
/// fixed, so the raster thread can skip path tessellation and draw only the rims.
class _PrismMesh {
  _PrismMesh(this.palette);

  static const _rings = 3;
  static const _segments = 96;
  static const _bevel = [
    (offset: -1.25, alpha: .0),
    (offset: -.52, alpha: .32),
    (offset: -.30, alpha: .88),
    (offset: .16, alpha: .60),
    (offset: .70, alpha: .18),
    (offset: 1.25, alpha: .0),
  ];
  static final _ringVertices = _segments * _bevel.length;
  static final _angles =
      List.generate(_segments, (i) => i * 2 * math.pi / _segments);
  static final _directions =
      _angles.map((a) => Offset(math.cos(a), math.sin(a) * .76)).toList();
  static final _indices = _buildIndices();

  final _positions = Float32List(_rings * _ringVertices * 2);
  final _colors = Int32List(_rings * _ringVertices);
  final _paint = Paint()..isAntiAlias = false;
  final LargeScreenMusicPalette palette;

  static Uint16List _buildIndices() {
    final strips = _bevel.length - 1;
    final indices = Uint16List(_rings * _segments * strips * 6);
    var index = 0;
    for (var ring = 0; ring < _rings; ring++) {
      final start = ring * _ringVertices;
      for (var segment = 0; segment < _segments; segment++) {
        final left = start + segment * _bevel.length;
        final right = start + (segment + 1) % _segments * _bevel.length;
        for (var lane = 0; lane < strips; lane++) {
          // Two triangles connect adjacent radial strips.
          indices[index++] = left + lane;
          indices[index++] = right + lane;
          indices[index++] = left + lane + 1;
          indices[index++] = left + lane + 1;
          indices[index++] = right + lane;
          indices[index++] = right + lane + 1;
        }
      }
    }
    return indices;
  }

  void paint(Canvas canvas, Size size, _MusicMotion motion, double intensity) {
    final energy = motion.energy;
    final peak = math.max(energy.bass, math.max(energy.mids, energy.treble));
    final opacity =
        Curves.easeOut.transform((peak / .38).clamp(0, 1)) * intensity;
    final scale = size.shortestSide;
    final pulse = energy.bass * .048 + motion.pulse * .058;
    final width = scale * (.011 + .012 * energy.bass + .006 * motion.pulse);
    final bend = scale * (.021 + .023 * energy.mids);
    var vertex = 0;
    for (var ring = 0; ring < _rings; ring++) {
      final spin = motion.time * (.34 - ring * .061) + ring * 1.93;
      final radius = scale * (.22 + ring * .146 + pulse);
      final visibility = opacity * (1 - ring * .14);
      for (var segment = 0; segment < _segments; segment++) {
        final angle = _angles[segment];
        final axis = _directions[segment];
        final distance = radius +
            bend *
                (math.sin(angle * 3 - spin) + .41 * math.cos(angle * 5 + spin));
        final sweep = .5 + .5 * math.cos(angle * 2 + spin);
        final alpha = 255 * visibility * (.15 + .85 * sweep * sweep);
        final hue = .5 + .5 * math.sin(angle * 2 - spin * .7);
        final tint = Color.lerp(palette.shade, palette.accent, hue)!;
        final rgb = tint.toARGB32() & 0xffffff;
        final reflection =
            Color.lerp(tint, palette.highlight, .34 + .42 * energy.treble)!
                    .toARGB32() &
                0xffffff;
        for (final face in _bevel) {
          final r = distance + width * face.offset;
          _positions[vertex * 2] = axis.dx * r;
          _positions[vertex * 2 + 1] = axis.dy * r;
          final color = face.alpha > .8 ? reflection : rgb;
          _colors[vertex++] = ((alpha * face.alpha).round() << 24) | color;
        }
      }
    }

    final mesh = Vertices.raw(VertexMode.triangles, _positions,
        indices: _indices, colors: _colors);
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(size.width * .54, size.height * .52);
    canvas.rotate(-.29);
    canvas.drawVertices(mesh, BlendMode.dst, _paint);
    canvas.restore();
    mesh.dispose();
  }
}
