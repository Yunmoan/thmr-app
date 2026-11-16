import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/thmr_focus_ring.dart';

/// A slider that paints and describes itself.
///
/// Material's Slider always wraps its value indicator in an OverlayPortal.
/// On Windows that emits an orphaned semantics node when the slider lives in a
/// pushed route ("N will not be in the tree and is not the new root"), which
/// can freeze the whole accessibility tree. This control has no overlay and
/// exposes the same slider semantics.
class ThmrSlider extends StatefulWidget {
  const ThmrSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 100,
    this.divisions,
    this.step,
    this.semanticsLabel,
    this.formatValue,
    this.onChangeEnd,
    this.height = 34,
  });

  final double value;
  final double min;
  final double max;
  final int? divisions;
  final double? step;
  final String? semanticsLabel;
  final String Function(double value)? formatValue;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final double height;

  @override
  State<ThmrSlider> createState() => _ThmrSliderState();
}

class _ThmrSliderState extends State<ThmrSlider> {
  final _focus = FocusNode(debugLabel: '滑块');
  bool _focused = false;
  late double _last = _clamped(widget.value);

  double _clamped(double value) =>
      value.clamp(widget.min, widget.max).toDouble();

  double get _keyStep {
    final step = widget.step ??
        (widget.divisions != null
            ? (widget.max - widget.min) / widget.divisions!
            : (widget.max - widget.min) / 10);
    return step <= 0 ? (widget.max - widget.min) / 10 : step;
  }

  double _snap(double value) {
    final clamped = _clamped(value);
    if (widget.divisions != null && widget.divisions! > 0) {
      final fraction = (clamped - widget.min) / (widget.max - widget.min);
      final tick = (fraction * widget.divisions!).round();
      return _clamped(
          widget.min + tick / widget.divisions! * (widget.max - widget.min));
    }
    return clamped;
  }

  String _format(double value) =>
      widget.formatValue?.call(value) ?? _plain(value);

  static String _plain(double value) {
    if ((value - value.roundToDouble()).abs() < 0.001) {
      return value.round().toString();
    }
    return value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  @override
  void didUpdateWidget(covariant ThmrSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    _last = _clamped(widget.value);
  }

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  void _emit(double value) {
    _last = _clamped(value);
    widget.onChanged(_last);
  }

  void _changeBy(double delta) {
    final next = _snap(_clamped(_last) + delta);
    if ((next - _last).abs() < 0.0001) return;
    _emit(next);
    widget.onChangeEnd?.call(_last);
  }

  @override
  Widget build(BuildContext context) {
    final current = _clamped(widget.value);
    final accent = Theme.of(context).colorScheme.primary;
    final track = Theme.of(context).colorScheme.outlineVariant;

    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      void setFromOffset(double dx) {
        if (width <= 16) return;
        _focus.requestFocus();
        final fraction = ((dx - 8) / (width - 16)).clamp(0.0, 1.0);
        _emit(_snap(widget.min + fraction * (widget.max - widget.min)));
      }

      return Semantics(
        slider: true,
        label: widget.semanticsLabel,
        value: _format(current),
        increasedValue: _format(_snap(_clamped(current + _keyStep))),
        decreasedValue: _format(_snap(_clamped(current - _keyStep))),
        onIncrease: () => _changeBy(_keyStep),
        onDecrease: () => _changeBy(-_keyStep),
        child: Actions(
          actions: {
            DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
              onInvoke: (intent) {
                if (intent.direction == TraversalDirection.left ||
                    intent.direction == TraversalDirection.right) {
                  _changeBy(intent.direction == TraversalDirection.left
                      ? -_keyStep
                      : _keyStep);
                } else {
                  _focus.focusInDirection(intent.direction);
                }
                return null;
              },
            ),
          },
          child: Focus(
            focusNode: _focus,
            onFocusChange: (focused) => setState(() => _focused = focused),
            onKeyEvent: (node, event) {
              if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
                return KeyEventResult.ignored;
              }
              if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
                  event.logicalKey == LogicalKeyboardKey.arrowUp) {
                _changeBy(_keyStep);
              } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                  event.logicalKey == LogicalKeyboardKey.arrowDown) {
                _changeBy(-_keyStep);
              } else if (event.logicalKey == LogicalKeyboardKey.home) {
                _emit(widget.min);
                widget.onChangeEnd?.call(_last);
              } else if (event.logicalKey == LogicalKeyboardKey.end) {
                _emit(widget.max);
                widget.onChangeEnd?.call(_last);
              } else {
                return KeyEventResult.ignored;
              }
              return KeyEventResult.handled;
            },
            child: ThmrFocusRing(
                focused: _focused,
                radius: 6,
                child: MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (details) {
                      setFromOffset(details.localPosition.dx);
                      widget.onChangeEnd?.call(_last);
                    },
                    onHorizontalDragStart: (details) =>
                        setFromOffset(details.localPosition.dx),
                    onHorizontalDragUpdate: (details) =>
                        setFromOffset(details.localPosition.dx),
                    onHorizontalDragEnd: (_) => widget.onChangeEnd?.call(_last),
                    child: SizedBox(
                      width: double.infinity,
                      height: widget.height,
                      child: CustomPaint(
                        painter: _ThmrSliderPainter(
                          fraction: widget.max == widget.min
                              ? 0
                              : (current - widget.min) /
                                  (widget.max - widget.min),
                          accent: accent,
                          track: track,
                        ),
                      ),
                    ),
                  ),
                )),
          ),
        ),
      );
    });
  }
}

class _ThmrSliderPainter extends CustomPainter {
  const _ThmrSliderPainter(
      {required this.fraction, required this.accent, required this.track});

  final double fraction;
  final Color accent;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const left = 8.0;
    final right = size.width - 8;
    if (right <= left) return;
    final y = size.height / 2;
    final paint = Paint()..color = track;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(left, y - 1.5, right, y + 1.5),
        const Radius.circular(2),
      ),
      paint,
    );
    final thumbX = left + (right - left) * fraction.clamp(0.0, 1.0);
    paint.color = accent;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTRB(left, y - 1.5, thumbX, y + 1.5),
        const Radius.circular(2),
      ),
      paint,
    );
    canvas.drawCircle(Offset(thumbX, y), 6, paint);
  }

  @override
  bool shouldRepaint(_ThmrSliderPainter oldDelegate) =>
      fraction != oldDelegate.fraction ||
      accent != oldDelegate.accent ||
      track != oldDelegate.track;
}
