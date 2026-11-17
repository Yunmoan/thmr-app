import 'package:flutter/material.dart';

class MessageSurface extends StatelessWidget {
  const MessageSurface({super.key, required this.child, this.color});

  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: MessageBody.maxWidth),
          child: Material(
            elevation: MessageBody.elevation,
            color: color ?? Theme.of(context).colorScheme.inverseSurface,
            borderRadius: BorderRadius.circular(MessageBody.radius),
            child: child,
          ),
        ),
      );
}

/// Shared content for transient messages and ongoing playback status.
class MessageBody extends StatelessWidget {
  const MessageBody({
    super.key,
    required this.content,
    required this.onClose,
    this.busy = false,
    this.action,
    this.foregroundColor,
  });

  static const maxWidth = 480.0;
  static const radius = 8.0;
  static const elevation = 6.0;

  final Widget content;
  final VoidCallback onClose;
  final bool busy;
  final Widget? action;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = foregroundColor ?? theme.colorScheme.onInverseSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(children: [
        if (busy) ...[
          SizedBox(
            width: 16,
            height: 16,
            child: MediaQuery.disableAnimationsOf(context)
                ? Icon(Icons.hourglass_empty_rounded, size: 16, color: color)
                : CircularProgressIndicator(strokeWidth: 2, color: color),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: DefaultTextStyle(
            style: theme.textTheme.bodySmall!.copyWith(color: color),
            child: content,
          ),
        ),
        if (action != null) action!,
        IconButton(
          tooltip: '关闭提示',
          color: color,
          onPressed: onClose,
          icon: const Icon(Icons.close_rounded, size: 18),
        ),
      ]),
    );
  }
}
