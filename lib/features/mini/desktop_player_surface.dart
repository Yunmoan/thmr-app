import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/widgets/desktop_title_bar.dart';
import '../../shared/widgets/thmr_background.dart';
import 'mini_player.dart';

/// One native window, with stable slots for the retained main tree and the
/// animated mini surface. Native presentation controls when this is exposed.
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
    return ExcludeFocus(
      excluding: busy,
      child: IgnorePointer(
        ignoring: busy,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Offstage(
              offstage: mini,
              child: const ThmrBackground(child: SizedBox.expand()),
            ),
            Padding(
              padding: mini ? EdgeInsets.zero : const EdgeInsets.only(top: 38),
              child: TickerMode(
                enabled: !mini,
                child: LayoutBuilder(builder: (context, constraints) {
                  // Native bounds include non-client borders; preserve the real
                  // Flutter content extent so hidden pages do not reflow/scroll.
                  if (!mini) _mainContentSize = constraints.biggest;
                  final size = _mainContentSize ?? kMainMinWindowSize;
                  return Offstage(
                    offstage: mini,
                    child: ExcludeFocus(
                      excluding: mini,
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
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
            else
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
