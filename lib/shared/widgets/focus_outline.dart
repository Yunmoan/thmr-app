import 'package:flutter/material.dart';

/// A foreground outline stays visible even when an InkWell's child paints an
/// opaque panel over its ink. This adds no extra traversal stop or layout size.
class FocusOutline extends StatefulWidget {
  const FocusOutline({super.key, required this.child, this.radius = 8});
  final Widget child;
  final double radius;

  @override
  State<FocusOutline> createState() => _FocusOutlineState();
}

class _FocusOutlineState extends State<FocusOutline> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onFocusChange: (focused) => setState(() => _focused = focused),
        child: CustomPaint(
          foregroundPainter: _focused ? _OutlinePainter(widget.radius) : null,
          child: widget.child,
        ),
      );
}

class _OutlinePainter extends CustomPainter {
  const _OutlinePainter(this.radius);
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final outline = RRect.fromRectAndRadius(
        (Offset.zero & size).deflate(2), Radius.circular(radius));
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..color = Colors.white;
    canvas.drawRRect(outline, paint);
    paint
      ..strokeWidth = 2
      ..color = Colors.black;
    canvas.drawRRect(outline, paint);
  }

  @override
  bool shouldRepaint(_OutlinePainter oldDelegate) =>
      radius != oldDelegate.radius;
}
