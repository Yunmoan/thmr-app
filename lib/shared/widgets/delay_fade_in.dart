import 'dart:async';

import 'package:flutter/material.dart';
import '../../core/theme/thmr_motion.dart';

class DelayFadeIn extends StatefulWidget {
  const DelayFadeIn(
      {super.key, this.delay = Duration.zero, required this.child});
  final Duration delay;
  final Widget child;

  @override
  State<DelayFadeIn> createState() => _DelayFadeInState();
}

class _DelayFadeInState extends State<DelayFadeIn>
    with SingleTickerProviderStateMixin {
  late final _controller =
      AnimationController(vsync: this, duration: ThmrMotion.duration);
  Timer? _timer;
  bool _scheduled = false;
  int _generation = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _generation++;
      _timer?.cancel();
      _controller.value = 1;
    } else if (!_scheduled && _controller.value == 0) {
      _schedule();
    }
  }

  void _schedule() {
    _scheduled = true;
    final generation = ++_generation;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _generation) return;
      if (widget.delay == Duration.zero) {
        _controller.forward();
      } else {
        _timer = Timer(widget.delay, () {
          if (mounted && generation == _generation) _controller.forward();
        });
      }
    });
  }

  @override
  void didUpdateWidget(covariant DelayFadeIn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.delay != widget.delay && _timer?.isActive == true) {
      _timer?.cancel();
      _schedule();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ThmrFadeSlide(animation: _controller, child: widget.child);
}
