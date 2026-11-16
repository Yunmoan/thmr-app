import 'package:flutter/material.dart';
import '../../core/theme/thmr_motion.dart';

/// Keeps tabs ready before selection and retains state while hidden and muted.
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
    value: widget.active ? 0 : 1,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateAnimation();
  }

  void _updateAnimation({bool entering = false}) {
    if (!widget.active ||
        MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _controller.value = 1;
    } else if (entering || _controller.value == 0) {
      _controller.forward(from: 0);
    }
  }

  @override
  void didUpdateWidget(covariant PersistentTabPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateAnimation(entering: widget.active && !oldWidget.active);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final content = BackdropGroup(
      backdropKey: _backdropKey,
      child: widget.child,
    );
    final animation = ThmrFadeSlide(animation: _controller, child: content);
    return Offstage(
      offstage: !widget.active,
      child: ExcludeFocus(
        excluding: !widget.active,
        child: TickerMode(enabled: widget.active, child: animation),
      ),
    );
  }
}
