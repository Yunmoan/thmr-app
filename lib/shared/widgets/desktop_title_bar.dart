// Custom Windows title bar (native one hidden via window_manager).

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/theme/thmr_theme.dart';

class DesktopTitleBar extends StatelessWidget {
  const DesktopTitleBar({super.key, this.onMini});

  /// 迷你模式入口(标题栏画中画按钮),回调由 ThmrApp 注入。
  final VoidCallback? onMini;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    return Container(
      height: 38,
      color: tokens.pageBg,
      child: Row(
        children: [
          const SizedBox(width: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Image.asset('assets/brand/logo.png',
                width: 22, height: 22),
          ),
          const SizedBox(width: 9),
          Text(
            '东方音乐电台 THMR',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tokens.mutedInk,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const Spacer(),
          // DragToMoveArea covers the empty middle so the window can be
          // dragged by any empty spot.
          const Expanded(child: DragToMoveArea(child: SizedBox.expand())),
          if (onMini != null)
            _CaptionButton(
              icon: Icons.picture_in_picture_alt_rounded,
              onTap: onMini,
            ),
          _CaptionButton(
            icon: Icons.remove_rounded,
            onTap: () => windowManager.minimize(),
          ),
          _CaptionButton(
            icon: Icons.crop_square_rounded,
            onTap: () async {
              if (await windowManager.isMaximized()) {
                await windowManager.unmaximize();
              } else {
                await windowManager.maximize();
              }
            },
          ),
          _CaptionButton(
            icon: Icons.close_rounded,
            danger: true,
            onTap: () => windowManager.close(),
          ),
        ],
      ),
    );
  }
}

class _CaptionButton extends StatelessWidget {
  const _CaptionButton({
    required this.icon,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    // 注意:标题栏位于 MaterialApp.builder 层(Navigator/Overlay 之外),
    // 不能使用 Tooltip(需要 Overlay 祖先),否则运行时报错。
    return SizedBox(
      width: 44,
      height: 38,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          hoverColor: danger
              ? const Color(0xFFC42B1C)
              : tokens.ink.withValues(alpha: 0.06),
          child: Icon(icon, size: 16, color: tokens.mutedInk),
        ),
      ),
    );
  }
}
