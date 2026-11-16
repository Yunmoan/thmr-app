import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

class ThmrMotion {
  const ThmrMotion._();
  static const duration = Duration(milliseconds: 240);
  static const exitDuration = Duration(milliseconds: 180);
  static const shortDuration = Duration(milliseconds: 160);
  static const enterCurve = Curves.easeOutCubic;
  static const exitCurve = Curves.easeInCubic;
  static const distance = 8.0;

  static Duration of(BuildContext context, {bool exiting = false}) =>
      MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : exiting
              ? exitDuration
              : duration;

  static AnimationStyle style(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context)
          ? AnimationStyle.noAnimation
          : const AnimationStyle(
              duration: duration,
              reverseDuration: exitDuration,
              curve: enterCurve,
              reverseCurve: exitCurve);

  static Duration quickOf(BuildContext context) =>
      MediaQuery.disableAnimationsOf(context) ? Duration.zero : shortDuration;
}

extension ThmrMessengerMotion on ScaffoldMessengerState {
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showThmrSnackBar(
          BuildContext motionContext, SnackBar snackBar) =>
      showSnackBar(snackBar,
          snackBarAnimationStyle: ThmrMotion.style(motionContext));
}

/// AnimatedSize with a true, state-preserving reduced-motion path. A zero
/// duration restarts its render controller during layout on this Flutter SDK.
class ThmrAnimatedSize extends StatefulWidget {
  const ThmrAnimatedSize(
      {super.key, this.alignment = Alignment.center, required this.child});
  final AlignmentGeometry alignment;
  final Widget child;
  @override
  State<ThmrAnimatedSize> createState() => _ThmrAnimatedSizeState();
}

class _ThmrAnimatedSizeState extends State<ThmrAnimatedSize> {
  final _childKey = GlobalKey();
  @override
  Widget build(BuildContext context) {
    final child = KeyedSubtree(key: _childKey, child: widget.child);
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      return child;
    }
    return AnimatedSize(
      duration: ThmrMotion.duration,
      reverseDuration: ThmrMotion.exitDuration,
      curve: ThmrMotion.enterCurve,
      alignment: widget.alignment,
      child: child,
    );
  }
}

/// A reversible entrance. Keep both the curve and child alive when interrupted.
class ThmrFadeSlide extends StatefulWidget {
  const ThmrFadeSlide(
      {super.key, required this.animation, required this.child});
  final Animation<double> animation;
  final Widget child;

  @override
  State<ThmrFadeSlide> createState() => _ThmrFadeSlideState();
}

class _ThmrFadeSlideState extends State<ThmrFadeSlide> {
  late CurvedAnimation _curve = _makeCurve();

  CurvedAnimation _makeCurve() => CurvedAnimation(
        parent: widget.animation,
        curve: ThmrMotion.enterCurve,
        reverseCurve: ThmrMotion.exitCurve,
      );

