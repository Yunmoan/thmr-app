import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// A window-level paint layer keeps outward focus rings above Material, menu,
/// rounded-panel and viewport clips. It never receives input or semantics.
class ThmrFocusLayer extends StatefulWidget {
  const ThmrFocusLayer({
    super.key,
    required this.child,
    this.reserveEdgeSpace = true,
  });
  final Widget child;
  final bool reserveEdgeSpace;

  @override
  State<ThmrFocusLayer> createState() => _ThmrFocusLayerState();
}

class _ThmrFocusLayerState extends State<ThmrFocusLayer> {
  final _entries = <_ThmrFocusRingState, Widget>{};

  void update(_ThmrFocusRingState target, Widget? overlay) {
    if (!mounted) return;
    if (overlay == null && !_entries.containsKey(target)) return;
    setState(() {
      if (overlay == null) {
        _entries.remove(target);
      } else {
        _entries[target] = overlay;
      }
    });
  }

  @override
  Widget build(BuildContext context) => _FocusLayerScope(
        layer: this,
        child: Stack(
          fit: StackFit.expand,
          clipBehavior: Clip.none,
          children: [
            if (widget.reserveEdgeSpace)
              ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
            // Keep room for a full outward ring even at the window edge.
            Padding(
              padding: widget.reserveEdgeSpace
                  ? const EdgeInsets.all(ThmrFocusRing.extent)
                  : EdgeInsets.zero,
              child: widget.child,
            ),
            for (final entry in _entries.entries)
              if (entry.key.mounted) Positioned.fill(child: entry.value),
          ],
        ),
      );
}

class _FocusLayerScope extends InheritedWidget {
  const _FocusLayerScope({required this.layer, required super.child});
  final _ThmrFocusLayerState layer;

  @override
  bool updateShouldNotify(_FocusLayerScope oldWidget) =>
      layer != oldWidget.layer;
}

/// One logical pixel, separated from the control by a two-pixel gap. The
/// composited follower tracks scrolling and transforms without changing layout.
class ThmrFocusRing extends StatefulWidget {
  const ThmrFocusRing({
    super.key,
    required this.focused,
    required this.child,
    this.radius = 8,
    this.focusNode,
    this.shape,
  });

  static const width = 1.0;
  static const gap = 2.0;
  static const extent = gap + width;
  final bool focused;
  final Widget child;
  final double radius;
  final FocusNode? focusNode;
  final OutlinedBorder? shape;

  static OutlinedBorder? _buttonShape(
      BuildContext context, Set<WidgetState> states) {
    final button = context.widget;
    if (button is! ButtonStyleButton) return null;
    final ButtonStyle? themeStyle;
    if (button is FilledButton) {
      themeStyle = FilledButtonTheme.of(context).style;
    } else if (button is OutlinedButton) {
      themeStyle = OutlinedButtonTheme.of(context).style;
    } else if (button is TextButton) {
      themeStyle = TextButtonTheme.of(context).style;
    } else {
      themeStyle = IconButtonTheme.of(context).style;
    }
    return button.style?.shape?.resolve(states) ??
        themeStyle?.shape?.resolve(states);
  }

  static Widget buttonBuilder(
    BuildContext context,
    Set<WidgetState> states,
    Widget? child,
  ) =>
      ThmrFocusRing(
        shape: _buttonShape(context, states),
        focused: states.contains(WidgetState.focused) &&
            !states.contains(WidgetState.disabled),
        child: child ?? const SizedBox.shrink(),
      );

  static Widget circularButtonBuilder(
    BuildContext context,
    Set<WidgetState> states,
    Widget? child,
  ) =>
      ThmrFocusRing(
        shape: _buttonShape(context, states),
        focused: states.contains(WidgetState.focused) &&
            !states.contains(WidgetState.disabled),
        radius: 999,
        child: child ?? const SizedBox.shrink(),
      );

  @override
  State<ThmrFocusRing> createState() => _ThmrFocusRingState();
}

class _ThmrFocusRingState extends State<ThmrFocusRing> {
  final _link = LayerLink();
  final _targetKey = GlobalKey();
  final _geometry = _FocusGeometrySignal();
  _ThmrFocusLayerState? _layer;
  bool _syncPending = false;
  Color _color = Colors.transparent;
  TextDirection _direction = TextDirection.ltr;

  Rect? _bounds() {
    final box = _targetKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final target = widget.focusNode?.context?.findRenderObject();
    if (target is RenderBox && target.attached && target.hasSize) {
      return box.globalToLocal(target.localToGlobal(Offset.zero)) & target.size;
    }
    return Offset.zero & box.size;
  }

