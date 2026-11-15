import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/platform/desktop_window.dart';
import 'large_screen_controller.dart';
import 'large_screen_player.dart';

/// Retain navigation, scroll offsets and focus without reflowing hidden pages
/// to the projector's dimensions. Only the presentation gets the new size.
class LargeScreenSurface extends ConsumerStatefulWidget {
  const LargeScreenSurface({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<LargeScreenSurface> createState() => _LargeScreenSurfaceState();
}

class _LargeScreenSurfaceState extends ConsumerState<LargeScreenSurface>
    with WindowListener {
  Size? _mainSize;
  FocusNode? _previousFocus;
  final _stageFocus = FocusScopeNode(debugLabel: '大屏模式');

  @override
  void initState() {
    super.initState();
    if (hasDesktopWindowControls) windowManager.addListener(this);
  }

  @override
  void dispose() {
    if (hasDesktopWindowControls) windowManager.removeListener(this);
    _stageFocus.dispose();
    super.dispose();
  }

  @override
  void onWindowLeaveFullScreen() =>
      ref.read(largeScreenProvider.notifier).nativeFullScreenChanged(false);

  @override
  void onWindowEnterFullScreen() =>
      ref.read(largeScreenProvider.notifier).nativeFullScreenChanged(true);

  @override
  Widget build(BuildContext context) {
    final active = ref.watch(largeScreenProvider.select((s) => s.active));
    ref.listen(largeScreenProvider.select((s) => s.active), (_, next) {
      if (next) _previousFocus = FocusManager.instance.primaryFocus;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || ref.read(largeScreenProvider).active != next) return;
        if (next) {
          _stageFocus.requestFocus();
        } else if (_previousFocus?.canRequestFocus == true) {
          _previousFocus!.requestFocus();
        }
      });
    });
    ref.listen(largeScreenProvider.select((s) => s.error), (_, error) {
      if (error != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error)));
      }
    });
    return LayoutBuilder(builder: (context, constraints) {
      if (!active) _mainSize = constraints.biggest;
      return Stack(fit: StackFit.expand, children: [
        Offstage(
          offstage: active,
          child: TickerMode(
            enabled: !active,
            child: ExcludeFocus(
              excluding: active,
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: 0,
                minHeight: 0,
                maxWidth: double.infinity,
                maxHeight: double.infinity,
                child: SizedBox.fromSize(
                    size: _mainSize ?? constraints.biggest,
                    child: widget.child),
              ),
            ),
          ),
        ),
        if (active)
          FocusScope(node: _stageFocus, child: const LargeScreenPlayer()),
      ]);
    });
  }
}
