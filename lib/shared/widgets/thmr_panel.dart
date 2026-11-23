import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/thmr_theme.dart';
import 'focus_outline.dart';
import 'thmr_wallpaper.dart';

/// 「和风纸面」面板:毛玻璃 + 细绯红描边 + 柔影。
/// 对应 Web 端 --panel-bg / --panel-border / --shadow。
class ThmrPanel extends StatelessWidget {
  const ThmrPanel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 10,
    this.onTap,
    this.enabled = true,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final VoidCallback? onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.thmr;
    final radius = BorderRadius.circular(borderRadius);
    final sharedBlur = enabled ? ThmrWallpaper.frostOf(context) : null;
    final frostOpacity = theme.brightness == Brightness.light ? 0.60 : 0.80;
    final decoration = BoxDecoration(
      color: tokens.panelBg.withValues(alpha: frostOpacity),
      borderRadius: radius,
      border: Border.all(color: tokens.panelBorder),
    );
    final foreground = Padding(
      key: const ValueKey('panel-foreground'),
      padding: padding,
      child: BackdropGroup(child: child),
    );
    // 切换卡片装饰时，前景组件保留原来的位置。背景模糊独立绘制，
    // 避免模糊前景或与嵌套面板共用滤镜。
    final panel = ClipRRect(
      borderRadius: radius,
      clipBehavior: enabled ? Clip.antiAlias : Clip.none,
      child: Stack(children: [
        if (sharedBlur != null) Positioned.fill(child: sharedBlur),
        if (enabled)
          Positioned.fill(
            child: sharedBlur == null
                ? BackdropFilter.grouped(
                    filter: ImageFilter.blur(
                        sigmaX: thmrFrostSigma, sigmaY: thmrFrostSigma),
                    blendMode: BlendMode.srcOver,
                    child: DecoratedBox(decoration: decoration),
                  )
                : DecoratedBox(decoration: decoration),
          ),
        if (onTap == null)
          foreground
        else
          // 点击与聚焦反馈绘制在磨砂底图上方。
          Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              borderRadius: radius,
              child: foreground,
            ),
          ),
      ]),
    );
    if (onTap == null) return panel;
    return FocusOutline(radius: borderRadius, child: panel);
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
