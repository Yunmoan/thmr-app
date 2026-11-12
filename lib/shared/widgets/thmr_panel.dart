import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/thmr_theme.dart';

/// 「和风纸面」面板:毛玻璃 + 细绯红描边 + 柔影。
/// 对应 Web 端 --panel-bg / --panel-border / --shadow。
class ThmrPanel extends StatelessWidget {
  const ThmrPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 10,
    this.onTap,
    this.blur = 8,
    this.frost = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final VoidCallback? onTap;
  final double blur;

  /// List rows should pass false: a translucent container skips the
  /// BackdropFilter pass (large lists of blurred rows tank the GPU,
  /// which also makes window dragging stutter).
  final bool frost;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    final body = Container(
      decoration: BoxDecoration(
        color: frost
            ? tokens.panelBg.withValues(alpha: 0.80)
            : tokens.solidPanel.withValues(alpha: 0.86),
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: tokens.panelBorder),
      ),
      padding: padding,
      child: child,
    );
    final panel = frost
        ? ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: BackdropFilter.grouped(
              filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
              // FadeTransition uses a save layer. Replace its filtered input
              // instead of blending that backdrop into the layer twice.
              blendMode: BlendMode.src,
              // Nested frosted panels must not share their parent's backdrop.
              child: BackdropGroup(child: body),
            ),
          )
        : ClipRRect(
            borderRadius: BorderRadius.circular(borderRadius),
            child: body,
          );
    if (onTap == null) return panel;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(borderRadius),
        child: panel,
      ),
    );
  }
}

/// 分区标题:宋体小标题 + 可选尾部动作。
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.action,
    this.trailing,
  });

  final String title;
  final Widget? action;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 10),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: tokens.ink,
                ),
          ),
          const Spacer(),
          if (trailing != null || action != null) trailing ?? action!,
        ],
      ),
    );
  }
}

/// 电台放送状态徽标。
class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key, this.active = true, this.switching = false});

  final bool active;
  final bool switching;

  @override
  Widget build(BuildContext context) {
    final color = active && !switching
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).thmr.mutedInk;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 5),
          Text(
            switching ? '切换中' : (active ? '放送中' : '待机'),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
          ),
        ],
      ),
    );
  }
}
