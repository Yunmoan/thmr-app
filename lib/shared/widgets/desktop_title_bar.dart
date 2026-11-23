// Windows 自绘标题栏，原生标题栏通过 window_manager 隐藏。

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/theme/thmr_theme.dart';
import 'focus_outline.dart';

class DesktopTitleBar extends StatelessWidget {
  const DesktopTitleBar({super.key, this.onMini});

  static const height = 38.0;

  /// 迷你模式入口(标题栏画中画按钮),回调由 ThmrApp 注入。
  final VoidCallback? onMini;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    return Container(
      height: height,
      color: tokens.pageBg,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 拖动区域覆盖整条标题栏的标志、文字和留白。窗口按钮位于区域之外，分别处理手势。
          Expanded(
            child: DragToMoveArea(
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
                ],
              ),
            ),
          ),
          if (onMini != null)
            _CaptionButton(
              icon: Icons.picture_in_picture_alt_rounded,
              label: '切换到迷你播放器',
              onTap: onMini,
            ),
          _CaptionButton(
            icon: Icons.remove_rounded,
            label: '最小化窗口',
            onTap: () => windowManager.minimize(),
          ),
          _CaptionButton(
            icon: Icons.crop_square_rounded,
            label: '最大化或还原窗口',
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
            label: '关闭窗口',
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
    required this.label,
    required this.onTap,
    this.danger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final tokens = Theme.of(context).thmr;
    // 标题栏位于 Navigator 和 Overlay 之外的 MaterialApp.builder 层，
    // Tooltip 所需的 Overlay 祖先在此处不可用。
    return FocusOutline(
        child: SizedBox(
      width: 44,
      height: DesktopTitleBar.height,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          hoverColor: danger
              ? const Color(0xFFC42B1C)
              : tokens.ink.withValues(alpha: 0.06),
          child: Semantics(
            label: label,
            button: true,
            child: Icon(icon, size: 16, color: tokens.mutedInk),
          ),
        ),
      ),
    ));
  }
}
