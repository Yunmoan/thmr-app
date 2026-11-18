import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show FragmentProgram, FragmentShader, VertexMode, Vertices;

import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../core/player/spectrum.dart';
import '../../core/state/large_screen_settings.dart';

class LargeScreenMusicVisual extends StatefulWidget {
  const LargeScreenMusicVisual({
    super.key,
    required this.effect,
    required this.intensity,
    required this.lowPower,
    required this.playing,
    required this.source,
    this.demo = false,
  });

  final LargeScreenMusicEffect effect;
  final double intensity;
  final bool lowPower;
  final bool playing;
  final SpectrumSource? source;
  final bool demo;

  @override
  State<LargeScreenMusicVisual> createState() => _LargeScreenMusicVisualState();
}

class _LargeScreenMusicVisualState extends State<LargeScreenMusicVisual>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const _bandCount = 48;
  static const _demoDuration = Duration(milliseconds: 4800);

  final _motion = _MusicMotion();
  late final Ticker _ticker = createTicker(_tick);
  FragmentShader? _shader;
  SpectrumSource? _capture;
  Duration _lastTick = Duration.zero;
  bool _allowsMotion = false;
  bool _shaderRequested = false;
  bool _demoFinished = false;

  bool get _usesShader => widget.effect != LargeScreenMusicEffect.prism;

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
    _sync();
  }

  @override
  void didUpdateWidget(covariant LargeScreenMusicVisual oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.demo && (!oldWidget.demo || widget.effect != oldWidget.effect)) {
      _demoFinished = false;
      _ticker.stop();
    }
    _sync();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => _sync();

  void _sync() {
    final visible = _allowsMotion && _visible;
    final source = !widget.demo && widget.playing ? widget.source : null;
    if (visible && (widget.demo || source != null)) _loadShaderIfNeeded();
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
    final shouldTick =
        widget.demo ? !_demoFinished : _capture != null || !_motion.isSilent;
    if (!canAnimate || !shouldTick) {
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
    final energy = widget.demo ? _demoEnergy(elapsed) : _liveEnergy();
    final seconds = math.min(delta.inMicroseconds / 1e6, .08);
    _motion.advance(energy, seconds, widget.intensity);
    if (widget.demo) {
      _demoFinished = elapsed >= _demoDuration;
      if (_demoFinished) _ticker.stop();
    } else if (_capture == null && _motion.isSilent) {
      _ticker.stop();
    }
  }

  _Energy _liveEnergy() {
    final data = _capture?.poll(_bandCount);
    if (data == null) return _silence;
    return (
      bass: _level(data, 0, 11),
      mids: _level(data, 11, 32),
      treble: _level(data, 32, _bandCount),
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
            accent: theme.colorScheme.primary,
          ),
        ),
      ),
    );
  }
}

typedef _Energy = ({double bass, double mids, double treble});
const _Energy _silence = (bass: 0, mids: 0, treble: 0);

class _MusicMotion extends ChangeNotifier {
  _Energy energy = _silence;
  double time = 0;
  double pulse = 0;
  double _bassFloor = 0;

  bool get isSilent => energy == _silence;

  void advance(_Energy target, double seconds, double intensity) {
    if (isSilent && target == _silence) return;
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
    if (target != _silence) {
      time += seconds *
          (.28 + .92 * energy.mids + .27 * energy.treble) *
          (.48 + .52 * intensity);
    }
    if (isSilent) pulse = _bassFloor = 0;
    notifyListeners();
  }

  void clear() {
    if (isSilent) return;
    energy = _silence;
    pulse = _bassFloor = 0;
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
    required this.accent,
  }) : super(repaint: motion);

  final FragmentShader? shader;
  final _MusicMotion motion;
  final LargeScreenMusicEffect effect;
  final double intensity;
  final bool dark;
  final Color accent;
  late final _prism = _PrismMesh(accent, dark);

  @override
  void paint(Canvas canvas, Size size) {
    if (motion.isSilent || size.isEmpty) return;
    final shader = this.shader;
    if (shader == null) {
      _prism.paint(canvas, size, motion, intensity);
      return;
    }
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
      ..setFloat(8, accent.r)
      ..setFloat(9, accent.g)
      ..setFloat(10, accent.b)
      ..setFloat(11, dark ? 1 : 0)
      ..setFloat(12, effect == LargeScreenMusicEffect.aurora ? 1 : 2);
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  @override
  bool shouldRepaint(_MusicVisualPainter oldDelegate) =>
      effect != oldDelegate.effect ||
      intensity != oldDelegate.intensity ||
      dark != oldDelegate.dark ||
      accent != oldDelegate.accent;
}

/// Draw the glass rims as one mesh with soft, colored edges. The topology stays
/// fixed, so the raster thread can skip path tessellation and draw only the rims.
class _PrismMesh {
  _PrismMesh(Color accent, bool dark)
      : _blue = Color.lerp(accent,
            dark ? const Color(0xff9cd5ff) : const Color(0xff466bb7), .78)!,
        _rose = Color.lerp(accent,
            dark ? const Color(0xfff6abd8) : const Color(0xffb050a1), .65)!,
        _glint = dark ? const Color(0xffd7e9ff) : const Color(0xff605599);

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
  final Color _blue, _rose, _glint;

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
        final tint = Color.lerp(_blue, _rose, hue)!;
        final rgb = tint.toARGB32() & 0xffffff;
        final reflection =
            Color.lerp(tint, _glint, .28 + .35 * energy.treble)!.toARGB32() &
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
