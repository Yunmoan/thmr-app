import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/platform/desktop_window.dart';
import '../../core/theme/thmr_motion.dart';
import '../../core/platform/window_presentation.dart';
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
    with SingleTickerProviderStateMixin, WindowListener {
  Size? _mainSize;
  MediaQueryData? _mainMetrics;
  FocusNode? _previousFocus;
  final _stageFocus = FocusScopeNode(debugLabel: '大屏模式');
  late final LargeScreenController _mode;
  late final AnimationController _standard;
  bool _standardVisible = true;
  EdgeInsets _workAreaInsets = EdgeInsets.zero;
  int _metricsRevision = 0;

  Future<void> _refreshWorkArea() async {
    if (!mounted || Theme.of(context).platform != TargetPlatform.windows) {
      return;
    }
    final revision = ++_metricsRevision;
    try {
      final insets = await WindowPresentation().workAreaInsets();
      if (mounted &&
          revision == _metricsRevision &&
          insets != _workAreaInsets) {
        setState(() => _workAreaInsets = insets);
      }
    } catch (error) {
      debugPrint('Window work-area metrics unavailable: $error');
    }
  }

  @override
  void initState() {
    super.initState();
    _mode = ref.read(largeScreenProvider.notifier);
    final mode = ref.read(largeScreenProvider);
    _standardVisible = !mode.active && mode.contentVisible;
    _standard = AnimationController(
        vsync: this,
        duration: ThmrMotion.duration,
        value: _standardVisible ? 1 : 0);
    _mode.animateStandard = _animateStandard;
    if (hasDesktopWindowControls) windowManager.addListener(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _standard.value = _standardVisible ? 1 : 0;
    }
  }

  Future<void> _animateStandard(bool visible) async {
    if (!visible) _previousFocus = FocusManager.instance.primaryFocus;
    _standardVisible = visible;
    _standard.duration = ThmrMotion.of(context, exiting: !visible);
    try {
      await (visible ? _standard.forward() : _standard.reverse()).orCancel;
    } on TickerCanceled {
      // Disposal or enabling reduced motion completes the visible transition.
    }
  }

  @override
  void dispose() {
    if (hasDesktopWindowControls) windowManager.removeListener(this);
    if (_mode.animateStandard == _animateStandard) {
      _mode.animateStandard = null;
    }
    _standard.dispose();
    _stageFocus.dispose();
    super.dispose();
  }

  @override
  void onWindowLeaveFullScreen() {
    ref.read(largeScreenProvider.notifier).nativeFullScreenChanged(false);
    unawaited(_refreshWorkArea());
  }

  @override
  void onWindowEnterFullScreen() {
    ref.read(largeScreenProvider.notifier).nativeFullScreenChanged(true);
    unawaited(_refreshWorkArea());
  }

  @override
  void onWindowResize() => unawaited(_refreshWorkArea());
  @override
  void onWindowMoved() => unawaited(_refreshWorkArea());

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(largeScreenProvider);
    final active = mode.active;
    ref.listen(largeScreenProvider, (previous, next) {
      if (next.active && previous?.active != true) {
        unawaited(_refreshWorkArea());
      }
      if (next.active &&
          previous?.active != true &&
          _previousFocus?.context == null) {
        _previousFocus = FocusManager.instance.primaryFocus;
      }
      if (next.busy) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || ref.read(largeScreenProvider).active != next.active) {
          return;
        }
        if (next.active) {
          _stageFocus.requestFocus();
        } else if (_previousFocus?.context != null &&
            _previousFocus?.canRequestFocus == true) {
          _previousFocus!.requestFocus();
        }
      });
    });
    ref.listen(largeScreenProvider.select((s) => s.error), (_, error) {
      if (error != null) {
        ScaffoldMessenger.of(context)
            .showThmrSnackBar(context, SnackBar(content: Text(error)));
      }
    });
    return LayoutBuilder(builder: (context, constraints) {
      final metrics = MediaQuery.of(context);
      if (!active) {
        _mainSize = constraints.biggest;
        _mainMetrics = metrics;
      }
      final retainedMetrics = metrics.copyWith(
        size: _mainMetrics?.size,
        padding: _mainMetrics?.padding,
        viewPadding: _mainMetrics?.viewPadding,
        viewInsets: _mainMetrics?.viewInsets,
        systemGestureInsets: _mainMetrics?.systemGestureInsets,
      );
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
                    child: MediaQuery(
                        data: retainedMetrics,
                        child: IgnorePointer(
                            ignoring: mode.busy,
                            child: ThmrFadeSlide(
                                key: const ValueKey('standard-mode-transition'),
                                animation: _standard,
                                child: widget.child)))),
              ),
            ),
          ),
        ),
        if (active)
          FocusScope(
              node: _stageFocus,
              child: LargeScreenPlayer(safeInsets: _workAreaInsets)),
      ]);
    });
  }
}
