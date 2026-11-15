import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/thmr_focus_ring.dart';

/// Volume control without Slider's OverlayPortal, which can produce orphaned
/// accessibility nodes on Windows when shown in a pushed route.
class VolumeSlider extends StatefulWidget {
  const VolumeSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.height = 34,
  });

  final double value;
  final ValueChanged<double> onChanged;
  final double height;

  @override
  State<VolumeSlider> createState() => _VolumeSliderState();
}

class _VolumeSliderState extends State<VolumeSlider> {
  final _focus = FocusNode(debugLabel: '音量');
  bool _focused = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final current = widget.value.clamp(0.0, 100.0);
    final accent = Theme.of(context).colorScheme.primary;
    final track = Theme.of(context).colorScheme.outlineVariant;

    void changeBy(double delta) =>
        widget.onChanged((current + delta).clamp(0.0, 100.0));

    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      void setFromOffset(double dx) {
        if (width <= 16) return;
        _focus.requestFocus();
        widget.onChanged(((dx - 8) / (width - 16) * 100).clamp(0.0, 100.0));
      }

      return Semantics(
        slider: true,
        label: '音量',
        value: '${current.round()}%',
        increasedValue: '${(current + 5).clamp(0.0, 100.0).round()}%',
        decreasedValue: '${(current - 5).clamp(0.0, 100.0).round()}%',
        onIncrease: () => changeBy(5),
        onDecrease: () => changeBy(-5),
        child: Actions(
          actions: {
            DirectionalFocusIntent: CallbackAction<DirectionalFocusIntent>(
              onInvoke: (intent) {
                if (intent.direction == TraversalDirection.left ||
                    intent.direction == TraversalDirection.right) {
                  changeBy(
                      intent.direction == TraversalDirection.left ? -5 : 5);
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
                changeBy(5);
              } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                  event.logicalKey == LogicalKeyboardKey.arrowDown) {
                changeBy(-5);
              } else if (event.logicalKey == LogicalKeyboardKey.home) {
                widget.onChanged(0);
              } else if (event.logicalKey == LogicalKeyboardKey.end) {
                widget.onChanged(100);
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
                    onTapDown: (details) =>
                        setFromOffset(details.localPosition.dx),
                    onHorizontalDragStart: (details) =>
                        setFromOffset(details.localPosition.dx),
                    onHorizontalDragUpdate: (details) =>
                        setFromOffset(details.localPosition.dx),
                    child: SizedBox(
                      width: double.infinity,
                      height: widget.height,
                      child: CustomPaint(
                        painter:
                            _VolumeSliderPainter(current / 100, accent, track),
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

class _VolumeSliderPainter extends CustomPainter {
  const _VolumeSliderPainter(this.fraction, this.accent, this.track);

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
    final thumbX = left + (right - left) * fraction;
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
  bool shouldRepaint(_VolumeSliderPainter oldDelegate) =>
      fraction != oldDelegate.fraction ||
      accent != oldDelegate.accent ||
      track != oldDelegate.track;
}
