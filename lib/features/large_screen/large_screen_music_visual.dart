import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show FragmentProgram, FragmentShader;

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

  @override
  void paint(Canvas canvas, Size size) {
    if (motion.isSilent || size.isEmpty) return;
    final shader = this.shader;
    if (shader == null) {
      _paintPrism(canvas, size);
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

  // Draw narrow paths and ordinary gradients. The rest of the screen needs no
  // custom shader, blur pass or intermediate surface for this style.
  void _paintPrism(Canvas canvas, Size size) {
    final energy = motion.energy;
    final peak = math.max(energy.bass, math.max(energy.mids, energy.treble));
    final opacity =
        Curves.easeOut.transform((peak / .38).clamp(0, 1)) * intensity;
    final scale = size.shortestSide;
    final blue = Color.lerp(
        accent, dark ? const Color(0xff9cd5ff) : const Color(0xff466bb7), .78)!;
    final pink = Color.lerp(
        accent, dark ? const Color(0xfff6abd8) : const Color(0xffb050a1), .65)!;
    final stroke = Paint()
      ..style = PaintingStyle.stroke
      ..strokeJoin = StrokeJoin.round;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(size.width * .54, size.height * .52);
    canvas.rotate(-.29);

    for (var ring = 2; ring >= 0; ring--) {
      final spin = motion.time * (.24 - ring * .048) + ring * 1.93;
      final radius = scale *
          (.22 + ring * .146 + energy.bass * .048 + motion.pulse * .058);
      final width = scale * (.012 + .012 * energy.bass + .006 * motion.pulse);
      final bend = scale * (.021 + .023 * energy.mids);
      final path = Path();
      const segments = 72;
      for (var segment = 0; segment < segments; segment++) {
        final angle = segment * 2 * math.pi / segments;
        final distance = radius +
            bend *
                (math.sin(angle * 3 - spin) + .41 * math.cos(angle * 5 + spin));
        final x = math.cos(angle) * distance;
        final y = math.sin(angle) * distance * .76;
        if (segment == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      path.close();
      final visibility = opacity * (1 - ring * .16);
      stroke
        ..shader = null
        ..color = blue.withValues(alpha: .12 * visibility)
        ..strokeWidth = width * 1.75;
      canvas.drawPath(path, stroke);

      stroke
        ..color = const Color(0xffffffff)
        ..shader = SweepGradient(
          transform: GradientRotation(spin),
          colors: [
            blue.withValues(alpha: .07 * visibility),
            blue.withValues(alpha: .68 * visibility),
            accent.withValues(alpha: .30 * visibility),
            pink.withValues(alpha: .09 * visibility),
            pink.withValues(alpha: .74 * visibility),
            blue.withValues(alpha: .07 * visibility),
          ],
          stops: const [0, .16, .31, .55, .78, 1],
        ).createShader(Rect.fromCircle(center: Offset.zero, radius: radius))
        ..strokeWidth = width;
      canvas.drawPath(path, stroke);

      // A thin offset reflection gives the colored band a beveled edge.
      stroke
        ..shader = null
        ..color =
            pink.withValues(alpha: (.12 + .25 * energy.treble) * visibility)
        ..strokeWidth = math.max(.8, scale * .0016);
      canvas.drawPath(path.shift(Offset(-width * .45, width * .4)), stroke);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MusicVisualPainter oldDelegate) =>
      effect != oldDelegate.effect ||
      intensity != oldDelegate.intensity ||
      dark != oldDelegate.dark ||
      accent != oldDelegate.accent;
}
