// Delayed fade+rise entrance for panels.

import 'dart:async';

import 'package:flutter/material.dart';

class DelayFadeIn extends StatefulWidget {
  const DelayFadeIn({super.key, this.delay = Duration.zero, required this.child});

  final Duration delay;
  final Widget child;

  @override
  State<DelayFadeIn> createState() => _DelayFadeInState();
}

class _DelayFadeInState extends State<DelayFadeIn> {
  bool _shown = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    if (widget.delay == Duration.zero) {
      _shown = true;
    } else {
      _timer = Timer(widget.delay, () {
        if (mounted) setState(() => _shown = true);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _shown ? 1 : 0,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
      child: AnimatedSlide(
        offset: _shown ? Offset.zero : const Offset(0, 0.02),
        duration: const Duration(milliseconds: 360),
        curve: Curves.easeOutCubic,
        child: widget.child,
      ),
    );
  }
}
