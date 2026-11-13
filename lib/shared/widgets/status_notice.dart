import 'dart:async';
import 'package:flutter/material.dart';

/// A non-modal status surface. Place in a Stack so it never resizes content.
/// null duration keeps progress visible until the operation changes state.
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

class _StatusNoticeState extends State<StatusNotice> {
  Timer? _timer;
  bool _visible = true;
  @override
  void initState() {
    super.initState();
    _reset();
  }

  @override
  void didUpdateWidget(StatusNotice oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.message != widget.message ||
        oldWidget.duration != widget.duration) {
      _reset();
    }
  }

  void _reset() {
    _timer?.cancel();
    _visible = true;
    if (widget.message != null && widget.duration != null) {
      _timer = Timer(widget.duration!, () {
        if (mounted) setState(() => _visible = false);
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
    if (!_visible || widget.message == null) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.topCenter,
      heightFactor: 1,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Material(
          elevation: 6,
          color: Theme.of(context).colorScheme.inverseSurface,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(children: [
              if (widget.busy) ...[
                SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.onInverseSurface)),
                const SizedBox(width: 10),
              ],
              Expanded(
                  child: Semantics(
                      liveRegion: true,
                      child: Text(widget.message!,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onInverseSurface)))),
              if (widget.onRetry != null)
                TextButton(
                    onPressed: widget.onRetry,
                    style: TextButton.styleFrom(
                        foregroundColor:
                            Theme.of(context).colorScheme.inversePrimary),
                    child: const Text('重试')),
              IconButton(
                  tooltip: '关闭提示',
                  color: Theme.of(context).colorScheme.onInverseSurface,
                  onPressed: () => setState(() => _visible = false),
                  icon: const Icon(Icons.close_rounded, size: 18)),
            ]),
          ),
        ),
      ),
    );
  }
}
