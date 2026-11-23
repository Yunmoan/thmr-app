import 'package:flutter/material.dart';
import '../../core/theme/thmr_motion.dart';

/// 在标签页首次选中前准备其内容，隐藏时暂停 Ticker 并保留组件状态。
class PersistentTabPage extends StatefulWidget {
  const PersistentTabPage({
    super.key,
    required this.active,
    required this.child,
  });

  final bool active;
  final Widget child;

  @override
  State<PersistentTabPage> createState() => _PersistentTabPageState();
}

class _PersistentTabPageState extends State<PersistentTabPage>
    with SingleTickerProviderStateMixin {
  final _backdropKey = BackdropKey();
  late bool _visible = widget.active;
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: ThmrMotion.duration,
    reverseDuration: ThmrMotion.exitDuration,
    value: 0,
  );

  @override
  void initState() {
    super.initState();
    _controller.addStatusListener(_statusChanged);
  }

  void _statusChanged(AnimationStatus status) {
    if (status == AnimationStatus.dismissed && !widget.active && _visible) {
      setState(() => _visible = false);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateAnimation();
  }

  void _updateAnimation() {
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _visible = widget.active;
      _controller.value = widget.active ? 1 : 0;
    } else if (widget.active) {
      _visible = true;
      _controller.forward();
    } else if (_visible) {
      _controller.reverse();
    }
  }

  @override
  void didUpdateWidget(covariant PersistentTabPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateAnimation();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = RepaintBoundary(
        child: BackdropGroup(backdropKey: _backdropKey, child: widget.child));
    final animation = ThmrFadeSlide(animation: _controller, child: content);
    return Offstage(
      offstage: !_visible,
      child: ExcludeFocus(
        excluding: !widget.active,
        child: ExcludeSemantics(
            excluding: !widget.active,
            child: IgnorePointer(
                ignoring: !widget.active,
                child: TickerMode(enabled: widget.active, child: animation))),
      ),
    );
  }
}
