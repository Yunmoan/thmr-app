import 'package:flutter/material.dart';

import '../../core/theme/thmr_focus_ring.dart';

/// A foreground outline stays visible even when an InkWell's child paints an
/// opaque panel over its ink. This adds no extra traversal stop or layout size.
class FocusOutline extends StatefulWidget {
  const FocusOutline({
    super.key,
    required this.child,
    this.radius = 8,
    this.focusBounds = false,
  });
  final Widget child;
  final double radius;

  /// Use the control's painted box instead of padded pointer hit targets.
  final bool focusBounds;

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
        child: ThmrFocusRing(
          focused: _focused,
          radius: widget.radius,
          focusNode: widget.focusBounds && _focused
              ? FocusManager.instance.primaryFocus
              : null,
          child: widget.child,
        ),
      );
}

/// For content supplied to a control that owns its focus node (menu entries
/// and navigation destinations). Observe that node without adding a tab stop.
class AncestorFocusOutline extends StatelessWidget {
  const AncestorFocusOutline({
    super.key,
    required this.child,
    this.radius = 8,
    this.outlineChild = false,
  });

  final Widget child;
  final double radius;

  /// Observe the owning control's focus while outlining just this content slot.
  final bool outlineChild;

  @override
  Widget build(BuildContext context) => ThmrFocusRing(
        focused: Focus.of(context).hasPrimaryFocus,
        focusNode: outlineChild ? null : Focus.of(context),
        radius: radius,
        child: child,
      );
}

/// Match Material 3's 56 × 32 rail indicator without enclosing its label.
class NavigationRailFocusIcon extends StatelessWidget {
  const NavigationRailFocusIcon({super.key, required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) => AncestorFocusOutline(
        outlineChild: true,
        radius: 16,
        child: SizedBox(width: 56, height: 32, child: Icon(icon)),
      );
}
