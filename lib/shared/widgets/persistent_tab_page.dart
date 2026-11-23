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
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: ThmrMotion.duration,
  );
  late final _progress =
      _controller.drive(CurveTween(curve: ThmrMotion.enterCurve));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateAnimation();
  }

  void _updateAnimation() {
    if (!widget.active) {
      _controller.value = 0;
    } else if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void didUpdateWidget(covariant PersistentTabPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active != oldWidget.active) _updateAnimation();
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
    return Offstage(
      offstage: !widget.active,
      child: ExcludeFocus(
        excluding: !widget.active,
        child: TickerMode(
            enabled: widget.active,
            child: ThmrSlide(progress: _progress, child: content)),
      ),
    );
  }
}
