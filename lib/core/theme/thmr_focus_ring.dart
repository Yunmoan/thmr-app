import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 在窗口级绘制焦点外环，避开 Material、菜单、圆角面板和视口的裁剪。此绘制层不接收输入，
/// 也不生成无障碍语义节点。
class ThmrFocusLayer extends StatefulWidget {
  const ThmrFocusLayer({
    super.key,
    required this.child,
  });
  final Widget child;

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
            widget.child,
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

/// 焦点环宽 1 个逻辑像素，通常与控件间隔 2 个逻辑像素。合成跟随层随控件滚动和变换，不占布局空间。
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
  bool _active = true;
  bool _syncPending = false;
  Color _color = Colors.transparent;
  TextDirection _direction = TextDirection.ltr;

  Rect? _bounds() {
    // 目标子树移除后，窗口覆盖层仍可能绘制本帧。元素会先进入停用状态，再执行 State.dispose。
    if (!_active) return null;
    final box = _targetKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final target = widget.focusNode?.context?.findRenderObject();
    if (target is RenderBox && target.attached && target.hasSize) {
      return box.globalToLocal(target.localToGlobal(Offset.zero)) & target.size;
    }
    return Offset.zero & box.size;
  }

  Rect? _windowBounds() {
    final target = _targetKey.currentContext?.findRenderObject();
    final window = _layer?.context.findRenderObject();
    if (target is! RenderBox ||
        !target.attached ||
        window is! RenderBox ||
        !window.attached ||
        !window.hasSize) {
      return null;
    }
    return MatrixUtils.transformRect(
        window.getTransformTo(target), Offset.zero & window.size);
  }

  void _syncOverlay(Listenable repaint) {
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
                        windowBounds: _windowBounds,
                        repaint: repaint,
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
  void activate() {
    super.activate();
    _active = true;
  }

  @override
  void deactivate() {
    _active = false;
    super.deactivate();
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
      // 滚动可能仅移动合成层。焦点环需要重新计算距窗口边缘的距离。
      _syncOverlay(Listenable.merge([
        _geometry,
        Scrollable.maybeOf(context, axis: Axis.vertical)?.position,
        Scrollable.maybeOf(context, axis: Axis.horizontal)?.position,
      ]));
    }
    return CompositedTransformTarget(
      key: _targetKey,
      link: _link,
      child: _FocusGeometry(
        onLayout: _geometry.changed,
        child: _layer == null
            // 独立控件也可放在应用级焦点层之外使用。
            ? CustomPaint(
                foregroundPainter: widget.focused
                    ? _FocusRingPainter(widget.radius, _color,
                        bounds: _bounds,
                        repaint: _geometry,
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

/// 保留的 RepaintBoundary 内控件尺寸可能在焦点组件未重建时变化。布局阶段使外部画笔失效，
/// 确保本帧绘制使用新尺寸。
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
      this.windowBounds,
      required Listenable repaint,
      this.shape,
      this.direction = TextDirection.ltr})
      : super(repaint: repaint);
  final double radius;
  final Color accent;
  final Rect? Function() bounds;
  final Rect? Function()? windowBounds;
  final OutlinedBorder? shape;
  final TextDirection direction;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = bounds();
    if (rect == null || rect.isEmpty) return;
    const expansion = ThmrFocusRing.gap + ThmrFocusRing.width / 2;
    final window = windowBounds?.call();
    if (window != null && !window.overlaps(rect)) return;
    // 贴边时只收进超出窗口的一侧，给描边本身留半个线宽。
    var outline = rect.inflate(expansion);
    if (window != null) {
      outline = outline.intersect(window.deflate(ThmrFocusRing.width / 2));
    }
    if (outline.isEmpty) return;
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
            outline,
            topLeft: corners.topLeft + extra,
            topRight: corners.topRight + extra,
            bottomLeft: corners.bottomLeft + extra,
            bottomRight: corners.bottomRight + extra,
          ),
          paint);
    } else if (border != null) {
      canvas.drawPath(
          border.getOuterPath(outline, textDirection: direction), paint);
    } else {
      canvas.drawRRect(
          RRect.fromRectAndRadius(
            outline,
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
      bounds != oldDelegate.bounds ||
      windowBounds != oldDelegate.windowBounds;
}