  @override
  void didUpdateWidget(covariant ThmrFadeSlide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animation != widget.animation) {
      _curve.dispose();
      _curve = _makeCurve();
    }
  }

  @override
  void dispose() {
    _curve.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return AnimatedBuilder(
      animation: _curve,
      child: widget.child,
      builder: (context, child) {
        final progress = reduced ? 1.0 : _curve.value;
        return IgnorePointer(
          ignoring: progress == 0,
          child: ExcludeFocus(
            excluding: progress == 0,
            child: FadeTransition(
              opacity: AlwaysStoppedAnimation(progress),
              child: Transform.translate(
                offset: Offset(0, ThmrMotion.distance * (1 - progress)),
                child: child,
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Outgoing content retains its dimensions and cannot receive input or focus.
class ThmrAnimatedContent extends StatefulWidget {
  const ThmrAnimatedContent(
      {super.key, this.alignment = Alignment.topLeft, required this.child});
  final Widget child;
  final AlignmentGeometry alignment;
  @override
  State<ThmrAnimatedContent> createState() => _ThmrAnimatedContentState();
}

class _ContentEntry {
  _ContentEntry(this.id, this.child, TickerProvider vsync,
      {bool initial = false})
      : controller = AnimationController(
          vsync: vsync,
          duration: ThmrMotion.duration,
          reverseDuration: ThmrMotion.exitDuration,
          value: initial ? 1 : 0,
        ) {
    opacity = CurvedAnimation(
        parent: controller,
        curve: ThmrMotion.enterCurve,
        reverseCurve: ThmrMotion.exitCurve);
  }
  final int id;
  Widget child;
  final AnimationController controller;
  late final CurvedAnimation opacity;
  void dispose() {
    opacity.dispose();
    controller.dispose();
  }
}

class _ThmrAnimatedContentState extends State<ThmrAnimatedContent>
    with TickerProviderStateMixin {
  int _serial = 0;
  late _ContentEntry _current =
      _ContentEntry(_serial++, widget.child, this, initial: true);
  final _previous = <_ContentEntry>[];
  bool _reduced = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled;
    if (_reduced) {
      _current.controller.value = 1;
      for (final entry in _previous) {
        entry.dispose();
      }
      _previous.clear();
    }
  }

  @override
  void didUpdateWidget(covariant ThmrAnimatedContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (Widget.canUpdate(_current.child, widget.child)) {
      _current.child = widget.child;
      return;
    }
    final old = _current;
    _current = _ContentEntry(_serial++, widget.child, this, initial: _reduced);
    if (_reduced) {
      old.dispose();
    } else {
      _previous.add(old);
      old.controller.reverse().then((_) {
        if (!mounted || !_previous.remove(old)) return;
        setState(() {});
        old.dispose();
      });
      _current.controller.forward();
    }
  }

  @override
  void dispose() {
    _current.dispose();
    for (final entry in _previous) {
      entry.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget layer(_ContentEntry entry, {required bool outgoing}) =>
        _ContentLayer(
          key: ValueKey(entry.id),
          outgoing: outgoing,
          child: BackdropGroup(
            child: ExcludeFocus(
              excluding: outgoing,
              child: ExcludeSemantics(
                excluding: outgoing,
                child: IgnorePointer(
                  ignoring: outgoing,
                  child: TickerMode(
                    enabled: !outgoing,
                    child: FadeTransition(
                        opacity: entry.opacity, child: entry.child),
                  ),
                ),
              ),
            ),
          ),
        );
    return _ContentLayers(
        alignment: widget.alignment.resolve(Directionality.of(context)),
        children: [
          for (final entry in _previous) layer(entry, outgoing: true),
          layer(_current, outgoing: false),
        ]);
  }
}

class _ContentParentData extends ContainerBoxParentData<RenderBox> {
  bool outgoing = false;
  Size? retainedSize;
}

class _ContentLayer extends ParentDataWidget<_ContentParentData> {
  const _ContentLayer(
      {super.key, required this.outgoing, required super.child});
  final bool outgoing;

  @override
  void applyParentData(RenderObject renderObject) {
    final data = renderObject.parentData! as _ContentParentData;
    if (data.outgoing == outgoing) return;
    data.outgoing = outgoing;
    renderObject.parent?.markNeedsLayout();
  }

  @override
  Type get debugTypicalAncestorWidgetClass => _ContentLayers;
}

class _ContentLayers extends MultiChildRenderObjectWidget {
  const _ContentLayers({required this.alignment, required super.children});
  final Alignment alignment;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderContentLayers(alignment);
  @override
  void updateRenderObject(
      BuildContext context, covariant _RenderContentLayers renderObject) {
    renderObject.alignment = alignment;
  }
}

/// Size follows the current child without squeezing a departing title or card.
/// Stable layers also retain outgoing state across the switch.
class _RenderContentLayers extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _ContentParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _ContentParentData> {
  _RenderContentLayers(this._alignment);
  Alignment _alignment;
  set alignment(Alignment value) {
    if (value == _alignment) return;
    _alignment = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _ContentParentData) {
      child.parentData = _ContentParentData();
    }
  }

  RenderBox? get _current {
    RenderBox? child = firstChild;
    while (child != null) {
      final data = child.parentData! as _ContentParentData;
      if (!data.outgoing) return child;
      child = data.nextSibling;
    }
    return null;
  }

  @override
  Size computeDryLayout(BoxConstraints constraints) => constraints
      .constrain(_current?.getDryLayout(constraints.loosen()) ?? Size.zero);
  @override
  double computeMinIntrinsicWidth(double height) =>
      _current?.getMinIntrinsicWidth(height) ?? 0;
  @override
  double computeMaxIntrinsicWidth(double height) =>
      _current?.getMaxIntrinsicWidth(height) ?? 0;
  @override
  double computeMinIntrinsicHeight(double width) =>
      _current?.getMinIntrinsicHeight(width) ?? 0;
  @override
  double computeMaxIntrinsicHeight(double width) =>
      _current?.getMaxIntrinsicHeight(width) ?? 0;

  @override
  void performLayout() {
    final current = _current;
    current?.layout(constraints.loosen(), parentUsesSize: true);
    size = constraints.constrain(current?.size ?? Size.zero);
    RenderBox? child = firstChild;
    while (child != null) {
      final data = child.parentData! as _ContentParentData;
      if (data.outgoing) {
        child.layout(
            data.retainedSize == null
                ? constraints.loosen()
                : BoxConstraints.tight(data.retainedSize!),
            parentUsesSize: true);
      } else {
        data.retainedSize = child.size;
      }
      data.offset = _alignment.alongOffset(Offset(
          size.width - child.size.width, size.height - child.size.height));
      child = data.nextSibling;
    }
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) {
    final current = _current;
    final distance = current?.getDistanceToActualBaseline(baseline);
    if (current == null || distance == null) return null;
    return distance + (current.parentData! as _ContentParentData).offset.dy;
  }

  @override
  void paint(PaintingContext context, Offset offset) => context.pushClipRect(
      needsCompositing, offset, Offset.zero & size, defaultPaint);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final current = _current;
    if (current == null) return false;
    return result.addWithPaintOffset(
      offset: (current.parentData! as _ContentParentData).offset,
      position: position,
      hitTest: (result, position) =>
          current.hitTest(result, position: position),
    );
  }
}

class ThmrPageTransitionsBuilder extends PageTransitionsBuilder {
  const ThmrPageTransitionsBuilder();
  @override
  Duration get transitionDuration => ThmrMotion.duration;
  @override
  Duration get reverseTransitionDuration => ThmrMotion.exitDuration;
  @override
  Widget buildTransitions<T>(
          PageRoute<T> route,
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation,
          Widget child) =>
      ThmrFadeSlide(animation: animation, child: child);
}
