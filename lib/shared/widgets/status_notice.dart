import 'dart:async';
import 'package:flutter/material.dart';

import '../../core/theme/thmr_motion.dart';

/// A status message over the page, with the same entrance/exit as other THMR
/// surfaces. Retain the outgoing content until its exit has finished.
class StatusNotice extends StatefulWidget {
  const StatusNotice(
      {super.key,
      required this.message,
      this.busy = false,
      this.duration = const Duration(seconds: 6),
      this.onRetry});
  final String? message;
  final bool busy;
  final Duration? duration;
  final VoidCallback? onRetry;
  @override
  State<StatusNotice> createState() => _StatusNoticeState();
}

class _StatusNoticeState extends State<StatusNotice>
    with SingleTickerProviderStateMixin {
  late final _animation = AnimationController(
      vsync: this,
      duration: ThmrMotion.duration,
      reverseDuration: ThmrMotion.exitDuration);
  Timer? _timer;
  bool _visible = false;
  (String, bool, VoidCallback?)? _display;

  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _drive();
  }

  @override
  void didUpdateWidget(covariant StatusNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message ||
        oldWidget.duration != widget.duration ||
        oldWidget.busy != widget.busy) {
      _reset();
      _drive();
    } else if (_visible && widget.message != null) {
      _display = (widget.message!, widget.busy, widget.onRetry);
    }
  }

  void _reset() {
    _timer?.cancel();
    _visible = widget.message != null;
    if (!_visible) return;
    _display = (widget.message!, widget.busy, widget.onRetry);
    if (widget.duration != null) _timer = Timer(widget.duration!, _dismiss);
  }

  void _dismiss() {
    _timer?.cancel();
    setState(() => _visible = false);
    _drive();
  }

  Future<void> _drive() async {
    _animation.duration = ThmrMotion.of(context);
    _animation.reverseDuration = ThmrMotion.of(context, exiting: true);
    if (MediaQuery.disableAnimationsOf(context)) {
      _animation.value = _visible ? 1 : 0;
      if (!_visible) _display = null;
      return;
    }
    try {
      if (_visible) {
        await _animation.forward().orCancel;
      } else {
        await _animation.reverse().orCancel;
        if (mounted && !_visible && _display != null) {
          setState(() => _display = null);
        }
      }
    } on TickerCanceled {
      // A replacement, reduced-motion update or disposal superseded the exit.
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final display = _display;
    if (display == null) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.topCenter,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ExcludeFocus(
          excluding: !_visible,
          child: ExcludeSemantics(
            excluding: !_visible,
            child: IgnorePointer(
              ignoring: !_visible,
              child: ThmrFadeSlide(
                animation: _animation,
                child: ThmrAnimatedContent(
                    child: Material(
                  key: ValueKey(display.$1),
                  elevation: 6,
                  color: scheme.inverseSurface,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    child: Row(children: [
                      if (display.$2) ...[
                        SizedBox(
                            width: 16,
                            height: 16,
                            child: MediaQuery.disableAnimationsOf(context)
                                ? Icon(Icons.hourglass_empty_rounded,
                                    size: 16, color: scheme.onInverseSurface)
                                : CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: scheme.onInverseSurface)),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                          child: Semantics(
                              liveRegion: true,
                              child: Text(display.$1,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: scheme.onInverseSurface)))),
                      if (display.$3 != null)
                        TextButton(
                            onPressed: display.$3,
                            style: TextButton.styleFrom(
                                foregroundColor: scheme.inversePrimary),
                            child: const Text('重试')),
                      IconButton(
                          tooltip: '关闭提示',
                          color: scheme.onInverseSurface,
                          onPressed: _dismiss,
                          icon: const Icon(Icons.close_rounded, size: 18)),
                    ]),
                  ),
                )),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