  void _syncOverlay() {
    if (_syncPending) return;
    _syncPending = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncPending = false;
      if (!mounted || _layer == null) return;
      _layer!.update(
        this,
        widget.focused
            ? IgnorePointer(
                child: ExcludeSemantics(
                  child: CompositedTransformFollower(
                    link: _link,
                    showWhenUnlinked: false,
                    child: CustomPaint(
                      foregroundPainter: _FocusRingPainter(
                        widget.radius,
                        _color,
                        bounds: _bounds,
                        geometry: _geometry,
                        shape: widget.shape,
                        direction: _direction,
                      ),
                    ),
                  ),
                ),
              )
            : null,
      );
    });
  }

  @override
  void dispose() {
    _geometry.dispose();
    final layer = _layer;
    if (layer != null) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => layer.update(this, null));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final nextLayer =
        context.dependOnInheritedWidgetOfExactType<_FocusLayerScope>()?.layer;
    if (_layer != nextLayer) {
      final previous = _layer;
      if (previous != null) {
        WidgetsBinding.instance
            .addPostFrameCallback((_) => previous.update(this, null));
      }
      _layer = nextLayer;
    }
    _color = Theme.of(context).colorScheme.primary;
    _direction = Directionality.maybeOf(context) ?? TextDirection.ltr;
    if (_layer != null &&
        (widget.focused || _layer!._entries.containsKey(this))) {
      _syncOverlay();
    }
    return CompositedTransformTarget(
      key: _targetKey,
      link: _link,
      child: _FocusGeometry(
        onLayout: _geometry.changed,
        child: _layer == null
            // Standalone controls can also be embedded without the app layer.
            ? CustomPaint(
                foregroundPainter: widget.focused
                    ? _FocusRingPainter(widget.radius, _color,
                        bounds: _bounds,
                        geometry: _geometry,
                        shape: widget.shape,
                        direction: _direction)
                    : null,
                child: widget.child,
              )
            : widget.child,
      ),
    );
  }
}

/// A control can resize inside a retained repaint boundary without rebuilding
/// its focus widget. Invalidate the external painter during layout, before the
/// paint phase, so the ring uses this frame's bounds (including animations).
class _FocusGeometrySignal extends ChangeNotifier {
  void changed() => notifyListeners();
}

class _FocusGeometry extends SingleChildRenderObjectWidget {
  const _FocusGeometry({required this.onLayout, required super.child});
  final VoidCallback onLayout;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderFocusGeometry(onLayout);

  @override
  void updateRenderObject(
      BuildContext context, _RenderFocusGeometry renderObject) {
    renderObject.onLayout = onLayout;
  }
}

class _RenderFocusGeometry extends RenderProxyBox {
  _RenderFocusGeometry(this.onLayout);
  VoidCallback onLayout;

  @override
  void performLayout() {
    super.performLayout();
    onLayout();
  }
}

class _FocusRingPainter extends CustomPainter {
  _FocusRingPainter(this.radius, this.accent,
      {required this.bounds,
      required Listenable geometry,
      this.shape,
      this.direction = TextDirection.ltr})
      : super(repaint: geometry);
  final double radius;
  final Color accent;
  final Rect? Function() bounds;
  final OutlinedBorder? shape;
  final TextDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = bounds();
    if (rect == null || rect.isEmpty) return;
    const expansion = ThmrFocusRing.gap + ThmrFocusRing.width / 2;
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = ThmrFocusRing.width
      ..color = accent;
    final border = shape;
    if (border is RoundedRectangleBorder) {
      final corners = border.borderRadius.resolve(direction);
      const extra = Radius.circular(expansion);
      canvas.drawRRect(
          RRect.fromRectAndCorners(
            rect.inflate(expansion),
            topLeft: corners.topLeft + extra,
            topRight: corners.topRight + extra,
            bottomLeft: corners.bottomLeft + extra,
            bottomRight: corners.bottomRight + extra,
          ),
          paint);
    } else if (border != null) {
      canvas.drawPath(
          border.getOuterPath(rect.inflate(expansion),
              textDirection: direction),
          paint);
    } else {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
            rect.inflate(expansion),
            Radius.circular(radius + expansion),
          ),
          paint);
    }
  }

  @override
  bool shouldRepaint(_FocusRingPainter oldDelegate) =>
      radius != oldDelegate.radius ||
      accent != oldDelegate.accent ||
      shape != oldDelegate.shape ||
      direction != oldDelegate.direction ||
      bounds != oldDelegate.bounds;
}
