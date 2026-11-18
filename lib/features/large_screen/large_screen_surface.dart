import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/platform/desktop_window.dart';
import '../../core/platform/mobile_presentation.dart';
import '../../core/state/large_screen_settings.dart';
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
    with
        SingleTickerProviderStateMixin,
        WindowListener,
        WidgetsBindingObserver {
  Size? _mainSize;
  MediaQueryData? _mainMetrics;
  FocusNode? _previousFocus;
  final _stageFocus = FocusScopeNode(debugLabel: '大屏幕模式');
  final _stageMessenger = GlobalKey<ScaffoldMessengerState>();
  late final LargeScreenController _mode;
  late final AnimationController _standard;
  bool _standardVisible = true;
  EdgeInsets _workAreaInsets = EdgeInsets.zero;
  int _metricsRevision = 0;
  bool _foreground = WidgetsBinding.instance.lifecycleState == null ||
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
  bool? _keepScreenOn = false;
  Future<void> _keepScreenOnUpdates = Future.value();

  void _showMessage(String message) {
    void show() {
      if (!mounted) return;
      final messenger = ref.read(largeScreenProvider).active
          ? _stageMessenger.currentState
          : ScaffoldMessenger.maybeOf(context);
      messenger?.showThmrSnackBar(context, SnackBar(content: Text(message)));
    }

    if (ref.read(largeScreenProvider).active &&
        _stageMessenger.currentState == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => show());
    } else {
      show();
    }
  }

  void _syncKeepScreenOn({bool force = false}) {
    if (!hasMobilePresentation) return;
    final enabled = _foreground &&
        ref.read(largeScreenProvider).active &&
        ref.read(largeScreenSettingsProvider).keepScreenOn;
    if (!force && _keepScreenOn == enabled) return;
    _keepScreenOn = enabled;
    _queueKeepScreenOn(enabled);
  }

  void _queueKeepScreenOn(bool enabled) {
    _keepScreenOnUpdates = _keepScreenOnUpdates
        .then((_) => MobilePresentation().setKeepScreenOn(enabled))
        .catchError((Object error) {
      debugPrint('Screen wake lock failed: $error');
      if (!mounted) return;
      _keepScreenOn = null;
      if (enabled) {
        _showMessage('无法保持屏幕常亮，请重试。');
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _syncKeepScreenOn(force: _foreground);
  }

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
    WidgetsBinding.instance.addObserver(this);
    _mode = ref.read(largeScreenProvider.notifier);
    final mode = ref.read(largeScreenProvider);
    _standardVisible = !mode.active && mode.contentVisible;
    _standard = AnimationController(
        vsync: this,
        duration: ThmrMotion.duration,
        value: _standardVisible ? 1 : 0);
    _mode.animateStandard = _animateStandard;
    _mode.refreshMetrics = _refreshWorkArea;
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
    final duration = ThmrMotion.of(context, exiting: !visible);
    _standard.duration = duration;
    if (duration == Duration.zero || !TickerMode.valuesOf(context).enabled) {
      _standard.value = visible ? 1 : 0;
      return;
    }
    try {
      await (visible ? _standard.forward() : _standard.reverse())
          .orCancel
          .timeout(duration + const Duration(milliseconds: 200), onTimeout: () {
        // Never strand the retained shell at opacity zero if its ticker is
        // muted (for example while an opaque route covers this surface).
        _standard.stop();
        _standard.value = visible ? 1 : 0;
      });
    } on TickerCanceled {
      // Disposal or enabling reduced motion completes the visible transition.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (hasMobilePresentation) _queueKeepScreenOn(false);
    if (hasDesktopWindowControls) windowManager.removeListener(this);
    if (_mode.animateStandard == _animateStandard) {
      _mode.animateStandard = null;
    }
    if (_mode.refreshMetrics == _refreshWorkArea) {
      _mode.refreshMetrics = null;
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
      if (previous?.active != next.active) _syncKeepScreenOn();
      if (next.active && previous?.active != true) {
        unawaited(_refreshWorkArea());
      }
      if (next.active &&
          previous?.active != true &&
          _previousFocus?.context == null) {
        _previousFocus = FocusManager.instance.primaryFocus;
      }
      // A native collapse can publish a complete ordinary page while the
      // window is concealed. Paint it at full opacity before the raster fence.
      if (!next.active &&
          next.contentVisible &&
          (!next.busy || previous?.active == true)) {
        _standardVisible = true;
        _standard.value = 1;
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
    ref.listen(largeScreenSettingsProvider.select((s) => s.keepScreenOn),
        (_, __) => _syncKeepScreenOn());
    ref.listen(largeScreenProvider.select((s) => s.error), (_, error) {
      if (error != null) {
        _showMessage(error);
      }
    });
    return PopScope(
        canPop: !hasMobilePresentation || (!active && !mode.busy),
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && (active || mode.busy)) {
            unawaited(_mode.change(false));
          }
        },
        child: LayoutBuilder(builder: (context, constraints) {
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
                                    key: const ValueKey(
                                        'standard-mode-transition'),
                                    animation: _standard,
                                    child: widget.child)))),
                  ),
                ),
              ),
            ),
            if (active)
              FocusScope(
                  node: _stageFocus,
                  child: ScaffoldMessenger(
                      key: _stageMessenger,
                      child: LargeScreenPlayer(safeInsets: _workAreaInsets))),
          ]);
        }));
  }
}
