import 'package:flutter/material.dart';

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
    duration: const Duration(milliseconds: 240),
    value: widget.active ? 0 : 1,
  );

  @override
  void initState() {
    super.initState();
    if (widget.active) _controller.forward();
  }

  @override
  void didUpdateWidget(covariant PersistentTabPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) {
      _controller.forward(from: 0);
    }
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
    final animation = MediaQuery.disableAnimationsOf(context)
        ? content
        : FadeTransition(
            opacity: _controller.drive(CurveTween(curve: Curves.easeOutCubic)),
            child: SlideTransition(
              position: _controller.drive(Tween<Offset>(
                begin: const Offset(0, 0.014),
                end: Offset.zero,
              ).chain(CurveTween(curve: Curves.easeOutCubic))),
              child: content,
            ),
          );
    return Offstage(
      offstage: !widget.active,
      child: TickerMode(enabled: widget.active, child: animation),
    );
  }
}
