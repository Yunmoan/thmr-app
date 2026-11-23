import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/desktop_title_bar.dart';
import '../../shared/widgets/thmr_background.dart';
import 'mini_player.dart';
import '../large_screen/large_screen_controller.dart';

/// 同一原生窗口为主界面和带动画的迷你播放器保留固定位置。窗口的显示时机由原生切换流程控制。
class DesktopPlayerSurface extends ConsumerStatefulWidget {
  const DesktopPlayerSurface({
    super.key,
    required this.child,
    this.miniPlayer = const MiniPlayerWindow(),
  });

  final Widget child;
  final Widget miniPlayer;

  @override
  ConsumerState<DesktopPlayerSurface> createState() =>
      _DesktopPlayerSurfaceState();
}

class _DesktopPlayerSurfaceState extends ConsumerState<DesktopPlayerSurface> {
  Size? _mainContentSize;

  @override
  Widget build(BuildContext context) {
    final mini = ref.watch(miniPlayerProvider);
    final busy = ref.watch(miniTransitionBusyProvider);
    final large = ref.watch(largeScreenProvider.select((s) => s.active));
    return ExcludeFocus(
      excluding: busy,
      child: IgnorePointer(
        ignoring: busy,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Offstage(
              offstage: mini || large,
              child: const ThmrBackground(child: SizedBox.expand()),
            ),
            Padding(
              padding: mini || large
                  ? EdgeInsets.zero
                  : const EdgeInsets.only(top: DesktopTitleBar.height),
              child: TickerMode(
                enabled: !mini,
                child: LayoutBuilder(builder: (context, constraints) {
                  // 原生窗口边界包含非客户区边框，需保留 Flutter 内容的实际尺寸，
                  // 避免隐藏页面重新布局或滚动。
                  if (!mini) _mainContentSize = constraints.biggest;
                  final size = _mainContentSize ?? kMainMinWindowSize;
                  return Offstage(
                    offstage: mini,
                    child: ExcludeFocus(
                      excluding: mini,
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        minWidth: 0,
                        minHeight: 0,
                        maxWidth: double.infinity,
                        maxHeight: double.infinity,
                        child:
                            SizedBox.fromSize(size: size, child: widget.child),
                      ),
                    ),
                  );
                }),
              ),
            ),
            if (mini)
              MiniPlayerTransition(child: widget.miniPlayer)
            else if (!large)
              Align(
                alignment: Alignment.topCenter,
                child: DesktopTitleBar(
                  onMini: () =>
                      enterMiniMode(ref, MediaQuery.textScalerOf(context)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
